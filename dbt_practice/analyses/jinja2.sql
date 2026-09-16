{%- set letters = ['a','b','c','d','e','f'] -%}

{%- for i in letters -%}

 {% if i !='a' %} 
  {{- i -}} 
 {% else %} 
   first letter {{ i }}
  
 {% endif %}

{% endfor %}