
with dataset_cutoff as (

    select
        max(order_ts) as observation_date
    from ORDERS

),

orders_clean as (

    select
        o.order_id,
        o.user_id,
        o.retailer_id,
        date_format(order_ts ,'%Y%m%d') as order_ts,
      order_value,
       commission,
      cashback,
        lower(o.status) as status

    from ORDERS o

),

marketing as (

    select
        channel,
        sum(cast(spend as double)) as spend,
        sum(cast(installs as bigint)) as installs
    from MARKETING
    group by 1

),

user_order_metrics as (

    select
        u.user_id,

        -- First tracked non-cancelled transaction
        min(
            case
                when o.status <> 'cancelled'
                and o.order_ts >= u.signup_date
                then o.order_ts
            end
        ) as first_order_ts,


        -- ----------------------------------------------------
        -- Activation flags
        -- ----------------------------------------------------

        max(
            case
                when o.status <> 'cancelled'
                 and o.order_ts >= u.signup_date
                 and date_parse(o.order_ts,'%Y%m%d') <
                     date_add(
                         'day',
                         7,
                         date_parse(u.signup_date,'%Y%m%d')
                     )
                then 1
                else 0
            end
        ) as activated_7d,


        max(
            case
                when o.status <> 'cancelled'
                 and o.order_ts >= u.signup_date
                 and date_parse(o.order_ts,'%Y%m%d') <
                     date_add(
                         'day',
                         14,
                         date_parse(u.signup_date,'%Y%m%d')
                     )
                then 1
                else 0
            end
        ) as activated_14d,


        max(
            case
                when o.status <> 'cancelled'
                 and o.order_ts >= u.signup_date
                 and date_parse(o.order_ts,'%Y%m%d') <
                     date_add(
                         'day',
                         30,
                         date_parse(u.signup_date,'%Y%m%d')
                     )
                then 1
                else 0
            end
        ) as activated_30d,


        -- ----------------------------------------------------
        -- Transaction counts within 60 days
        -- Cancelled transactions excluded
        -- ----------------------------------------------------

        count(
            distinct case
                when o.status <> 'cancelled'
                 and o.order_ts >= u.signup_date
                 and date_parse(o.order_ts,'%Y%m%d') <
                     date_add(
                         'day',
                         61,
                         date_parse(u.signup_date,'%Y%m%d')
                     )
                then o.order_id
            end
        ) as transactions_60d,


        -- Confirmed transactions only

        count(
            distinct case
                when o.status = 'confirmed'
                 and o.order_ts >= u.signup_date
                 and date_parse(o.order_ts,'%Y%m%d') <
                     date_add(
                         'day',
                         61,
                         date_parse(u.signup_date,'%Y%m%d')
                     )
                then o.order_id
            end
        ) as confirmed_orders_60d,


        -- ----------------------------------------------------
        -- Revenue:
        -- commission - cashback
        -- confirmed orders only
        -- ----------------------------------------------------

        sum(
            case
                when o.status = 'confirmed'
                 and o.order_ts >= u.signup_date
                 and date_parse(o.order_ts,'%Y%m%d') <
                     date_add(
                         'day',
                         61,
                         date_parse(u.signup_date,'%Y%m%d')
                     )
                then o.commission - o.cashback
                else 0
            end
        ) as revenue_60d

    from USERS u

    left join orders_clean o
        on u.user_id = o.user_id

    group by 1

)

