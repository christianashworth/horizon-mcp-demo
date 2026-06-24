# Horizon MCP Demo - Project Setup Script
# Run this from inside C:\Users\christian.ashworth\horizon-mcp-demo

Write-Host 'Creating .gitignore...'
@'
# dbt
target/
dbt_packages/
logs/

# DuckDB database file (generated locally by dbt run)
*.duckdb
*.duckdb.wal

# Python
.venv/
__pycache__/
*.pyc
*.pyo
.env

# OS
.DS_Store
Thumbs.db

'@ | Set-Content -Path '.gitignore' -Encoding UTF8

Write-Host 'Creating README.md...'
@'
# horizon-mcp-demo

A working demonstration of a governed semantic layer exposed via MCP, built on dbt Core and DuckDB. Models a P&C insurance company with policies, claims, and earned premium data.

Used as research and reference material for Horizon Data Partners white paper: *The Governed Data Layer: Why AI Agents Fail Without One, and How to Build It.*

---

## What this demonstrates

1. **A governed semantic layer** — dbt models with enforced metric definitions for loss ratio, earned premium, incurred loss, and claim frequency
2. **An MCP server** — a lightweight Python server that reads dbt artifacts and exposes governed tools to any MCP-compatible agent
3. **An agent demo** — Claude querying the semantic layer via MCP, answering business questions using governed metric definitions rather than raw tables

---

## Project structure

```
horizon-mcp-demo/
├── seeds/                        # Raw fake data (CSV)
│   ├── policies.csv
│   ├── claims.csv
│   └── premiums.csv
├── models/
│   ├── staging/                  # Cleaned, typed source models
│   │   ├── stg_policies.sql
│   │   ├── stg_claims.sql
│   │   └── stg_premiums.sql
│   ├── marts/                    # Governed analytical models
│   │   ├── mart_policy_summary.sql
│   │   ├── mart_loss_ratio_by_segment.sql
│   │   └── mart_monthly_premium_trend.sql
│   └── schema.yml                # Metric definitions and column docs
├── mcp_server/
│   └── horizon_mcp_server.py     # MCP server exposing dbt artifacts
├── scripts/
│   └── run_agent.py              # Agent demo using Claude + MCP
├── dbt_project.yml
├── profiles.yml                  # DuckDB connection config
└── requirements.txt
```

---

## Setup (Windows)

### Prerequisites
- Python 3.12 (not 3.13+)
- Git

### 1. Clone the repo

```powershell
git clone https://github.com/christianashworth/horizon-mcp-demo.git
cd horizon-mcp-demo
```

### 2. Create and activate virtual environment

```powershell
py -3.12 -m venv .venv
.venv\Scripts\activate
```

If you get a script execution error:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3. Install dependencies

```powershell
python -m pip install --upgrade pip
pip install -r requirements.txt
```

### 4. Verify dbt installed correctly

```powershell
dbt --version
```

You should see dbt Core 1.11.x with the duckdb plugin.

### 5. Build the database

```powershell
dbt seed
dbt run
```

This creates `horizon_insurance.duckdb` in the project root and builds all models.

### 6. Verify the build

```powershell
dbt test
```

All tests should pass.

---

## Running the agent demo

### Set your Anthropic API key

```powershell
$env:ANTHROPIC_API_KEY = "your-api-key-here"
```

### Run the demo

```powershell
python scripts/run_agent.py
```

The agent will work through five questions, calling MCP tools to inspect the semantic layer and query the database. You will see each tool call logged as it happens.

---

## Metric definitions

All metric definitions are governed at the semantic layer. The MCP server exposes them via the `get_metric_definitions` tool. Core definitions:

| Metric | Definition | Governance note |
|--------|-----------|-----------------|
| **loss_ratio** | incurred losses / earned premium | Never use written premium as denominator. Never average policy-level ratios. |
| **incurred_loss** | paid losses + case reserves | Do not use paid_loss alone as a proxy. |
| **earned_premium** | premium allocated to the measurement period | Use earned, not written, in all loss ratio denominators. |
| **claim_frequency_per_100** | (claims / policies) × 100 | Segment level only. |
| **case_reserve** | incurred_loss − paid_loss | Zero on closed claims. |

---

## Notes

