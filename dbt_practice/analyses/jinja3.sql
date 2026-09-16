{% set start=1 %}
{% set max_value=100 %}

{% set column_required = ['order_id', 'order_status', 'total_amount'] %}


Select 

{% for x in column_required %}
   {{ x }}{% if not loop.last %},{% endif %}
{% endfor %}

from {{ ref('bronze_transactions') }}

{% if start ==1 %}
 where total_amount < {{ max_value }}
{% endif %}