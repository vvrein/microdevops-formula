{% import_yaml "victoriametrics/defaults.yaml" as defaults %}

{% for vm_name, vm_data in pillar.get("vmserver", {}).items() %}

  {% set vm_name = vm_name.replace(".","_") %}
  {% set vm_data = vm_data | tojson | replace("__VM_NAME__", vm_name) | load_json %}

  {% set service_name = "victoriametrics" if vm_name == "main" else "victoriametrics-" ~ vm_name %}
  {% set service_target = vm_data["service"].get("target", defaults["service"]["target"]) %}

  {% do defaults["args"].update({"storageDataPath": defaults["args"]["storageDataPath"].format(vm_name=vm_name)}) %}
  {% do defaults["args"].update(vm_data.get("args", {})) %}
  {% do vm_data["args"].update(defaults["args"]) %}

  {% set vmargslist = [] %}
  {% for k, v in vm_data["args"].items() %}
    {% do vmargslist.append("-" ~ k ~ " " ~ v) %}
  {% endfor %}

  {% if vm_data["service"].get("platform", none) in defaults["platforms"] %}
    {% set platform = vm_data["service"]["platform"] %}
    {% set source = defaults["platforms"][platform]["source"].format(release=vm_data["service"]["version"], arch=grains["osarch"]) %}
    {% set source_hash = defaults["platforms"][platform]["source_hash"].format(release=vm_data["service"]["version"], arch=grains["osarch"]) %}
  {% else %}
    {% set source = vm_data["service"]["source"] %}
    {% set source_hash = vm_data["service"].get("source_hash", none) %}
  {% endif %}
  {% set archive_name = defaults["salt_cache_dir"] ~ "/" ~ source.split("/")[-1] %}


  {%- with %}
    {%- set files = vm_data.get("files", {}) %}
    {%- set extloop = vm_name %} 
    {%- include "_include/file_manager/init.sls" %}
  {%- endwith %}

  {%- include "victoriametrics/nginx/init.sls" %}

victoriametrics_{{ vm_name }}_archive:
  file.managed:
    - name: {{ archive_name }}
    - source: {{ source }}
    - makedirs: True
    {% if source_hash %}
    - source_hash: {{ source_hash }}
    {% else %}
    - skip_verify: True
    {% endif %}

victoriametrics_{{ vm_name }}_data_dir:
  file.directory:
    - name: {{ vm_data["args"]["storageDataPath"] }}
    - makedirs: True
    - user: root
    - group: root

victoriametrics_{{ vm_name }}_target_dir:
  file.directory:
    - name: {{ service_target.rsplit("/",maxsplit=1)[0] }}
    - makedirs: True
    - user: root
    - group: root

victoriametrics_{{ vm_name }}_archive_extract:
  archive.extracted:
    - name: {{ service_target.rsplit("/",maxsplit=1)[0] }}
    - source: {{ archive_name }}
    - skip_verify: True
    - enforce_toplevel: False
    - user: root
    - group: root
    {% if vm_data.get("service", {}).get("version", none) %}
    - onlyif:
      - "! {{ service_target }} -version | grep -q '{{ vm_data["service"]["version"] }}' "
    {% endif %}

victoriametrics_{{ vm_name }}_binary:
  file.rename:
    - name: {{ service_target }}
    - source: {{ service_target.rsplit("/",maxsplit=1)[0] ~ "/victoria-metrics-prod" }}
    - force: True


victoriametrics_{{ vm_name }}_systemd_unit:
  file.managed:
    - name: /etc/systemd/system/{{ service_name }}.service
    - contents: |
        [Unit]
        Description=VictoriaMetrics
        After=network.target
        
        [Service]
        Type=simple
        StartLimitBurst=5
        StartLimitInterval=0
        Restart=on-failure
        RestartSec=1
        ExecStart={{ service_target }} {{ " ".join(vmargslist) }}
        
        [Install]
        WantedBy=multi-user.target

victoriametrics_{{ vm_name }}_systemd_daemon-reload:
  service.running:
    - name: {{ service_name }}.service
    - enable: True
    - watch:
      - file: /etc/systemd/system/{{ service_name }}.service

{% endfor %}
