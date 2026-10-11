with dataset_cutoff as (

    select
        max(date_parse(date_format(order_ts, '%Y%m%d'), '%Y%m%d'))
            as observation_date
    from ORDERS

),

valid_orders as (

    select
        u.user_id,
        date_parse(u.signup_date, '%Y%m%d') as signup_date,

        o.order_id,
        o.retailer_id,
        date_parse(
            date_format(o.order_ts, '%Y%m%d'),
            '%Y%m%d'
        ) as order_date,

        lower(o.status) as status,

        r.retailer_name,
        r.category,
        r.commission_pct

    from USERS u

    join ORDERS o
        on u.user_id = o.user_id

    left join RETAIL r
        on o.retailer_id = r.retailer_id

    cross join dataset_cutoff d

    where lower(o.status) <> 'cancelled'

      -- valid post-signup transaction
      and date_parse(
            date_format(o.order_ts, '%Y%m%d'),
            '%Y%m%d'
          ) >= date_parse(u.signup_date, '%Y%m%d')

      -- transaction within first 60 days
      and date_diff(
            'day',
            date_parse(u.signup_date, '%Y%m%d'),
            date_parse(
                date_format(o.order_ts, '%Y%m%d'),
                '%Y%m%d'
            )
          ) between 0 and 60

      -- only mature users
      and date_parse(u.signup_date, '%Y%m%d')
            <= date_add(
                'day',
                -60,
                d.observation_date
            )

),

ranked_orders as (

    select
        *,

        row_number() over (
            partition by user_id
            order by order_date, order_id
        ) as txn_no

    from valid_orders

),

first_second as (

    select
        user_id,

        max(
            case when txn_no = 1
            then order_date end
        ) as first_order_date,

        max(
            case when txn_no = 2
            then order_date end
        ) as second_order_date,

        max(
            case when txn_no = 1
            then category end
        ) as first_category,

        max(
            case when txn_no = 2
            then category end
        ) as second_category,

        max(
            case when txn_no = 1
            then retailer_name end
        ) as first_retailer,

        max(
            case when txn_no = 2
            then retailer_name end
        ) as second_retailer

    from ranked_orders

    group by 1

)

----A : FIND MEDIAN 1st to 2nd order TIME LAPSED>
-- select

--     count(*) as first_time_transactors,

--     count(second_order_date) as repeat_transactors,

--     round(
--         100.0 * count(second_order_date)
--         / count(*),
--         2
--     ) as repeat_rate_60d,

--     approx_percentile(
--         date_diff(
--             'day',
--             first_order_date,
--             second_order_date
--         ),
--         0.25
--     ) as p25_days_to_repeat,

--     approx_percentile(
--         date_diff(
--             'day',
--             first_order_date,
--             second_order_date
--         ),
--         0.50
--     ) as median_days_to_repeat,

--     approx_percentile(
--         date_diff(
--             'day',
--             first_order_date,
--             second_order_date
--         ),
--         0.75
--     ) as p75_days_to_repeat

-- from first_second;

---B :: First Category wise repeat rates.
-- select
--     first_category,

--     count(*) as first_time_transactors,

--     count(second_order_date) as repeat_transactors,

--     round(
--         100.0 * count(second_order_date)
--         / count(*),
--         2
--     ) as repeat_rate_60d,

--     approx_percentile(
--         case
--             when second_order_date is not null
--             then date_diff(
--                 'day',
--                 first_order_date,
--                 second_order_date
--             )
--         end,
--         0.50
--     ) as median_days_to_repeat

-- from first_second

-- group by 1

-- order by repeat_rate_60d desc;


--C - same vs cross Category
-- select

--     count(*) as repeat_users,

--     count(
--         case
--             when first_category = second_category
--             then 1
--         end
--     ) as same_category_repeat_users,

--     count(
--         case
--             when first_category <> second_category
--             then 1
--         end
--     ) as cross_category_repeat_users,

--     round(
--         100.0 *
--         count(
--             case
--                 when first_category = second_category
--                 then 1
--             end
--         )
--         / count(*),
--         2
--     ) as same_category_repeat_pct,

--     round(
--         100.0 *
--         count(
--             case
--                 when first_category <> second_category
--                 then 1
--             end
--         )
--         / count(*),
--         2
--     ) as cross_category_repeat_pct

-- from first_second

-- where second_order_date is not null;


---D - If cross , then WHICH category will the 2nd order come from ?
select
    first_category,
    second_category,

    count(*) as repeat_users,

    round(
        100.0 * count(*)
        / sum(count(*)) over (
            partition by first_category
        ),
        2
    ) as pct_of_first_category_repeats

from first_second

where second_order_date is not null

group by 1,2

order by
    first_category,
    repeat_users desc;
