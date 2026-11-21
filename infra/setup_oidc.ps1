<#
  GitHub -> Azure OIDC for the deployment pipeline (lab section 8).

  Step A (no repo needed):  ./infra/setup_oidc.ps1 -Suffix 965lp
      Creates the Entra app 'github-student-agent-deployer', its service principal,
      and least-privilege role assignments.

  Step B (after you create the GitHub repo):
      ./infra/setup_oidc.ps1 -Suffix 965lp -Repo <owner>/<repo>
      Also adds federated credentials for GitHub environments dev, preprod and prod.
#>
param(
    [Parameter(Mandatory)] [string] $Suffix,
    [string] $Repo
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$appName = "github-student-agent-deployer"
$acr     = "acrstudentlab$Suffix"
$sub     = az account show --query id -o tsv
$tenant  = az account show --query tenantId -o tsv

$appId = az ad app list --display-name $appName --query "[0].appId" -o tsv
if (-not $appId) { $appId = az ad app create --display-name $appName --query appId -o tsv }
$spId = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv
if (-not $spId) { $spId = az ad sp create --id $appId --query id -o tsv }

# az acr build needs more than AcrPush (it schedules an ACR Task), so the deployer gets
# Contributor scoped to the registry only, plus AcrPush for the push itself.
$acrId = az acr show -n $acr --query id -o tsv
az role assignment create --assignee-object-id $spId --assignee-principal-type ServicePrincipal --role AcrPush --scope $acrId -o none
az role assignment create --assignee-object-id $spId --assignee-principal-type ServicePrincipal --role Contributor --scope $acrId -o none
foreach ($k in "dev","preprod","prod") {
    $rgId = az group show -n "rg-student-$k" --query id -o tsv
    az role assignment create --assignee-object-id $spId --assignee-principal-type ServicePrincipal --role Contributor --scope $rgId -o none
}

if ($Repo) {
    $tmp = New-TemporaryFile
    $existing = az ad app federated-credential list --id $appId --query "[].name" -o tsv
    foreach ($k in "dev","preprod","prod") {
        $name = "github-$($Repo.Replace('/','-'))-$k"
        if ($existing -contains $name) { continue }
        @{ name = $name; issuer = "https://token.actions.githubusercontent.com"
           subject = "repo:${Repo}:environment:$k"; audiences = @("api://AzureADTokenExchange") } |
            ConvertTo-Json | Set-Content $tmp -Encoding utf8
        az ad app federated-credential create --id $appId --parameters "@$tmp" -o none
        Write-Host "Federated credential added: repo:${Repo}:environment:$k"
    }
    Remove-Item $tmp
} else {
    Write-Host "No -Repo given: federated credentials NOT created yet. Re-run with -Repo <owner>/<repo>."
}

Write-Host "`nAZURE_CLIENT_ID=$appId`nAZURE_TENANT_ID=$tenant`nAZURE_SUBSCRIPTION_ID=$sub`nACR_NAME=$acr"
