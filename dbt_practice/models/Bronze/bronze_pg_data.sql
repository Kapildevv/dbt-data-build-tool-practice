select 
* 
from 
{{ source('default', 'pg_data') }}