- The `.duckdb` file is excluded from version control (see `.gitignore`). It is generated locally by `dbt seed && dbt run`.
- The MCP server opens DuckDB in read-only mode. Write operations are blocked at the tool layer as well.
- The `profiles.yml` is included in the repo because it contains no credentials — DuckDB is a local file with no authentication.

'@ | Set-Content -Path 'README.md' -Encoding UTF8

Write-Host 'Creating dbt_project.yml...'
@'
name: 'horizon_insurance'
version: '1.0.0'
config-version: 2

profile: 'horizon_insurance'

model-paths: ["models"]
analysis-paths: ["analyses"]
seed-paths: ["seeds"]
target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

seeds:
  horizon_insurance:
    +schema: raw

models:
  horizon_insurance:
    staging:
      +schema: staging
      +materialized: view
    marts:
      +schema: marts
      +materialized: table

'@ | Set-Content -Path 'dbt_project.yml' -Encoding UTF8

Write-Host 'Creating mcp_server\horizon_mcp_server.py...'
@'
"""
horizon_mcp_server.py

A lightweight MCP server that exposes the Horizon Insurance dbt project
to Claude (or any MCP-compatible agent). Reads dbt artifacts generated
by `dbt run` and serves them as governed tools.

Tools exposed:
  - list_models: returns all dbt models with descriptions
  - get_model_details: returns full schema, columns, and metric definitions for a model
  - query_data: executes a read-only SQL query against the DuckDB database
  - get_metric_definitions: returns all governed metric definitions from schema.yml

Usage:
  python mcp_server/horizon_mcp_server.py
"""

import json
import os
import duckdb
from pathlib import Path
from mcp.server.fastmcp import FastMCP

# ── paths ──────────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).parent.parent
MANIFEST_PATH = PROJECT_ROOT / "target" / "manifest.json"
DB_PATH = PROJECT_ROOT / "horizon_insurance.duckdb"

# ── MCP server ─────────────────────────────────────────────────────────────────
mcp = FastMCP("Horizon Insurance Data")


def load_manifest() -> dict:
    """Load the dbt manifest.json artifact."""
    if not MANIFEST_PATH.exists():
        raise FileNotFoundError(
            f"manifest.json not found at {MANIFEST_PATH}. "
            "Run `dbt run` from the project root first."
        )
    with open(MANIFEST_PATH, "r") as f:
        return json.load(f)


def get_db_connection():
    """Return a read-only DuckDB connection."""
    if not DB_PATH.exists():
        raise FileNotFoundError(
            f"Database not found at {DB_PATH}. "
            "Run `dbt seed && dbt run` from the project root first."
        )
    return duckdb.connect(str(DB_PATH), read_only=True)


# ── tools ──────────────────────────────────────────────────────────────────────

@mcp.tool()
def list_models() -> str:
    """
    List all dbt models in the Horizon Insurance project with their
    descriptions and schemas. Use this to understand what data is available
    before querying.
    """
    manifest = load_manifest()
    models = []

    for node_id, node in manifest.get("nodes", {}).items():
        if node.get("resource_type") != "model":
            continue
        models.append({
            "model_name": node.get("name"),
            "schema": node.get("schema"),
            "description": node.get("description", "No description provided"),
            "materialized": node.get("config", {}).get("materialized"),
        })

    models.sort(key=lambda x: x["model_name"])
    return json.dumps(models, indent=2)


@mcp.tool()
def get_model_details(model_name: str) -> str:
    """
    Get full details for a specific dbt model including column definitions,
    metric definitions, and data tests. Use this before querying a model
    to understand exactly what each column means.

    Args:
        model_name: The name of the model, e.g. 'mart_loss_ratio_by_segment'
    """
    manifest = load_manifest()

    for node_id, node in manifest.get("nodes", {}).items():
        if node.get("resource_type") == "model" and node.get("name") == model_name:
            columns = {}
            for col_name, col_data in node.get("columns", {}).items():
                columns[col_name] = {
                    "description": col_data.get("description", ""),
                    "data_type": col_data.get("data_type", ""),
                    "tests": [t if isinstance(t, str) else list(t.keys())[0]
                              for t in col_data.get("tests", [])],
                }
            return json.dumps({
                "model_name": node.get("name"),
                "schema": node.get("schema"),
                "description": node.get("description"),
                "materialized": node.get("config", {}).get("materialized"),
                "columns": columns,
                "raw_sql_path": node.get("original_file_path"),
            }, indent=2)

    return json.dumps({"error": f"Model '{model_name}' not found in manifest."})


