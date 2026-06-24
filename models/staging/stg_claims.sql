with source as (
    select * from {{ ref('claims') }}
),

staged as (
    select
        claim_id,
        policy_id,
        cast(claim_date as date)  as claim_date,
        cast(close_date as date)  as close_date,
        claim_type,
        cast(incurred_loss as decimal(12,2)) as incurred_loss,
        cast(paid_loss as decimal(12,2))     as paid_loss,
        status,
        at_fault,
        -- derived fields
        case
            when status = 'open' then true
            else false
        end as is_open,
        case
            when at_fault = 'Y' then true
            else false
        end as is_at_fault,
        cast(incurred_loss as decimal(12,2))
            - cast(paid_loss as decimal(12,2)) as case_reserve
    from source
)

select * from staged

