"""
run_agent.py

Demonstrates a Claude agent querying the Horizon Insurance governed semantic
layer via the MCP server. Shows two capabilities:
  1. Understanding the data model (what metrics exist, how they are defined)
  2. Answering business questions using governed metric definitions

Logging:
  Full run logs are written to logs/agent_run_<timestamp>.json
  Each log captures: question, tool calls (name, input, output, tokens),
  question-level token totals, and run-level totals.

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
from datetime import datetime, timezone
import anthropic
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

# â”€â”€ config â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
PROJECT_ROOT = Path(__file__).parent.parent
MCP_SERVER_PATH = PROJECT_ROOT / "mcp_server" / "horizon_mcp_server.py"
LOGS_DIR = PROJECT_ROOT / "logs"

DEMO_QUESTIONS = [
    # Capability 1: understanding the data model
    "What models are available in this dataset and what does each one contain?",
    "How is loss ratio defined in this semantic layer? What is the correct formula?",
    # Capability 2: answering business questions with governed metrics
    "What is the loss ratio by product type and state? Which segment has the worst performance?",
    "How many open claims are there, and what is the total case reserve outstanding?",
    "Which state has the highest claim frequency per 100 policies for auto insurance?",
]


def init_log(run_timestamp: str) -> dict:
    """Initialise the run-level log structure."""
    return {
        "run_id": run_timestamp,
        "model": "claude-sonnet-4-6",
        "started_at": run_timestamp,
        "questions": [],
        "run_totals": {
            "input_tokens": 0,
            "output_tokens": 0,
            "total_tokens": 0,
            "total_tool_calls": 0,
        }
    }


def init_question_log(question_number: int, question_text: str) -> dict:
    """Initialise a question-level log entry."""
    return {
        "question_number": question_number,
        "question": question_text,
        "tool_calls": [],
        "final_answer": "",
        "question_totals": {
            "input_tokens": 0,
            "output_tokens": 0,
            "total_tokens": 0,
            "tool_call_count": 0,
            "api_call_count": 0,
        }
    }


async def run_agent_demo():
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise EnvironmentError(
            "ANTHROPIC_API_KEY environment variable not set. "
            "Set it before running this script."
        )

    client = anthropic.Anthropic(api_key=api_key)

    # â”€â”€ set up logging â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    LOGS_DIR.mkdir(exist_ok=True)
    run_timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    log_path = LOGS_DIR / f"agent_run_{run_timestamp}.json"
    run_log = init_log(run_timestamp)

    server_params = StdioServerParameters(
        command="python",
        args=[str(MCP_SERVER_PATH)],
        env=None,
    )

    print("=" * 70)
    print("HORIZON INSURANCE â€” GOVERNED SEMANTIC LAYER DEMO")
    print("Agent: Claude via MCP â†’ dbt semantic layer â†’ DuckDB")
    print(f"Log file: logs/agent_run_{run_timestamp}.json")
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
                print(f"\n{'â”€' * 70}")
                print(f"QUESTION {i}: {question}")
                print("â”€" * 70)

                q_log = init_question_log(i, question)
                messages = [{"role": "user", "content": question}]

                # agentic loop â€” Claude calls tools until it has an answer
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

                    # â”€â”€ capture token usage for this API call â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    call_input_tokens  = response.usage.input_tokens
                    call_output_tokens = response.usage.output_tokens
                    q_log["question_totals"]["input_tokens"]  += call_input_tokens
                    q_log["question_totals"]["output_tokens"] += call_output_tokens
                    q_log["question_totals"]["total_tokens"]  += call_input_tokens + call_output_tokens
                    q_log["question_totals"]["api_call_count"] += 1

                    # check if Claude wants to call a tool
                    if response.stop_reason == "tool_use":
                        tool_results = []
                        for block in response.content:
                            if block.type == "tool_use":
                                print(f"  â†’ Calling tool: {block.name}({json.dumps(block.input)[:80]}...)")

                                result = await session.call_tool(block.name, block.input)
                                tool_output = result.content[0].text if result.content else ""

                                # â”€â”€ log this tool call in full â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                                tool_call_entry = {
                                    "tool_name": block.name,
                                    "tool_input": block.input,
                                    "tool_output": tool_output,
                                    "api_call_input_tokens": call_input_tokens,
                                    "api_call_output_tokens": call_output_tokens,
                                }
                                q_log["tool_calls"].append(tool_call_entry)
                                q_log["question_totals"]["tool_call_count"] += 1

                                tool_results.append({
                                    "type": "tool_result",
                                    "tool_use_id": block.id,
                                    "content": tool_output,
                                })

                        messages.append({"role": "assistant", "content": response.content})
                        messages.append({"role": "user", "content": tool_results})

                    else:
                        # Claude has finished â€” extract and print the final answer
                        final_answer = ""
                        for block in response.content:
                            if hasattr(block, "text"):
                                final_answer += block.text

                        q_log["final_answer"] = final_answer

                        # â”€â”€ print token summary for this question â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                        qt = q_log["question_totals"]
                        print(f"\nANSWER:\n{final_answer}")
                        print(f"\n  ðŸ“Š Token usage â€” Q{i}: "
                              f"input={qt['input_tokens']:,}  "
                              f"output={qt['output_tokens']:,}  "
                              f"total={qt['total_tokens']:,}  "
                              f"tool_calls={qt['tool_call_count']}  "
                              f"api_calls={qt['api_call_count']}")
                        break

                # accumulate into run totals
                run_log["questions"].append(q_log)
                run_log["run_totals"]["input_tokens"]    += q_log["question_totals"]["input_tokens"]
                run_log["run_totals"]["output_tokens"]   += q_log["question_totals"]["output_tokens"]
                run_log["run_totals"]["total_tokens"]    += q_log["question_totals"]["total_tokens"]
                run_log["run_totals"]["total_tool_calls"] += q_log["question_totals"]["tool_call_count"]

    # â”€â”€ print run summary â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    rt = run_log["run_totals"]
    print(f"\n{'=' * 70}")
    print("RUN SUMMARY")
    print(f"{'=' * 70}")
    print(f"{'Question':<8} {'Input':>8} {'Output':>8} {'Total':>8} {'Tool Calls':>12} {'API Calls':>10}")
    print(f"{'â”€' * 70}")
    for q in run_log["questions"]:
        qt = q["question_totals"]
        print(f"Q{q['question_number']:<7} {qt['input_tokens']:>8,} {qt['output_tokens']:>8,} "
              f"{qt['total_tokens']:>8,} {qt['tool_call_count']:>12} {qt['api_call_count']:>10}")
    print(f"{'â”€' * 70}")
    print(f"{'TOTAL':<8} {rt['input_tokens']:>8,} {rt['output_tokens']:>8,} "
          f"{rt['total_tokens']:>8,} {rt['total_tool_calls']:>12}")

    # â”€â”€ write log file â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    run_log["completed_at"] = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    with open(log_path, "w", encoding="utf-8") as f:
        json.dump(run_log, f, indent=2, default=str)
    print(f"\nFull log written to: {log_path}")


if __name__ == "__main__":
    asyncio.run(run_agent_demo())