,user_level_final as (

select
    u.user_id,
    cast(u.signup_date as date) as signup_date,

    date_trunc(
        'week',
        cast(u.signup_date as date)
    ) as signup_week,

    u.acquisition_channel,
    u.city_tier,
    u.device_os,

    m.first_order_ts,

    case
        when m.first_order_ts is not null
        then date_diff(
            'day',
            cast(u.signup_date as date),
            cast(m.first_order_ts as date)
        )
    end as days_to_first_order,

    coalesce(m.activated_7d, 0) as activated_7d,
    coalesce(m.activated_14d, 0) as activated_14d,
    coalesce(m.activated_30d, 0) as activated_30d,

    coalesce(m.transactions_60d, 0) as transactions_60d,
    coalesce(m.confirmed_orders_60d, 0) as confirmed_orders_60d,
    coalesce(m.revenue_60d, 0) as revenue_60d,

    case
        when coalesce(m.transactions_60d,0) >= 2
        then 1
        else 0
    end as repeat_transactor_60d,


    -- --------------------------------------------------------
    -- Whether user had enough time to observe full 60 days
    -- --------------------------------------------------------

    case
        when --1=1 
        date_parse(u.signup_date, '%Y%m%d') --cast(u.signup_date as date)
             <= date_add(
                    'day',
                    -60,
                    d.observation_date
                )
        then 1
        else 0
    end as mature_60d,

    d.observation_date

from USERS u

left join user_order_metrics m
    on u.user_id = m.user_id

cross join dataset_cutoff d

)

-- select
--     approx_percentile(days_to_first_order, 0.25) as p25,
--     approx_percentile(days_to_first_order, 0.50) as p50,
--     approx_percentile(days_to_first_order, 0.75) as p75,
--     approx_percentile(days_to_first_order, 0.90) as p90
-- from user_level_final
-- where days_to_first_order is not null

,channel_user_Acq_final as (
SELECT
    acquisition_channel,
    COUNT(user_id) AS users,
    count(distinct case when repeat_transactor_60d = 1 then user_id end ) repeat_txn_user,
    count(distinct case when repeat_transactor_60d = 1 and mature_60d=1 then user_id end ) repeat_txn_mature_user,
    
    sum(activated_7d) as activated_7d,
    sum(activated_14d) as activated_14d,
    --ACTIVATION rate main : 30d
    sum(activated_30d) as activated_30d,
    100.00 * SUM(activated_30d) / COUNT(*) AS activation_rate,
    SUM(cast(revenue_60d as int)) AS revenue_60d,
    round(SUM(revenue_60d) / COUNT(*),1) AS revenue_per_user_60d,
    sum(confirmed_orders_60d)confirmed_orders_60d,
    --mature users only
    sum( case when mature_60d = 1 then cast(revenue_60d as int) else 0 end) as mature_user_revenue_60d,
    count( distinct case when mature_60d = 1 then user_id end) as mature_users,
    round(1.00 *sum(case when mature_60d = 1 then revenue_60d else 0 end)
    /nullif(count( distinct case when mature_60d = 1 then user_id end), 0),1) as revenue_per_mature_user_60d
    ----
FROM user_level_final
GROUP BY 1
)



select
    u.acquisition_channel,
    coalesce(m.installs, 0) as installs,
    coalesce(m.spend, 0) as spend,
    u.users signup_users,
    -- Cost per install
    round(
        m.spend / nullif(m.installs, 0),
        1
    ) as cost_per_install,

    -- Useful reconciliation metric:
    -- paid acquisition cost per signup
    round(
        m.spend / nullif(u.users, 0),
        1
    ) as cost_per_signup,
    
        -- Main revenue desicion metric!
    round(
        m.spend / nullif(u.activated_30d,0),
        1
    ) as cost_per_activated_user,

    u.activated_30d as activated_30d_users,
    u.activation_rate as activation_rate_30d_pct,

revenue_60d,
revenue_per_user_60d,
confirmed_orders_60d,

mature_user_revenue_60d,
mature_users,
revenue_per_mature_user_60d,



    -- Sensitivity checks
   round(
        100.0 * u.activated_7d
        / nullif(u.users,0),
        2
    ) as activation_rate_7d_pct,

    round(
        100.0 * u.activated_14d
        / nullif(u.users,0),
        2
    ) as activation_rate_14d_pct

from channel_user_Acq_final u
left join marketing m
    on lower(u.acquisition_channel) = lower(m.channel)

