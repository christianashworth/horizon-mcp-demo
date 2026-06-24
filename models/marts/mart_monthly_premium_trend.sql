-- mart_monthly_premium_trend.sql
-- Grain: one row per product_type / state / earning_month
-- Shows earned premium development over time with running claim activity

with premiums as (
    select * from {{ ref('stg_premiums') }}
),

policies as (
    select
        policy_id,
        product_type,
        state
    from {{ ref('stg_policies') }}
),

claims as (
    select
        policy_id,
        claim_date,
        incurred_loss,
        left(cast(claim_date as varchar), 7) as claim_month
    from {{ ref('stg_claims') }}
),

premiums_with_segment as (
    select
        pr.premium_id,
        pr.policy_id,
        pr.earning_month,
        pr.earning_year,
        pr.earning_month_num,
        pr.earned_premium,
        p.product_type,
        p.state
    from premiums pr
    inner join policies p
        on pr.policy_id = p.policy_id
),

claims_by_month_segment as (
    select
        c.claim_month,
        p.product_type,
        p.state,
        count(*)            as claims_reported,
        sum(c.incurred_loss) as incurred_loss_reported
    from claims c
    inner join policies p
        on c.policy_id = p.policy_id
    group by c.claim_month, p.product_type, p.state
),

earned_by_month_segment as (
    select
        earning_month,
        product_type,
        state,
        sum(earned_premium)     as earned_premium,
        count(distinct policy_id) as active_policy_count
    from premiums_with_segment
    group by earning_month, product_type, state
),

final as (
    select
        e.earning_month,
        e.product_type,
        e.state,
        e.earned_premium,
        e.active_policy_count,
        coalesce(c.claims_reported, 0)          as claims_reported,
        coalesce(c.incurred_loss_reported, 0)   as incurred_loss_reported,
        case
            when e.earned_premium = 0 then null
            else round(coalesce(c.incurred_loss_reported, 0) / e.earned_premium, 4)
        end as monthly_loss_ratio
    from earned_by_month_segment e
    left join claims_by_month_segment c
        on e.earning_month = c.claim_month
        and e.product_type = c.product_type
        and e.state = c.state
)

select * from final
order by earning_month, product_type, state

