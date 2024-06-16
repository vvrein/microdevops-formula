{%- macro docker_extract(data, shared, prefix=[], suffix=[], req=none) %}
  {%- set dir = data.get("dir", shared["install_dir"] + "/output").format(**shared) %}
  {%- set upperdir = dir.rsplit("/", maxsplit=1)[0] %}
  {%- set platform = data.get("platform", "{kernel_lower}/{osarch}").format(**shared) %}
  {%- set source = data.get("source", shared["source"]).format(**shared) %}
  {%- set version = data.get("version", shared["version"]).format(**shared) %}

{{ "_".join(prefix + ["docker_extract"] + suffix) }}:
  cmd.script:
    - name: salt://baseblocks/files/docker-image-extract
    - args: "-o {{ dir }} -p {{ platform }} {{ source }}:{{ version }}"
    - shell: /bin/bash
    - user: {{ shared.get("user", "") }}
    - group: {{ shared.get("group", "") }}
  {% for name, value in req.items() %}
    - {{ name }}: {{ value }}
  {% endfor %}
  {%- if data.get("clean", False) %}
  file.absent:
    - name: {{ dir }}
    - order: last
  {%- endif %}
{%- endmacro %}
