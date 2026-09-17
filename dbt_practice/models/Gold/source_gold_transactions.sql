with txn_data as
(select
*,
row_number() over (partition by customer_id order by order_date desc) as row_num
from {{ref('bronze_transactions')}})

select 
customer_id, 
order_id,
order_date,
row_num
 from 
 txn_data 
 where row_num = 1
