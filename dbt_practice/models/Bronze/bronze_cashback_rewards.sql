
{{ config(materialized='view') }}

select 
* 
from 
{{ source('default', 'cashback_rewards') }}