@mcp.tool()
def get_metric_definitions() -> str:
    """
    Return all governed metric definitions from the Horizon Insurance
    semantic layer. Always consult this before performing calculations
    involving loss ratio, earned premium, or claim frequency to ensure
    you are using the correct definition.
    """
    definitions = {
        "loss_ratio": {
            "definition": "Incurred losses divided by earned premium",
            "numerator": "Total incurred loss — the sum of paid losses and case reserves on all claims",
            "denominator": "Total earned premium — the premium allocated to the measurement period",
            "governance_note": (
                "Loss ratio must always be calculated as sum(incurred_loss) / sum(earned_premium). "
                "Do not average policy-level loss ratios. "
                "Do not use written premium as the denominator."
            ),
            "primary_model": "mart_loss_ratio_by_segment",
        },
        "incurred_loss": {
            "definition": "Paid losses plus case reserves on a claim or set of claims",
            "components": {
                "paid_loss": "Amounts already disbursed to claimants",
                "case_reserve": "Estimated future payment obligation on open claims (incurred_loss - paid_loss)",
            },
            "governance_note": (
                "Incurred loss includes both paid and unpaid (reserved) amounts. "
                "Do not use paid_loss alone as a proxy for incurred loss."
            ),
            "primary_model": "stg_claims",
        },
        "earned_premium": {
            "definition": (
                "The portion of written premium allocated to a given measurement period "
                "based on how much of the policy term has elapsed"
            ),
            "governance_note": (
                "Use earned premium — not written premium — as the denominator "
                "in all loss ratio calculations. Written premium is the total "
                "premium charged at policy inception. Earned premium is the "
                "portion that has been 'earned' through time."
            ),
            "primary_model": "stg_premiums",
        },
        "claim_frequency_per_100": {
            "definition": "Number of claims per 100 in-force policies in the segment",
            "formula": "(claim_count / policy_count) * 100",
            "governance_note": "Reported at the segment level only (product_type + state).",
            "primary_model": "mart_loss_ratio_by_segment",
        },
        "case_reserve": {
            "definition": "Estimated unpaid loss on an open claim",
            "formula": "incurred_loss - paid_loss",
            "governance_note": (
                "Case reserves exist only on open claims. "
                "Closed claims with paid_loss = incurred_loss will have case_reserve = 0."
            ),
            "primary_model": "stg_claims",
        },
    }
    return json.dumps(definitions, indent=2)


@mcp.tool()
def query_data(sql: str) -> str:
    """
    Execute a read-only SQL query against the Horizon Insurance DuckDB database.
    Use list_models and get_model_details first to understand available tables
    and column definitions.

    The database contains these schemas:
      - main_raw: raw seed tables (policies, claims, premiums)
      - main_staging: staged models (stg_policies, stg_claims, stg_premiums)
      - main_marts: analytical models (mart_policy_summary,
                    mart_loss_ratio_by_segment, mart_monthly_premium_trend)

    Args:
        sql: A read-only SELECT statement. UPDATE, INSERT, DELETE, and DROP
             are not permitted.
    """
    # safety check — block any write operations
    sql_upper = sql.strip().upper()
    forbidden = ["INSERT", "UPDATE", "DELETE", "DROP", "CREATE", "ALTER", "TRUNCATE"]
    for keyword in forbidden:
        if sql_upper.startswith(keyword) or f" {keyword} " in sql_upper:
            return json.dumps({
                "error": f"Write operation '{keyword}' is not permitted. "
                         "Only SELECT statements are allowed."
            })

    try:
        conn = get_db_connection()
        result = conn.execute(sql).fetchdf()
        conn.close()

        if result.empty:
            return json.dumps({"rows": [], "row_count": 0})

        # convert to JSON-serialisable format
        records = result.to_dict(orient="records")
        return json.dumps({
            "rows": records,
            "row_count": len(records),
            "columns": list(result.columns),
        }, indent=2, default=str)

    except Exception as e:
        return json.dumps({"error": str(e)})


# ── entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("Starting Horizon Insurance MCP server...")
    print(f"  Project root : {PROJECT_ROOT}")
    print(f"  Manifest     : {MANIFEST_PATH}")
    print(f"  Database     : {DB_PATH}")
    mcp.run(transport="stdio")

'@ | Set-Content -Path 'mcp_server\horizon_mcp_server.py' -Encoding UTF8

Write-Host 'Creating models\marts\mart_loss_ratio_by_segment.sql...'
@'
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

'@ | Set-Content -Path 'models\marts\mart_loss_ratio_by_segment.sql' -Encoding UTF8

Write-Host 'Creating models\marts\mart_monthly_premium_trend.sql...'
@'
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

'@ | Set-Content -Path 'models\marts\mart_monthly_premium_trend.sql' -Encoding UTF8

Write-Host 'Creating models\marts\mart_policy_summary.sql...'
@'
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

'@ | Set-Content -Path 'models\marts\mart_policy_summary.sql' -Encoding UTF8

Write-Host 'Creating models\schema.yml...'
@'
version: 2

models:
  - name: stg_policies
    description: >
      Staged policy records from raw seed data. One row per policy.
      Includes all active and cancelled policies.
    columns:
      - name: policy_id
        description: Unique identifier for the policy
        tests:
          - unique
          - not_null
      - name: product_type
        description: "Type of insurance product: auto or homeowners"
      - name: state
        description: US state where the policy is written
      - name: written_premium
        description: Total premium charged for the policy term
      - name: status
        description: "Current policy status: active or cancelled"

  - name: stg_claims
    description: >
      Staged claims records. One row per claim.
      Includes open and closed claims across all policy types.
    columns:
      - name: claim_id
        description: Unique identifier for the claim
        tests:
          - unique
          - not_null
      - name: policy_id
        description: Foreign key to stg_policies
        tests:
          - not_null
      - name: incurred_loss
        description: >
          Total estimated loss for this claim including paid amounts and
          case reserves. This is the standard actuarial incurred loss figure
          used in loss ratio calculations.
      - name: paid_loss
        description: Amounts already paid out on this claim
      - name: case_reserve
        description: >
          Incurred loss minus paid loss. Represents the estimated future
          payment obligation on open claims.
      - name: status
        description: "Claim status: open or closed"

  - name: stg_premiums
    description: >
      Earned premium by policy by calendar month. One row per policy per month.
      Earned premium represents the portion of written premium allocated to a
      given month based on the policy period. Used as the denominator in
      all loss ratio calculations.
    columns:
      - name: premium_id
        description: Unique identifier for this earning record
        tests:
          - unique
          - not_null
      - name: policy_id
        description: Foreign key to stg_policies
      - name: earning_month
        description: "Calendar month in YYYY-MM format"
      - name: earned_premium
        description: Premium earned in this calendar month for this policy

  - name: mart_policy_summary
    description: >
      Policy-level summary combining written premium, earned premium,
      and claim activity. One row per policy. Primary source for
      policy-level loss ratio analysis.

      METRIC DEFINITIONS (enforced at this layer):
      - loss_ratio: total incurred loss / total earned premium (policy period to date)
      - incurred_loss: paid losses + case reserves on all claims for this policy
      - earned_premium: sum of monthly earned premium records for this policy
    columns:
      - name: policy_id
        tests:
          - unique
          - not_null
      - name: loss_ratio
        description: >
          Incurred loss ratio at the policy level. Numerator is total incurred
          losses (paid + case reserve). Denominator is total earned premium
          for the policy period to date. Null if no earned premium recorded.

  - name: mart_loss_ratio_by_segment
    description: >
      Loss ratio and claim metrics aggregated by product type and state.
      Primary analytical surface for segment-level underwriting performance.

      METRIC DEFINITIONS (enforced at this layer):
      - loss_ratio: sum(incurred_loss) / sum(earned_premium) by segment
      - claim_frequency_per_100: claims per 100 in-force policies
      - avg_incurred_loss_per_claim: total incurred loss / total claim count
    columns:
      - name: loss_ratio
        description: >
          Segment-level incurred loss ratio. Consistent with policy-level
          definition in mart_policy_summary. Numerator and denominator are
          summed independently before dividing — not an average of policy
          loss ratios.

  - name: mart_monthly_premium_trend
    description: >
      Monthly earned premium and claim activity by product type and state.
      Used for trend analysis and monitoring loss ratio development over time.
    columns:
      - name: monthly_loss_ratio
        description: >
          Loss ratio for the calendar month only. Claims matched to the month
          they were reported, not the month they occurred. Earned premium is
          the premium earned in that specific month.

