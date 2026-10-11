-- ============================================================
-- 01_data_quality.sql
-- Purpose:
-- 1. Understand scale / date coverage
-- 2. Find duplicates
-- 3. Find invalid user-order relationships
-- 4. Check money fields
-- 5. Check channel consistency
-- ============================================================

--------All below checks were found to be expected, no data anomaly reported.

-- ------------------------------------------------------------
-- 1. USERS - BASIC PROFILE
-- ------------------------------------------------------------

select
    count(*) as rows,
    count(distinct user_id) as unique_users,
    min(signup_date) as min_signup_date,
    max(signup_date) as max_signup_date
from USERS;

---user maturity
select case 
when diff<30 then 1
when diff<60 then 2
when diff<90 then 3
when diff<120 then 4
else 5 end as months
, count(user_id)
from 
(
select 
date_diff('day' , date_parse(signup_date,'%Y%m%d') , current_date) diff , 
user_id
from USERS
)
group by 1


-- ------------------------------------------------------------
-- 2. DUPLICATE USERS
-- expected: zero rows
-- ------------------------------------------------------------

select
    user_id,
    count(*) as cnt
from USERS
group by 1
having count(*) > 1



-- ------------------------------------------------------------
-- 3. USER DISTRIBUTION BY CHANNEL
-- ------------------------------------------------------------

select
    acquisition_channel,
    count(*) as users,
    round(
        100.0 * count(*) / sum(count(*)) over (),
        2
    ) as user_share_pct
from USERS
group by 1
order by users desc


-- ------------------------------------------------------------
-- 4. ORDERS - BASIC PROFILE
-- ------------------------------------------------------------

select
    count(*) as rows,
    count(distinct order_id) as unique_orders,
    count(distinct user_id) as ordering_users,
    min(order_ts) as min_order_ts,
    max(order_ts) as max_order_ts
from ORDERS


-- ------------------------------------------------------------
-- 5. DUPLICATE ORDER IDs
-- expected: zero rows
-- ------------------------------------------------------------

select
    order_id,
    count(*) as cnt
from ORDERS
group by 1
having count(*) > 1



-- ------------------------------------------------------------
-- 6. ORDER STATUS DISTRIBUTION
-- ------------------------------------------------------------

select
    status,
    count(*) as orders,
    count(distinct user_id) as users,
    round(sum(cast(order_value as double)), 2) as order_value,
    round(sum(cast(commission as double)), 2) as commission,
    round(sum(cast(cashback as double)), 2) as cashback
from ORDERS
group by 1
order by orders desc


-- ------------------------------------------------------------
-- 7. ORDERS WHERE USER DOES NOT EXIST
-- expected: 0
-- ------------------------------------------------------------

select
    count(*) as untagged_orders
from ORDERS o
left join USERS u
    on o.user_id = u.user_id
where u.user_id is null


-- ------------------------------------------------------------
-- 8. ORDERS BEFORE USER SIGNUP
-- ordering allowed pre signup ? / anonymous state orders? -- not found any
-- ------------------------------------------------------------

select
    count(*) as orders_before_signup,
    count(distinct o.user_id) as impacted_users
from ORDERS o
join USERS u
    on o.user_id = u.user_id
where date_format(o.order_ts,'%Y%m%d') < u.signup_date


-- ------------------------------------------------------------
-- 9. -ve Values or profit > revenue
-- ------------------------------------------------------------

select
    count(*) as suspicious_orders
from ORDERS
where
       cast(order_value as double) <= 0
    or cast(commission as double) < 0
    or cast(cashback as double) < 0
    or cast(cashback as double) > cast(commission as double);


-- ------------------------------------------------------------
-- 10. CONFIRMED ORDER REVENUE SANITY CHECK
-- ------------------------------------------------------------

select
    count(*) as confirmed_orders,
    round(
        sum(
            cast(commission as double)
            - cast(cashback as double)
        ),
        2
    ) as confirmed_revenue,
    round(
        avg(
            cast(commission as double)
            - cast(cashback as double)
        ),
        2
    ) as revenue_per_confirmed_order
from ORDERS
where lower(status) = 'confirmed'


-- ------------------------------------------------------------
-- 11. MARKETING DATA COVERAGE
-- ------------------------------------------------------------

select
    min(week_start) as min_week,
    max(week_start) as max_week,
    count(*) as rows
from MARKETING


-- ------------------------------------------------------------
-- 12. MARKETING PERFORMANCE BY CHANNEL
-- ------------------------------------------------------------

select
    channel,
    round(sum(cast(spend as double)), 2) as spend,
    sum(cast(installs as bigint)) as installs,

    round(
        sum(cast(spend as double))
        / nullif(sum(cast(installs as bigint)), 0),
        2
    ) as cost_per_install

from MARKETING
group by 1
order by spend desc


-- ------------------------------------------------------------
-- 13. CHANNELS IN USERS BUT NOT MARKETING
-- Organic/referral may intentionally appear here
-- ------------------------------------------------------------

select distinct acquisition_channel
from USERS

except

select distinct channel
from MARKETING


-- ------------------------------------------------------------
-- 14. CHANNELS IN MARKETING BUT NOT USERS [ideally Null]
-- ------------------------------------------------------------

select distinct channel
from MARKETING

except

select distinct acquisition_channel
from USERS


-- ------------------------------------------------------------
-- 15. MARKETING ROWS WITH WEIRD VALUES
-- ------------------------------------------------------------

select *
from MARKETING
where
       cast(spend as double) < 0
    or cast(installs as bigint) < 0
    or (
        cast(spend as double) > 0
        and cast(installs as bigint) = 0
    )


-- ------------------------------------------------------------
-- 16. RETAILER DUPLICATES
-- ------------------------------------------------------------

select
    retailer_id,
    count(*) as cnt
from jumbo_write.c_retail1
group by 1
having count(*) > 1


-- ------------------------------------------------------------
-- 17. ORDER from RETAILERS NOT IN RETAILER MASTER
-- ------------------------------------------------------------

select
    count(*) as orders_with_unknown_retailer
from ORDERS o
left join jumbo_write.c_retail1 r
    on o.retailer_id = r.retailer_id
where r.retailer_id is null


-- ------------------------------------------------------------
-- 18. DATASET OBSERVATION / MATURITY CHECK [will be using this for all analysis where only mature/established data should be taken.
--
-- Critical for 60-day metrics.
-- ------------------------------------------------------------

with cutoff as (
    select
        max(cast(order_ts as date)) as observation_date
    from ORDERS
)

select
    observation_date,
    date_add('day', -60, observation_date) as latest_fully_mature_signup_date
from cutoff
