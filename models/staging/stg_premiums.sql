with source as (
    select * from {{ ref('premiums') }}
),

staged as (
    select
        premium_id,
        policy_id,
        earning_month,
        cast(earned_premium as decimal(12,2)) as earned_premium,
        -- parse year and month for easier aggregation
        cast(left(earning_month, 4) as integer)  as earning_year,
        cast(right(earning_month, 2) as integer) as earning_month_num
    from source
)

select * from staged

