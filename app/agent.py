import os

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential


def ask_foundry(question: str) -> str:
    endpoint = os.getenv("FOUNDRY_PROJECT_ENDPOINT")
    agent_name = os.getenv("FOUNDRY_AGENT_NAME")

    if not endpoint or not agent_name:
        raise RuntimeError("Foundry endpoint or agent name is missing")

    # In Azure Container Apps, AZURE_CLIENT_ID is unset and DefaultAzureCredential
    # uses the app's system-assigned managed identity. Locally it uses `az login`.
    credential = DefaultAzureCredential()
    try:
        with AIProjectClient(endpoint=endpoint, credential=credential) as project:
            openai_client = project.get_openai_client()
            # Call the saved Foundry Prompt Agent by name (latest version).
            response = openai_client.responses.create(
                input=question,
                extra_body={
                    "agent_reference": {"name": agent_name, "type": "agent_reference"}
                },
                timeout=60,
            )
            return response.output_text
    finally:
        credential.close()
