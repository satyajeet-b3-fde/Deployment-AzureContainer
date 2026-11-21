# Student Support AI Agent — DEV → PRE-PROD → PROD on Azure Container Apps

FastAPI backend that calls a saved Microsoft Foundry Prompt Agent (`student-support-agent`),
deployed to three Azure Container Apps via GitHub Actions with OIDC and approval gates.

## What is already provisioned (eastus2, Pay-As-You-Go)

| Resource | DEV | PRE-PROD | PROD |
|---|---|---|---|
| Resource group | rg-student-dev | rg-student-preprod | rg-student-prod |
| Log Analytics | law-student-dev | law-student-preprod | law-student-prod |
| Container Apps env | cae-student-dev | cae-student-preprod | cae-student-prod |
| Container App | student-agent-dev | student-agent-preprod | student-agent-prod |
| Foundry resource | aif-student-dev-965lp | aif-student-preprod-965lp | aif-student-prod-965lp |
| Foundry project | foundry-student-dev | foundry-student-preprod | foundry-student-prod |
| Model deployment | gpt-5.4-mini (10K TPM) | gpt-5.4-mini | gpt-5.4-mini |
| Min / max replicas | 0 / 2 | 0 / 2 | 1 / 3 |

App URLs:
- DEV: https://student-agent-dev.ashydune-39b8926f.eastus2.azurecontainerapps.io/docs
- PRE-PROD: https://student-agent-preprod.proudisland-4accaec5.eastus2.azurecontainerapps.io/docs
- PROD: https://student-agent-prod.bravetree-e0634715.eastus2.azurecontainerapps.io/docs

Shared: `rg-student-shared` → ACR `acrstudentlab965lp` (Basic, admin user disabled).
Each Container App has a system-assigned identity with **AcrPull** on the ACR and
**Foundry User** (formerly "Azure AI User") on its own Foundry resource only.

GitHub deployer: Entra app `github-student-agent-deployer` with AcrPush + Contributor on the ACR,
and Contributor on the three app resource groups (no subscription-wide role).

## Your part: GitHub

### 1. Create the repo and push
Create an empty GitHub repo, then from **this folder** (`student-support-agent/`):

```powershell
git init -b main
git add .
git commit -m "Student Support AI Agent - initial"
git remote add origin https://github.com/<owner>/<repo>.git
git push -u origin main
```

> Run `git init` here. The parent folder (`C:\Users\Satyajeet`) is itself a git repo, and you
> don't want to push your home directory. `.env` and `.venv/` are already in `.gitignore`.

### 2. Add OIDC federated credentials (one command)
```powershell
./infra/setup_oidc.ps1 -Suffix 965lp -Repo <owner>/<repo>
```
This adds subjects `repo:<owner>/<repo>:environment:dev|preprod|prod`.

### 3. Create GitHub Environments
Repo → Settings → Environments → create **dev**, **preprod**, **prod**.
In **each** environment add these **variables** (Variables tab, not Secrets):

| Variable | dev | preprod | prod |
|---|---|---|---|
| AZURE_CLIENT_ID | 8c263203-25cb-4c78-9f46-f3e9dac45b7b | same | same |
| AZURE_TENANT_ID | 12b90b25-8589-4b52-ac30-db7bb9a53ce4 | same | same |
| AZURE_SUBSCRIPTION_ID | 02edbacd-6b42-462f-a8d8-1ea75b7bbd43 | same | same |
| ACR_NAME | acrstudentlab965lp | same | same |
| RESOURCE_GROUP | rg-student-dev | rg-student-preprod | rg-student-prod |
| CONTAINER_APP_NAME | student-agent-dev | student-agent-preprod | student-agent-prod |
| FOUNDRY_PROJECT_ENDPOINT | https://aif-student-dev-965lp.services.ai.azure.com/api/projects/foundry-student-dev | https://aif-student-preprod-965lp.services.ai.azure.com/api/projects/foundry-student-preprod | https://aif-student-prod-965lp.services.ai.azure.com/api/projects/foundry-student-prod |
| FOUNDRY_AGENT_NAME | student-support-agent | same | same |

For **preprod** and **prod**: Deployment protection rules → **Required reviewers** → add yourself.
(Required reviewers on a private repo need a paid GitHub plan; on a public repo they're free.)

### 4. Run the pipeline
Actions → **Student AI Agent - Multi Environment CI/CD** → **Run workflow**.
Flow: test → `az acr build` (image tagged with commit SHA) → deploy DEV + smoke test →
**approve** → PRE-PROD → **approve** → PROD. The same image goes to all three.

## Local development
```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env      # then fill in the DEV endpoint
az login
python -m uvicorn app.main:app --reload --port 8000   # http://localhost:8000/docs
python -m pytest -v
```

## Operations
```powershell
# Logs
az containerapp logs show -n student-agent-dev -g rg-student-dev --type console --follow

# Rollback (PROD)
az containerapp revision set-mode -n student-agent-prod -g rg-student-prod --mode multiple
az containerapp revision list -n student-agent-prod -g rg-student-prod -o table
az containerapp ingress traffic set -n student-agent-prod -g rg-student-prod --revision-weight <GOOD>=100 <BAD>=0
```

## Infra scripts
- `infra/provision.ps1 -Suffix 965lp` — idempotent provisioning of everything above.
- `infra/create_agent.py <project-endpoint>` — creates/updates the Prompt Agent and smoke-tests it.
- `infra/setup_oidc.ps1 -Suffix 965lp [-Repo owner/repo]` — deployer identity, roles, federated credentials.

## Cost / cleanup
PROD keeps 1 replica always on, and the gpt-5.4-mini deployments bill per token. After class:
```powershell
foreach ($g in "rg-student-dev","rg-student-preprod","rg-student-prod","rg-student-shared") { az group delete -n $g --yes --no-wait }
az ad app delete --id 8c263203-25cb-4c78-9f46-f3e9dac45b7b
```
