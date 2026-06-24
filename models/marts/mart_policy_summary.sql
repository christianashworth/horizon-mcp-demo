-- mart_policy_summary.sql
-- Grain: one row per policy
-- Joins policy data with claim counts and total losses

with policies as (
    select * from {{ ref('stg_policies') }}
),

claims as (
    select * from {{ ref('stg_claims') }}
),

premiums as (
    select * from {{ ref('stg_premiums') }}
),

claims_by_policy as (
    select
        policy_id,
        count(*)                        as claim_count,
        sum(incurred_loss)              as total_incurred_loss,
        sum(paid_loss)                  as total_paid_loss,
        sum(case_reserve)               as total_case_reserve,
        sum(case when is_open then 1 else 0 end) as open_claim_count,
        sum(case when is_at_fault then 1 else 0 end) as at_fault_claim_count
    from claims
    group by policy_id
),

premiums_by_policy as (
    select
        policy_id,
        sum(earned_premium) as total_earned_premium
    from premiums
    group by policy_id
),

final as (
    select
        p.policy_id,
        p.policyholder_id,
        p.product_type,
        p.state,
        p.effective_date,
        p.expiration_date,
        p.written_premium,
        p.status,
        p.is_active,
        coalesce(ep.total_earned_premium, 0)     as total_earned_premium,
        coalesce(c.claim_count, 0)               as claim_count,
        coalesce(c.total_incurred_loss, 0)       as total_incurred_loss,
        coalesce(c.total_paid_loss, 0)           as total_paid_loss,
        coalesce(c.total_case_reserve, 0)        as total_case_reserve,
        coalesce(c.open_claim_count, 0)          as open_claim_count,
        coalesce(c.at_fault_claim_count, 0)      as at_fault_claim_count,
        -- loss ratio: incurred losses / earned premium
        -- defined as: total incurred loss divided by total earned premium for the policy period to date
        case
            when coalesce(ep.total_earned_premium, 0) = 0 then null
            else round(coalesce(c.total_incurred_loss, 0) / ep.total_earned_premium, 4)
        end as loss_ratio
    from policies p
    left join claims_by_policy c
        on p.policy_id = c.policy_id
    left join premiums_by_policy ep
        on p.policy_id = ep.policy_id
)

select * from final

