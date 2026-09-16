Select *
from {{ ref('bronze_transactions') }}
where total_amount < 0