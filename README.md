# horizon-mcp-demo

A working demonstration of a governed semantic layer exposed via MCP, built on dbt Core and DuckDB. Models a P&C insurance company with policies, claims, and earned premium data.

Used as research and reference material for Horizon Data Partners white paper: *The Governed Data Layer: Why AI Agents Fail Without One, and How to Build It.*

---

## What this demonstrates

1. **A governed semantic layer** â€” dbt models with enforced metric definitions for loss ratio, earned premium, incurred loss, and claim frequency
2. **An MCP server** â€” a lightweight Python server that reads dbt artifacts and exposes governed tools to any MCP-compatible agent
3. **An agent demo** â€” Claude querying the semantic layer via MCP, answering business questions using governed metric definitions rather than raw tables

---

## Project structure

```
horizon-mcp-demo/
â”œâ”€â”€ seeds/                        # Raw fake data (CSV)
â”‚   â”œâ”€â”€ policies.csv
â”‚   â”œâ”€â”€ claims.csv
â”‚   â””â”€â”€ premiums.csv
â”œâ”€â”€ models/
â”‚   â”œâ”€â”€ staging/                  # Cleaned, typed source models
â”‚   â”‚   â”œâ”€â”€ stg_policies.sql
â”‚   â”‚   â”œâ”€â”€ stg_claims.sql
â”‚   â”‚   â””â”€â”€ stg_premiums.sql
â”‚   â”œâ”€â”€ marts/                    # Governed analytical models
â”‚   â”‚   â”œâ”€â”€ mart_policy_summary.sql
â”‚   â”‚   â”œâ”€â”€ mart_loss_ratio_by_segment.sql
â”‚   â”‚   â””â”€â”€ mart_monthly_premium_trend.sql
â”‚   â””â”€â”€ schema.yml                # Metric definitions and column docs
â”œâ”€â”€ mcp_server/
â”‚   â””â”€â”€ horizon_mcp_server.py     # MCP server exposing dbt artifacts
â”œâ”€â”€ scripts/
â”‚   â””â”€â”€ run_agent.py              # Agent demo using Claude + MCP
â”œâ”€â”€ dbt_project.yml
â”œâ”€â”€ profiles.yml                  # DuckDB connection config
â””â”€â”€ requirements.txt
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
| **claim_frequency_per_100** | (claims / policies) Ã— 100 | Segment level only. |
| **case_reserve** | incurred_loss âˆ’ paid_loss | Zero on closed claims. |

---

## Notes

- The `.duckdb` file is excluded from version control (see `.gitignore`). It is generated locally by `dbt seed && dbt run`.
- The MCP server opens DuckDB in read-only mode. Write operations are blocked at the tool layer as well.
- The `profiles.yml` is included in the repo because it contains no credentials â€” DuckDB is a local file with no authentication.

