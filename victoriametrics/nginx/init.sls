
{% from "acme/macros.jinja" import verify_and_issue %}

{%- set cert_prefix = "victoriametrics" %}
{%- set template = "vhost.jinja" %}

vmserver_{{ vm_name }}_nginx_install:
  pkg.installed:
    - pkgs:
      - nginx
      - apache2-utils

vmserver_{{ vm_name }}_htpasswd_dir:
  file.directory:
    - name: /etc/nginx/htpasswd

  {%- for auth in vm_content["nginx"].get("auth_basic",[]) %}
vmserver_{{ vm_name }}_basic_auth_{{ auth["username"] }}:
  webutil.user_exists:
    - name: {{ auth["username"] }}
    - password: {{ auth["password"] }}
    - htpasswd_file: {{ "/etc/nginx/htpasswd/victoriametrics_" ~ vm_name }}
    - force: true
  {%- endfor %}

  {% for server in vm_content["nginx"]["servers"] if "acme_account" in server.keys() %}

    {{ verify_and_issue(server["acme_account"], cert_prefix, server["names"]) }}

  {%- endfor %}

vmserver_{{ vm_name }}_nginx_files_1:
  file.managed:
    - name: {{ "/etc/nginx/sites-available/victoriametrics-" ~ vm_name ~ ".conf" }}
    - source: salt://loki/nginx/{{ template }}
    - template: jinja
    - context:
        cert_prefix: {{ cert_prefix }}
        vm_name: {{ vm_name }}
        vm_content: {{ vm_content }}

vmserver_{{ vm_name }}_nginx_files_symlink_1:
  file.symlink:
    - name: {{ "/etc/nginx/sites-enabled/victoriametrics-" ~ vm_name ~ ".conf" }}
    - target: {{ "/etc/nginx/sites-available/victoriametrics-" ~ vm_name ~ ".conf" }}

vmserver_{{ vm_name }}_nginx_files_2:
  file.absent:
    - name: /etc/nginx/sites-enabled/default

vmserver_{{ vm_name }}_nginx_reload:
  cmd.run:
    - runas: root
    - name: service nginx configtest && service nginx reload

vmserver_{{ vm_name }}_nginx_reload_cron:
  cron.present:
    - name: /usr/sbin/service nginx configtest && /usr/sbin/service nginx reload
    - identifier: nginx_reload
    - user: root
    - minute: 15
    - hour: 6
