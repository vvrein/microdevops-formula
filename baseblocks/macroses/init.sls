{% from "baseblocks/macroses/docker_macro.sls" import docker_extract %}
{% set docker_extract = docker_extract %}

{% load_yaml as typemap %}
install_dir: file
download: file
untar: cmd
move: file
venv: cmd
docker_extract: cmd
{% endload %}


{%- macro defaults(data, shared, prefix=[], suffix=[], req=none) %}

  {# get tag from github into data["version"] #}
  {%- if data.get("source") and data.get("store") == "github" %}

    {%- if data.get("version") in ["latest", "latest_release"] %}
      {%- set github_url = "https://api.github.com/repos/{repo}/releases/latest".format(repo="/".join(data["source"].split("/")[3:5])) %}
      {%- set response = salt.http.query(github_url) %}
      {%- if not "error" in response and "body" in response %}
        {%- set body = response["body"] | load_json %}
        {%- do data.update({"version": body["name"]}) %}
      {%- else %}
        {{ raise("\n>>> CRITICAL: error occured during fetching \"latest\" release tag\n>>> remote response: " ~ response ~ "\n>>> remote url: " ~ tags_url ) }}
      {%- endif %}

    {%- elif data.get("version") in ["latest_tag"] %}
      {%- set github_url = "https://api.github.com/repos/{repo}/tags?per_page=1".format(repo="/".join(data["source"].split("/")[3:5])) %}
      {%- set response = salt.http.query(github_url) %}
      {%- if not "error" in response and "body" in response %}
        {%- set body = response["body"] | load_json %}
        {%- do data.update({"version": body[0]["name"]}) %}
      {%- else %}
        {{ raise("\n>>> CRITICAL: error occured during fetching \"latest\" release tag\n>>> remote response: " ~ response ~ "\n>>> remote url: " ~ tags_url ) }}
      {%- endif %}
    {%- endif %}
    
    {%- do shared.update({"version": data["version"], "tag": data["version"], "tag_vstrip": data["version"].lstrip("v")}) %}

  {%- endif %}

  {%- for name in data.keys() %}
    {%- if data.get(name) %}
      {%- do shared.update({name: data[name].format(**shared) }) %}
    {%- endif %}
  {%- endfor %}

{%- endmacro %}


{%- macro install_dir(data, shared, prefix=[], suffix=[], req=none) %}
{{ "_".join(prefix + ["install_dir"] + suffix) }}:
  file.directory:
    - name: {{ data.get("name", shared["install_dir"]) }}
    - user: {{ shared.get("user", "") }}
    - group: {{ shared.get("group", "") }}
    - makedirs: True
{%- endmacro %}


{%- macro download(data, shared, prefix=[], suffix=[], req=none) %}
  {%- set dst = data.get("destination", shared["file"]).format(**shared) %}
  {%- set src = data.get("source", shared["source"]).format(**shared) %}
  {%- set hash = data.get("source_hash", shared.get("source_hash", "")).format(**shared) %}
{{ "_".join(prefix + ["download"] + suffix) }}:
  file.managed:
    - name: {{ dst }}
    - source: {{ src }}
  {%- if hash %}
    - source_hash: {{ hash }} 
  {%- else %}
    - skip_verify: True
  {%- endif %}
    - user: {{ shared.get("user", "") }}
    - group: {{ shared.get("group", "") }}
    - makedirs: True
  {% for name, value in req.items() %}
    - {{ name }}: {{ value }}
  {% endfor %}
{%- endmacro %}


{%- macro untar(data, shared, prefix=[], suffix=[], req=none) %}
  {%- set archive = data.get("archive", shared["file"]).format(**shared) %}
  {%- set target = data.get("target", shared["install_dir"]).format(**shared) %}
  {%- set unpack = data.get("unpack","").format(**shared) %}
{{ "_".join(prefix + ["untar"] + suffix) }}:
  cmd.run:
    - name: |
        tar {{ data.get("args","") }} --no-same-owner \
          --directory {{ target }} \
          --extract \
          --file {{ archive }} \
          {{ unpack }}
    - user: {{ shared.get("user", "") }}
    - group: {{ shared.get("group", "") }}
    - shell: /bin/bash
  {% for name, value in req.items() %}
    - {{ name }}: {{ value }}
  {% endfor %}
  {%- if shared.get("version") is not match("latest") %}
    - unless: 
      - "[[ $(<{{ target }}/.salt_version_info) =~ {{ shared["version"] }} ]]"
    {%- for unless in data.get("unless", {}).values() %}
      - {{ unless.format(**shared) }}
    {%- endfor %}
  file.managed:
    - name: {{ target }}/.salt_version_info
    - contents: "{{ shared["version"] }}"
  {%- endif %}
{%- endmacro %}


{%- macro move(data, shared, prefix=[], suffix=[], req=none) %}
{{ "_".join(prefix + ["move"] + suffix) }}:
  file.rename:
    - name: "{{ data["dst"].format(**shared) }}"
    - source: "{{ data["src"].format(**shared) }}"
    - force: True
    - makedirs: True
  {% for name, value in req.items() %}
    - {{ name }}: {{ value }}
  {% endfor %}
{%- endmacro %}


{%- macro venv(data, shared, prefix=[], suffix=[], req=none) %}
  {%- set dir = data.get("path", shared["install_dir"] + "/venv").format(**shared) %}
  {%- set upperdir = dir.rsplit("/", maxsplit=1)[0] %}
  {%- set requirements_txt = data.get("requirements_txt", shared.get("requirements_txt", "")) %}
  {%- set requirements = data.get("requirements",[]) %}

{{ "_".join(prefix + ["venv"] + suffix) }}:
  pkg.installed:
    - name: python3-venv
  {%- if requirements %}
  file.managed:
    - name: {{ upperdir }}/.salt_requirements.txt
    - user: {{ shared.get("user", "") }}
    - group: {{ shared.get("group", "") }}
    - makedirs: True
    - contents: |
        {{ "\n".join(requirements) | indent(8) }}
  {%- endif %}
  cmd.run:
    - shell: /bin/bash
    - cwd: {{ upperdir }}
    - user: {{ shared.get("user", "") }}
    - group: {{ shared.get("group", "") }}
    - name: |
        python3 -m venv --clear {{ dir }}
  {%- if requirements %}
        {{ dir }}/bin/pip --require-virtualenv install -r {{ upperdir }}/.salt_requirements.txt
  {%- endif %}
  {%- if requirements_txt %}
        {{ dir }}/bin/pip --require-virtualenv install -r {{ requirements_txt }}
  {%- endif %}
    - unless:
      - "[[ $({{ dir }}/bin/python -V) =~ Python ]]"
  {%- if requirements %}
      - "[[ ! $({{ dir }}/bin/pip freeze -r {{ upperdir }}/.salt_requirements.txt 2>&1) =~ WARNING ]]"
  {%- endif %}
  {%- if requirements_txt %}
      - "[[ ! $({{ dir }}/bin/pip freeze -r {{ requirements_txt }} 2>&1) =~ WARNING ]]"
  {%- endif %}
  {% for name, value in req.items() %}
    - {{ name }}: {{ value }}
  {% endfor %}
{%- endmacro %}