'@ | Set-Content -Path 'models\schema.yml' -Encoding UTF8

Write-Host 'Creating models\staging\stg_claims.sql...'
@'
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

'@ | Set-Content -Path 'models\staging\stg_claims.sql' -Encoding UTF8

Write-Host 'Creating models\staging\stg_policies.sql...'
@'
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

'@ | Set-Content -Path 'models\staging\stg_policies.sql' -Encoding UTF8

Write-Host 'Creating models\staging\stg_premiums.sql...'
@'
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

'@ | Set-Content -Path 'models\staging\stg_premiums.sql' -Encoding UTF8

Write-Host 'Creating profiles.yml...'
@'
horizon_insurance:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: 'horizon_insurance.duckdb'
      schema: main
      threads: 4

'@ | Set-Content -Path 'profiles.yml' -Encoding UTF8

Write-Host 'Creating requirements.txt...'
@'
dbt-duckdb==1.10.1
mcp==1.28.0
anthropic==0.112.0

'@ | Set-Content -Path 'requirements.txt' -Encoding UTF8

Write-Host 'Creating scripts\run_agent.py...'
@'
"""
run_agent.py

Demonstrates a Claude agent querying the Horizon Insurance governed semantic
layer via the MCP server. Shows two capabilities:
  1. Understanding the data model (what metrics exist, how they are defined)
  2. Answering business questions using governed metric definitions

Usage:
  python scripts/run_agent.py

Requires:
  - ANTHROPIC_API_KEY set as an environment variable
  - dbt run completed (target/manifest.json and horizon_insurance.duckdb exist)
  - MCP server file at mcp_server/horizon_mcp_server.py
"""

import asyncio
import os
import json
from pathlib import Path
import anthropic
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

# ── config ─────────────────────────────────────────────────────────────────────
PROJECT_ROOT = Path(__file__).parent.parent
MCP_SERVER_PATH = PROJECT_ROOT / "mcp_server" / "horizon_mcp_server.py"

DEMO_QUESTIONS = [
    # Capability 1: understanding the data model
    "What models are available in this dataset and what does each one contain?",
    "How is loss ratio defined in this semantic layer? What is the correct formula?",
    # Capability 2: answering business questions with governed metrics
    "What is the loss ratio by product type and state? Which segment has the worst performance?",
    "How many open claims are there, and what is the total case reserve outstanding?",
    "Which state has the highest claim frequency per 100 policies for auto insurance?",
]


async def run_agent_demo():
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError(
            "ANTHROPIC_API_KEY environment variable not set. "
            "Set it before running this script."
        )

    client = anthropic.Anthropic(api_key=api_key)

    server_params = StdioServerParameters(
        command="python",
        args=[str(MCP_SERVER_PATH)],
        env=None,
    )

    print("=" * 70)
    print("HORIZON INSURANCE — GOVERNED SEMANTIC LAYER DEMO")
    print("Agent: Claude via MCP → dbt semantic layer → DuckDB")
    print("=" * 70)

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # get available tools from the MCP server
            tools_response = await session.list_tools()
            tools = [
                {
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema,
                }
                for tool in tools_response.tools
            ]

            print(f"\nMCP server connected. Tools available: {[t['name'] for t in tools]}\n")

            for i, question in enumerate(DEMO_QUESTIONS, 1):
                print(f"\n{'─' * 70}")
                print(f"QUESTION {i}: {question}")
                print("─" * 70)

                messages = [{"role": "user", "content": question}]

                # agentic loop — Claude calls tools until it has an answer
                while True:
                    response = client.messages.create(
                        model="claude-sonnet-4-6",
                        max_tokens=2048,
                        system=(
                            "You are a data analyst with access to the Horizon Insurance "
                            "governed semantic layer via MCP tools. "
                            "Always use get_metric_definitions before performing any "
                            "calculation involving loss ratio, earned premium, or claim frequency. "
                            "Always use get_model_details before querying a model you haven't "
                            "inspected in this conversation. "
                            "Be precise about metric definitions and cite the governance notes "
                            "when relevant to the answer."
                        ),
                        tools=tools,
                        messages=messages,
                    )

                    # check if Claude wants to call a tool
                    if response.stop_reason == "tool_use":
                        # process all tool calls in this response
                        tool_results = []
                        for block in response.content:
                            if block.type == "tool_use":
                                print(f"  → Calling tool: {block.name}({json.dumps(block.input)[:80]}...)")
                                result = await session.call_tool(block.name, block.input)
                                tool_results.append({
                                    "type": "tool_result",
                                    "tool_use_id": block.id,
                                    "content": result.content[0].text if result.content else "",
                                })

                        # add assistant response and tool results to message history
                        messages.append({"role": "assistant", "content": response.content})
                        messages.append({"role": "user", "content": tool_results})

                    else:
                        # Claude has finished — extract and print the final answer
                        final_answer = ""
                        for block in response.content:
                            if hasattr(block, "text"):
                                final_answer += block.text

                        print(f"\nANSWER:\n{final_answer}")
                        break


