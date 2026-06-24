with source as (
    select * from {{ ref('policies') }}
),

staged as (
    select
        policy_id,
        policyholder_id,
        product_type,
        state,
        cast(effective_date as date)   as effective_date,
        cast(expiration_date as date)  as expiration_date,
        cast(written_premium as decimal(12,2)) as written_premium,
        status,
        -- derived fields
        datediff('day', cast(effective_date as date), cast(expiration_date as date)) as policy_term_days,
        case
            when status = 'active' then true
            else false
        end as is_active
    from source
)

select * from staged

