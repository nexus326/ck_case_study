
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
   -- cast(u.signup_date as date) as signup_date,

    date_trunc(
        'week',
        date_parse(u.signup_date ,'%Y%m%d')
    ) as signup_week,

    u.acquisition_channel,
    u.city_tier,
    u.device_os,

    m.first_order_ts,

    -- case
    --     when m.first_order_ts is not null
    --     then date_diff(
    --         'day',
    --         cast(u.signup_date as date),
    --         cast(m.first_order_ts as date)
    --     )
    -- end as days_to_first_order,

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

select
    signup_week,

    count(distinct user_id) as cohort_users,

    count(
        distinct case
            when transactions_60d >= 1
            then user_id
        end
    ) as first_transactors,

    count(
        distinct case
            when transactions_60d >= 2
            then user_id
        end
    ) as repeat_transactors,

    100.0 *
    count(
        distinct case
            when transactions_60d >= 2
            then user_id
        end
    )
    /
    nullif(
        count(
            distinct case
                when transactions_60d >= 1
                then user_id
            end
        ),
        0
    ) as repeat_rate

from user_level_final
where mature_60d = 1
group by 1
order by 1