if __name__ == "__main__":
    asyncio.run(run_agent_demo())

'@ | Set-Content -Path 'scripts\run_agent.py' -Encoding UTF8

Write-Host 'Creating seeds\claims.csv...'
@'
claim_id,policy_id,claim_date,close_date,claim_type,incurred_loss,paid_loss,status,at_fault
CLM-0001,POL-0001,2024-02-15,2024-04-01,collision,4200.00,4200.00,closed,Y
CLM-0002,POL-0003,2024-03-10,2024-05-15,collision,8500.00,8500.00,closed,N
CLM-0003,POL-0005,2024-02-01,2024-03-20,comprehensive,1200.00,1200.00,closed,N
CLM-0004,POL-0006,2024-04-05,,wind_hail,15000.00,0.00,open,N
CLM-0005,POL-0008,2024-03-22,2024-06-01,collision,6800.00,6800.00,closed,Y
CLM-0006,POL-0009,2024-04-10,,water_damage,22000.00,0.00,open,N
CLM-0007,POL-0011,2024-02-28,2024-04-15,fire,45000.00,45000.00,closed,N
CLM-0008,POL-0012,2024-03-05,2024-04-30,collision,3100.00,3100.00,closed,Y
CLM-0009,POL-0014,2024-05-01,,theft,8500.00,0.00,open,N
CLM-0010,POL-0015,2024-04-18,2024-06-30,collision,5200.00,5200.00,closed,N
CLM-0011,POL-0016,2024-03-15,2024-05-01,wind_hail,18000.00,18000.00,closed,N
CLM-0012,POL-0019,2024-05-10,,water_damage,31000.00,0.00,open,N
CLM-0013,POL-0020,2024-02-20,2024-03-31,collision,2800.00,2800.00,closed,Y
CLM-0014,POL-0001,2024-06-01,,collision,9200.00,0.00,open,Y
CLM-0015,POL-0021,2024-05-15,2024-07-01,comprehensive,950.00,950.00,closed,N
CLM-0016,POL-0022,2024-05-20,,fire,67000.00,0.00,open,N
CLM-0017,POL-0023,2024-06-02,,collision,4100.00,0.00,open,Y
CLM-0018,POL-0002,2024-04-22,2024-06-15,water_damage,12000.00,12000.00,closed,N
CLM-0019,POL-0025,2024-06-10,,wind_hail,9800.00,0.00,open,N
CLM-0020,POL-0007,2024-05-28,2024-07-15,collision,3600.00,3600.00,closed,N

'@ | Set-Content -Path 'seeds\claims.csv' -Encoding UTF8

