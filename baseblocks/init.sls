{%- import_yaml "baseblocks/defaults.yaml" as def_yml %}
{%- import "baseblocks/macroses/init.sls" as macroses %}

{%- set type = "baseblocks" %}
{%- for top_name, top_data in pillar.get(type, {}).items() %}

  {%- set subtype = top_data.get("type", "fallback") %}
  {%- set order = top_data.get("order", def_yml["order"]) %}
  {%- set prefix = [type, top_name] %}

  {%- set exclude = ["type", "order", "defaults"] %}

  {%- set top_data = salt.defaults.merge(def_yml[type][subtype], top_data, in_place=False) %}

  {%- set shared = {"name": top_name,
                    "type": type,
                    "subtype": subtype,
                    "osarch": grains["osarch"],
                    "cpuarch": grains["cpuarch"],
                    "kernel": grains["kernel"],
                    "kernel_lower": grains["kernel"].lower(),
                    "salt_cache_dir": def_yml["salt_cache_dir"] } 
  %}

  {%- do macroses["defaults"](top_data.get("defaults", {}), shared, prefix) %}

  {# iterate over groups #}
  {%- for group_name, group_data in top_data.items() if group_name not in exclude %}

    {%- do prefix.append(group_name) %}

    {# order is empty - then iterate in pillar sequence #}
    {%- if not order %}
      {%- set order = group_data.keys() %}
    {%- endif %}
    
    {# merge global defaults with group defaults and handle them #}
    {%- set group_defaults = salt.defaults.merge(top_data.get("defaults", {}), group_data.get("defaults",{}), in_place=False) %}
    {%- set shared = salt.defaults.deepcopy(shared) %}
    {%- do macroses["defaults"](group_defaults, shared, prefix) %}

    {# iterate over steps in group #}
    {%- for key in order if key in group_data and key not in exclude %}

      {# each step require previous #}
      {%- set req = {} %}
      {% if not loop.first %}
        {% set req = { "require": [{macroses["typemap"][loop.previtem]: "_".join(prefix + [loop.previtem]) ~ "*" }] }  %}
      {% endif %}
      
      {# step args can be absent (none) #}
      {%- set args = group_data[key] %}
      {%- if args is none %}
        {%- set args = {} %}
      {%- endif %}
 
      {# step args can be list or dict, reduce to list #}
      {%- if args is mapping %}
        {%- set args = [args] %}
      {%- endif %}

      {# if args > 1 add indexes to id #}
      {%- for arg in args %}

        {%- set suffix = [] %}
        {%- if loop.length > 1 %}
          {%- do suffix.append(loop.index0 | string) %}
        {%- endif %}

        {# steps can be skipped #}
        {%- if not arg.get("skip", False) %}
          {{ macroses[key](arg, shared, prefix, suffix, req=req) }}
        {%- endif %}

      {%- endfor %}

    {%- endfor %}

  {%- endfor %}

{%- endfor %}

