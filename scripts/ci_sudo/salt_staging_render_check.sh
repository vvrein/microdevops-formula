#!/bin/bash

# $1 should be $CI_COMMIT_REF_NAME
# $2 should be $CI_COMMIT_SHA
# $3 should be $CI_COMMIT_BEFORE_SHA
# $4 should be $CI_REPOSITORY_URL

if [ "_$1" = "_" ]; then 
	stdbuf -oL -eL echo 'ERROR: $1 ($CI_COMMIT_REF_NAME) is not set'
	exit 1
fi
if [ "_$2" = "_" ]; then 
	stdbuf -oL -eL echo 'ERROR: $2 ($CI_COMMIT_SHA) is not set'
	exit 1
fi
if [ "_$3" = "_" ]; then 
	stdbuf -oL -eL echo 'ERROR: $3 ($CI_COMMIT_BEFORE_SHA) is not set'
	exit 1
fi
if [ "_$4" = "_" ]; then 
	stdbuf -oL -eL echo 'ERROR: $4 ($CI_REPOSITORY_URL) is not set'
	exit 1
fi

WORK_DIR=/tmp/salt_staging/$1
mkdir -p ${WORK_DIR}
cd ${WORK_DIR} || ( stdbuf -oL -eL echo "ERROR: ${WORK_DIR} does not exist"; exit 1 )

# Use locking with timeout to align concurrent git checkouts in a line
LOCK_DIR=${WORK_DIR}/.ci.lock
LOCK_RETRIES=1
LOCK_RETRIES_MAX=60
SLEEP_TIME=5
until mkdir "$LOCK_DIR" || (( LOCK_RETRIES == LOCK_RETRIES_MAX ))
do
	stdbuf -oL -eL echo "NOTICE: Acquiring lock failed on $LOCK_DIR, sleeping for ${SLEEP_TIME}s"
	let "LOCK_RETRIES++"
	sleep ${SLEEP_TIME}
done
if [ ${LOCK_RETRIES} -eq ${LOCK_RETRIES_MAX} ]; then
	stdbuf -oL -eL echo "ERROR: Cannot acquire lock after ${LOCK_RETRIES} retries, giving up on $LOCK_DIR"
	exit 1
else
	stdbuf -oL -eL echo "NOTICE: Successfully acquired lock on $LOCK_DIR"
	trap 'rm -rf "$LOCK_DIR"' 0
fi

GRAND_EXIT=0
rm -f /srv/scripts/ci_sudo/$(basename $0).out
exec > >(tee /srv/scripts/ci_sudo/$(basename $0).out)
exec 2>&1

# Update local repo to commit
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: git -C ${WORK_DIR}/srv pull || git clone $4 ${WORK_DIR}/srv"
( stdbuf -oL -eL git -C ${WORK_DIR}/srv pull || stdbuf -oL -eL git clone $4 ${WORK_DIR}/srv ) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: git fetch && git checkout -B $1 origin/$1"
( stdbuf -oL -eL git fetch && stdbuf -oL -eL git checkout -B $1 origin/$1 ) || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: git submodule update --recursive -f --checkout"
stdbuf -oL -eL git submodule update --recursive -f --checkout || GRAND_EXIT=1
stdbuf -oL -eL echo "---"
stdbuf -oL -eL echo "NOTICE: CMD: .githooks/post-merge"
stdbuf -oL -eL .githooks/post-merge || GRAND_EXIT=1

# Release the lock after checkout, let tests run even if repo updated in the time of testing
rm -rf "$LOCK_DIR"

# Get changed files from the last push and try to render some of them
for FILE in $(git diff-tree --no-commit-id --name-only -r $2 $3); do
	stdbuf -oL -eL echo "NOTICE: checking file ${WORK_DIR}/srv/${FILE}"
	if [[ -e "${WORK_DIR}/srv/${FILE}" ]]; then
		if [[ ${FILE} == *.sls || ${FILE} == *.jinja ]]; then
			if stdbuf -oL -eL salt-call --retcode-passthrough slsutil.renderer ${WORK_DIR}/srv/${FILE}; then
				stdbuf -oL -eL echo "NOTICE: slsutil.renderer of file ${WORK_DIR}/srv/${FILE} succeeded"
			else
				GRAND_EXIT=1
				stdbuf -oL -eL echo "ERROR: slsutil.renderer of file ${WORK_DIR}/srv/${FILE} failed"
			fi
		else
			stdbuf -oL -eL echo "NOTICE: ${WORK_DIR}/srv/${FILE} is neither .sls nor .jinja"
		fi
	else
		stdbuf -oL -eL echo "NOTICE: ${WORK_DIR}/srv/${FILE} does not exist"
	fi
done

grep -q "ERROR" ${WORK_DIR}/srv/scripts/ci_sudo/$(basename $0).out && GRAND_EXIT=1

exit $GRAND_EXIT
