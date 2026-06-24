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

# â”€â”€ config â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
    print("HORIZON INSURANCE â€” GOVERNED SEMANTIC LAYER DEMO")
    print("Agent: Claude via MCP â†’ dbt semantic layer â†’ DuckDB")
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

                    # check if Claude wants to call a tool
                    if response.stop_reason == "tool_use":
                        # process all tool calls in this response
                        tool_results = []
                        for block in response.content:
                            if block.type == "tool_use":
                                print(f"  â†’ Calling tool: {block.name}({json.dumps(block.input)[:80]}...)")
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
                        # Claude has finished â€” extract and print the final answer
                        final_answer = ""
                        for block in response.content:
                            if hasattr(block, "text"):
                                final_answer += block.text

                        print(f"\nANSWER:\n{final_answer}")
                        break


if __name__ == "__main__":
    asyncio.run(run_agent_demo())

