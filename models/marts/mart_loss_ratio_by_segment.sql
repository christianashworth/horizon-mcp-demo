-- mart_loss_ratio_by_segment.sql
-- Grain: one row per product_type / state combination
-- Core governed metric: loss ratio
-- Definition: incurred losses (paid + case reserve) divided by earned premium
-- Scope: all policies with at least one month of earned premium

with policy_summary as (
    select * from {{ ref('mart_policy_summary') }}
),

segmented as (
    select
        product_type,
        state,
        count(policy_id)                        as policy_count,
        sum(written_premium)                    as total_written_premium,
        sum(total_earned_premium)               as total_earned_premium,
        sum(claim_count)                        as total_claims,
        sum(total_incurred_loss)                as total_incurred_loss,
        sum(total_paid_loss)                    as total_paid_loss,
        sum(total_case_reserve)                 as total_case_reserve,
        sum(open_claim_count)                   as open_claims,
        -- loss ratio at segment level
        -- numerator: total incurred losses (paid losses + case reserves)
        -- denominator: total earned premium
        -- this is the standard actuarial definition used across this model
        case
            when sum(total_earned_premium) = 0 then null
            else round(sum(total_incurred_loss) / sum(total_earned_premium), 4)
        end as loss_ratio,
        -- claim frequency: claims per 100 policies
        case
            when count(policy_id) = 0 then null
            else round(sum(claim_count) / count(policy_id) * 100, 2)
        end as claim_frequency_per_100,
        -- average incurred loss per claim
        case
            when sum(claim_count) = 0 then null
            else round(sum(total_incurred_loss) / sum(claim_count), 2)
        end as avg_incurred_loss_per_claim
    from policy_summary
    group by product_type, state
)

select * from segmented
order by product_type, state

