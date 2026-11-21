"""Create (or add a new version of) the student-support-agent Prompt Agent in a Foundry project.

Usage:
    python infra/create_agent.py <FOUNDRY_PROJECT_ENDPOINT> [--model gpt-5.4-mini]

Uses your `az login` identity (needs the Foundry User role on the Foundry resource).
Run it once per environment so DEV, PRE-PROD and PROD share the same reviewed instructions.
"""
import argparse

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition
from azure.identity import DefaultAzureCredential

AGENT_NAME = "student-support-agent"
INSTRUCTIONS = """You are a Student Support AI Assistant.
Help students understand Python, FastAPI, Azure,
GraphQL, Microsoft Foundry, RAG and Agentic AI.

1. Explain concepts in beginner-friendly English.
2. Give practical examples.
3. Use numbered steps for tutorials.
4. Do not invent Azure configuration details.
5. If unsure, say so clearly.
6. Keep answers structured and educational."""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("endpoint")
    parser.add_argument("--model", default="gpt-5.4-mini")
    args = parser.parse_args()

    with DefaultAzureCredential() as cred, AIProjectClient(endpoint=args.endpoint, credential=cred) as project:
        agent = project.agents.create_version(
            agent_name=AGENT_NAME,
            definition=PromptAgentDefinition(model=args.model, instructions=INSTRUCTIONS),
            description="Student Support AI Agent (classroom lab)",
        )
        print(f"Created {agent.name} version {agent.version} in {args.endpoint}")

        reply = project.get_openai_client().responses.create(
            input="In one sentence, what is FastAPI?",
            extra_body={"agent_reference": {"name": AGENT_NAME, "type": "agent_reference"}},
        )
        print("Smoke test:", reply.output_text)


if __name__ == "__main__":
    main()
