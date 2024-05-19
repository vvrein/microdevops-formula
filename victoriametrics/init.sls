{% import_yaml "victoriametrics/defaults.yaml" as defaults %}

{% set kind = "vmserver" %}
{% for vm_name, vm_data in pillar.get(kind, {}).items() %}
  {%- include "victoriametrics/setup.sls" %}
{% endfor %}

{% set kind = "vmagent" %}
{% for vm_name, vm_data in pillar.get(kind, {}).items() %}
  {%- include "victoriametrics/setup.sls" %}
{% endfor %}