Write-Host 'Creating seeds\policies.csv...'
@'
policy_id,policyholder_id,product_type,state,effective_date,expiration_date,written_premium,status
POL-0001,PH-1001,auto,TX,2024-01-01,2025-01-01,1200.00,active
POL-0002,PH-1002,homeowners,TX,2024-01-01,2025-01-01,2400.00,active
POL-0003,PH-1003,auto,CA,2024-02-01,2025-02-01,1850.00,active
POL-0004,PH-1004,homeowners,CA,2024-02-01,2025-02-01,3100.00,active
POL-0005,PH-1005,auto,FL,2024-01-01,2025-01-01,2200.00,active
POL-0006,PH-1006,homeowners,FL,2024-03-01,2025-03-01,4500.00,active
POL-0007,PH-1007,auto,TX,2024-01-01,2025-01-01,980.00,active
POL-0008,PH-1008,auto,NY,2024-02-01,2025-02-01,2100.00,active
POL-0009,PH-1009,homeowners,NY,2024-02-01,2025-02-01,3800.00,active
POL-0010,PH-1010,auto,CA,2024-03-01,2025-03-01,1650.00,active
POL-0011,PH-1011,homeowners,TX,2024-01-01,2025-01-01,2750.00,active
POL-0012,PH-1012,auto,FL,2024-02-01,2025-02-01,1900.00,active
POL-0013,PH-1013,auto,CA,2024-03-01,2025-03-01,1420.00,cancelled
POL-0014,PH-1014,homeowners,TX,2024-01-01,2025-01-01,2900.00,active
POL-0015,PH-1015,auto,NY,2024-02-01,2025-02-01,2350.00,active
POL-0016,PH-1016,homeowners,FL,2024-01-01,2025-01-01,5100.00,active
POL-0017,PH-1017,auto,TX,2024-03-01,2025-03-01,1100.00,active
POL-0018,PH-1018,auto,CA,2024-01-01,2025-01-01,1780.00,cancelled
POL-0019,PH-1019,homeowners,NY,2024-03-01,2025-03-01,4200.00,active
POL-0020,PH-1020,auto,FL,2024-01-01,2025-01-01,2050.00,active
POL-0021,PH-1021,auto,TX,2024-04-01,2025-04-01,1300.00,active
POL-0022,PH-1022,homeowners,CA,2024-04-01,2025-04-01,3400.00,active
POL-0023,PH-1023,auto,FL,2024-04-01,2025-04-01,1950.00,active
POL-0024,PH-1024,auto,NY,2024-04-01,2025-04-01,2250.00,active
POL-0025,PH-1025,homeowners,TX,2024-04-01,2025-04-01,2600.00,active

'@ | Set-Content -Path 'seeds\policies.csv' -Encoding UTF8

