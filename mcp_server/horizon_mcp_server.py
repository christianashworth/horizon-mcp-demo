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

# â”€â”€ paths â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
PROJECT_ROOT = Path(__file__).parent.parent
MANIFEST_PATH = PROJECT_ROOT / "target" / "manifest.json"
DB_PATH = PROJECT_ROOT / "horizon_insurance.duckdb"

# â”€â”€ MCP server â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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


# â”€â”€ tools â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
            "numerator": "Total incurred loss â€” the sum of paid losses and case reserves on all claims",
            "denominator": "Total earned premium â€” the premium allocated to the measurement period",
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
                "Use earned premium â€” not written premium â€” as the denominator "
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
    # safety check â€” block any write operations
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


# â”€â”€ entry point â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

if __name__ == "__main__":
    print("Starting Horizon Insurance MCP server...")
    print(f"  Project root : {PROJECT_ROOT}")
    print(f"  Manifest     : {MANIFEST_PATH}")
    print(f"  Database     : {DB_PATH}")
    mcp.run(transport="stdio")

