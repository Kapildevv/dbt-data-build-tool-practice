with txn_data as
(select distinct
customer_id, 
date_trunc('month', date(substr(order_date,1,10))) as order_month
from {{ref('bronze_transactions')}})


select 
customer_id,
date(order_month) as order_month,
date(lag(order_month) over (partition by customer_id order by order_month)) as prev_order_month

from txn_data