Write-Host 'Creating seeds\premiums.csv...'
@'
premium_id,policy_id,earning_month,earned_premium
PREM-0001,POL-0001,2024-01,100.00
PREM-0002,POL-0001,2024-02,100.00
PREM-0003,POL-0001,2024-03,100.00
PREM-0004,POL-0001,2024-04,100.00
PREM-0005,POL-0001,2024-05,100.00
PREM-0006,POL-0001,2024-06,100.00
PREM-0007,POL-0002,2024-01,200.00
PREM-0008,POL-0002,2024-02,200.00
PREM-0009,POL-0002,2024-03,200.00
PREM-0010,POL-0002,2024-04,200.00
PREM-0011,POL-0002,2024-05,200.00
PREM-0012,POL-0002,2024-06,200.00
PREM-0013,POL-0003,2024-02,154.17
PREM-0014,POL-0003,2024-03,154.17
PREM-0015,POL-0003,2024-04,154.17
PREM-0016,POL-0003,2024-05,154.17
PREM-0017,POL-0003,2024-06,154.17
PREM-0018,POL-0004,2024-02,258.33
PREM-0019,POL-0004,2024-03,258.33
PREM-0020,POL-0004,2024-04,258.33
PREM-0021,POL-0004,2024-05,258.33
PREM-0022,POL-0004,2024-06,258.33
PREM-0023,POL-0005,2024-01,183.33
PREM-0024,POL-0005,2024-02,183.33
PREM-0025,POL-0005,2024-03,183.33
PREM-0026,POL-0005,2024-04,183.33
PREM-0027,POL-0005,2024-05,183.33
PREM-0028,POL-0005,2024-06,183.33
PREM-0029,POL-0006,2024-03,375.00
PREM-0030,POL-0006,2024-04,375.00
PREM-0031,POL-0006,2024-05,375.00
PREM-0032,POL-0006,2024-06,375.00
PREM-0033,POL-0007,2024-01,81.67
PREM-0034,POL-0007,2024-02,81.67
PREM-0035,POL-0007,2024-03,81.67
PREM-0036,POL-0007,2024-04,81.67
PREM-0037,POL-0007,2024-05,81.67
PREM-0038,POL-0007,2024-06,81.67
PREM-0039,POL-0008,2024-02,175.00
PREM-0040,POL-0008,2024-03,175.00
PREM-0041,POL-0008,2024-04,175.00
PREM-0042,POL-0008,2024-05,175.00
PREM-0043,POL-0008,2024-06,175.00
PREM-0044,POL-0009,2024-02,316.67
PREM-0045,POL-0009,2024-03,316.67
PREM-0046,POL-0009,2024-04,316.67
PREM-0047,POL-0009,2024-05,316.67
PREM-0048,POL-0009,2024-06,316.67
PREM-0049,POL-0010,2024-03,137.50
PREM-0050,POL-0010,2024-04,137.50
PREM-0051,POL-0010,2024-05,137.50
PREM-0052,POL-0010,2024-06,137.50
PREM-0053,POL-0011,2024-01,229.17
PREM-0054,POL-0011,2024-02,229.17
PREM-0055,POL-0011,2024-03,229.17
PREM-0056,POL-0011,2024-04,229.17
PREM-0057,POL-0011,2024-05,229.17
PREM-0058,POL-0011,2024-06,229.17
PREM-0059,POL-0012,2024-02,158.33
PREM-0060,POL-0012,2024-03,158.33
PREM-0061,POL-0012,2024-04,158.33
PREM-0062,POL-0012,2024-05,158.33
PREM-0063,POL-0012,2024-06,158.33
PREM-0064,POL-0014,2024-01,241.67
PREM-0065,POL-0014,2024-02,241.67
PREM-0066,POL-0014,2024-03,241.67
PREM-0067,POL-0014,2024-04,241.67
PREM-0068,POL-0014,2024-05,241.67
PREM-0069,POL-0014,2024-06,241.67
PREM-0070,POL-0015,2024-02,195.83
PREM-0071,POL-0015,2024-03,195.83
PREM-0072,POL-0015,2024-04,195.83
PREM-0073,POL-0015,2024-05,195.83
PREM-0074,POL-0015,2024-06,195.83
PREM-0075,POL-0016,2024-01,425.00
PREM-0076,POL-0016,2024-02,425.00
PREM-0077,POL-0016,2024-03,425.00
PREM-0078,POL-0016,2024-04,425.00
PREM-0079,POL-0016,2024-05,425.00
PREM-0080,POL-0016,2024-06,425.00
PREM-0081,POL-0017,2024-03,91.67
PREM-0082,POL-0017,2024-04,91.67
PREM-0083,POL-0017,2024-05,91.67
PREM-0084,POL-0017,2024-06,91.67
PREM-0085,POL-0019,2024-03,350.00
PREM-0086,POL-0019,2024-04,350.00
PREM-0087,POL-0019,2024-05,350.00
PREM-0088,POL-0019,2024-06,350.00
PREM-0089,POL-0020,2024-01,170.83
PREM-0090,POL-0020,2024-02,170.83
PREM-0091,POL-0020,2024-03,170.83
PREM-0092,POL-0020,2024-04,170.83
PREM-0093,POL-0020,2024-05,170.83
PREM-0094,POL-0020,2024-06,170.83
PREM-0095,POL-0021,2024-04,108.33
PREM-0096,POL-0021,2024-05,108.33
PREM-0097,POL-0021,2024-06,108.33
PREM-0098,POL-0022,2024-04,283.33
PREM-0099,POL-0022,2024-05,283.33
PREM-0100,POL-0022,2024-06,283.33
PREM-0101,POL-0023,2024-04,162.50
PREM-0102,POL-0023,2024-05,162.50
PREM-0103,POL-0023,2024-06,162.50
PREM-0104,POL-0024,2024-04,187.50
PREM-0105,POL-0024,2024-05,187.50
PREM-0106,POL-0024,2024-06,187.50
PREM-0107,POL-0025,2024-04,216.67
PREM-0108,POL-0025,2024-05,216.67
PREM-0109,POL-0025,2024-06,216.67

'@ | Set-Content -Path 'seeds\premiums.csv' -Encoding UTF8
