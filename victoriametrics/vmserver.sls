{% import_yaml "victoriametrics/defaults.yaml" as defaults %}

{% for vm_name, vm_content in pillar.get("vmserver", {}).items() %}

  {% set vm_content = vm_content | tojson | replace("__VM_NAME__", vm_name) | load_json %}

  {% set service_target = vm_content["service"].get("target", defaults["service"]["target"]) %}
  {% set unitname = "victoriametrics.service" if vm_name == "main" else "victoriametrics-" ~ vm_name ~ ".service" %}

  {% do defaults["args"].update({"storageDataPath": defaults["args"]["storageDataPath"].format(vm_name=vm_name)}) %}
  {% do defaults["args"].update(vm_content.get("args", {})) %}
  {% do vm_content["args"].update(defaults["args"]) %}

  {% set vmargslist = [] %}
  {% for k, v in vm_content["args"].items() %}
    {% do vmargslist.append("-" ~ k ~ " " ~ v) %}
  {% endfor %}

  {% if vm_content["service"].get("platform", none) in defaults["platforms"] %}
    {% set platform = vm_content["service"]["platform"] %}
    {% set source = defaults["platforms"][platform]["source"].format(release=vm_content["service"]["version"], arch=grains["osarch"]) %}
    {% set source_hash = defaults["platforms"][platform]["source_hash"].format(release=vm_content["service"]["version"], arch=grains["osarch"]) %}
  {% else %}
    {% set source = vm_content["service"]["source"] %}
    {% set source_hash = vm_content["service"].get("source_hash", none) %}
  {% endif %}
  {% set archive_name = defaults["salt_cache_dir"] ~ "/" ~ source.split("/")[-1] %}


  {%- with %}
    {%- set files = vm_content.get("files", {}) %}
    {%- set extloop = vm_name %} 
    {%- include "_include/file_manager/init.sls" %}
  {%- endwith %}


vmserver_{{ vm_name }}_archive:
  file.managed:
    - name: {{ archive_name }}
    - source: {{ source }}
    - makedirs: True
    {% if source_hash %}
    - source_hash: {{ source_hash }}
    {% else %}
    - skip_verify: True
    {% endif %}

vmserver_{{ vm_name }}_data_dir:
  file.directory:
    - name: {{ vm_content["args"]["storageDataPath"] }}
    - makedirs: True
    - user: root
    - group: root

vmserver_{{ vm_name }}_target_dir:
  file.directory:
    - name: {{ service_target.rsplit("/",maxsplit=1)[0] }}
    - makedirs: True
    - user: root
    - group: root

vmserver_{{ vm_name }}_archive_extract:
  archive.extracted:
    - name: {{ service_target.rsplit("/",maxsplit=1)[0] }}
    - source: {{ archive_name }}
    - skip_verify: True
    - enforce_toplevel: False
    - user: root
    - group: root
    {% if vm_content.get("service", {}).get("version", none) %}
    - onlyif:
      - "! {{ service_target }} -version | grep -q '{{ vm_content["service"]["version"] }}' "
    {% endif %}

vmserver_{{ vm_name }}_binary:
  file.rename:
    - name: {{ service_target }}
    - source: {{ service_target.rsplit("/",maxsplit=1)[0] ~ "/victoria-metrics-prod" }}
    - force: True


vmserver_{{ vm_name }}_systemd_unit:
  file.managed:
    - name: /etc/systemd/system/{{ unitname }}
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

vmserver_{{ vm_name }}_systemd_daemon-reload:
  service.running:
    - name: {{ unitname }}
    - enable: True
    - watch:
      - file: /etc/systemd/system/{{ unitname }}

{% endfor %}
