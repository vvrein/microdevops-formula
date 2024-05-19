{% set vm_name = vm_name.replace(".","_") %}
{% set vm_data = vm_data | tojson | replace("__VM_NAME__", vm_name) | load_json %}

{% set service_name = kind if vm_name == "main" else kind ~ "-" ~ vm_name %}
{% set service_target = vm_data["service"].get("target", defaults["service"][kind]["target"]) %}

{% if vm_data["service"].get("platform", none) in defaults["platforms"] %}
  {% set platform = vm_data["service"]["platform"] %}
  {% set source = defaults["platforms"][platform]["source"].format(release=vm_data["service"]["version"], name=defaults["service"][kind]["name"], arch=grains["osarch"]) %}
  {% set source_hash = defaults["platforms"][platform]["source_hash"].format(release=vm_data["service"]["version"], name=defaults["service"][kind]["name"], arch=grains["osarch"]) %}
{% else %}
  {% set source = vm_data["service"]["source"] %}
  {% set source_hash = vm_data["service"].get("source_hash", none) %}
{% endif %}
{% set archive_name = defaults["salt_cache_dir"] ~ "/" ~ source.split("/")[-1] %}

{% do defaults["service"][kind]["args"].update(vm_data.get("args", {})) %}
{% do vm_data["args"].update(defaults["service"][kind]["args"]) %}
{% set arg_storage = defaults["service"][kind]["arg_storage"] %}
{% set data_dir = vm_data.get(arg_storage, defaults["service"][kind]["args"][arg_storage]).format(vm_name=vm_name) %}
{% do vm_data["args"].update({arg_storage: data_dir}) %}

{% set vmargslist = [] %}
{% for k, v in vm_data.get("args", {}).items() %}
  {% do vmargslist.append("-" ~ k ~ " " ~ v) %}
{% endfor %}

{%- set files = vm_data.get("files", {}) %}
{%- set extloop = vm_name %} 
{%- include "_include/file_manager/init.sls" %}

{% if kind == "vmserver" and vm_data.get("nginx", {}) and vm_data.get("nginx",{}).get("enabled", True) %}
  {%- include "victoriametrics/nginx/init.sls" %}
{% endif %}

{{ kind }}_{{ vm_name }}_storage_dir:
  file.directory:
    - name: {{ vm_data["args"][arg_storage] }}
    - makedirs: True
    - user: root
    - group: root

{{ kind }}_{{ vm_name }}_archive:
  file.managed:
    - name: {{ archive_name }}
    - source: {{ source }}
    - makedirs: True
    {% if source_hash %}
    - source_hash: {{ source_hash }}
    {% else %}
    - skip_verify: True
    {% endif %}

{{ kind }}_{{ vm_name }}_target_dir:
  file.directory:
    - name: {{ service_target }}
    - makedirs: True
    - user: root
    - group: root

{% if kind == "vmagent" and vm_data["service"].get("vmutils", True) %}
  {% set unpack_filename = "" %}
  {% set check_filename = "vmctl" %}
{% else %}
  {% set unpack_filename = defaults["service"][kind]["file_name"] ~ "-prod" %}
  {% set check_filename = defaults["service"][kind]["file_name"] %}
{% endif %}

{{ kind }}_{{ vm_name }}_archive_extract:
  cmd.run:
    - name: |
        tar --transform 's/-prod//' --no-same-owner --directory {{ service_target }} --extract --file {{ archive_name }} {{ unpack_filename }}
    - user: root
    - group: root
    - shell: /bin/bash
    - require:
      - file: {{ kind }}_{{ vm_name }}_archive
    {% if vm_data.get("service", {}).get("version", none) %}
    - onlyif:
      - "! {{ service_target }}/{{ check_filename }} -version | grep -q '{{ vm_data["service"]["version"] }}'"
    {% endif %}

{% if kind == "vmagent" and not vm_data["service"].get("vmutils_only", False) %}
{{ kind }}_{{ vm_name }}_systemd_unit:
  file.managed:
    - name: /etc/systemd/system/{{ service_name }}.service
    - require:
      - cmd: {{ kind }}_{{ vm_name }}_archive_extract
    - contents: |
        [Unit]
        Description=VictoriaMetrics {{ kind }}
        After=network.target
        
        [Service]
        Type=simple
        StartLimitBurst=5
        StartLimitIntervalSec=0
        Restart=on-failure
        RestartSec=1
        ExecStart={{ service_target }}/{{ defaults["service"][kind]["file_name"] }} {{ " ".join(vmargslist) }}
        
        [Install]
        WantedBy=multi-user.target

{{ kind }}_{{ vm_name }}_systemd_daemon-reload:
  service.running:
    - name: {{ service_name }}.service
    - enable: True
    - watch:
      - file: {{ kind }}_{{ vm_name }}_systemd_unit
      - cmd: {{ kind }}_{{ vm_name }}_archive_extract
{% endif %}
