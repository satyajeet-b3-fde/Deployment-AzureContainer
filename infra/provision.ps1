<#
  Provisions the Azure side of the DEV / PRE-PROD / PROD classroom lab.
  Safe to re-run (create commands are idempotent or skipped when the resource exists).

  Usage:  ./infra/provision.ps1 -Suffix 965lp [-Location eastus2]
#>
param(
    [Parameter(Mandatory)] [string] $Suffix,
    [string] $Location = "eastus2",
    [string] $ModelName = "gpt-5.4-mini",
    [string] $ModelVersion = "2026-03-17",
    [int]    $ModelCapacity = 10
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$sub      = az account show --query id -o tsv
$sharedRg = "rg-student-shared"
$acr      = "acrstudentlab$Suffix"
$envs = @(
    @{ key="dev";     min=0; max=2 },
    @{ key="preprod"; min=0; max=2 },
    @{ key="prod";    min=1; max=3 }
)
$tmp = New-TemporaryFile

function Test-Exists([scriptblock] $cmd) {
    $PSNativeCommandUseErrorActionPreference = $false
    $out = & $cmd 2>$null
    return [bool]$out
}

function Put-Arm($uri, $body) {
    $body | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding utf8
    az rest --method put --uri $uri --body "@$tmp" -o none
}

Write-Host "== Shared: resource group + ACR ($acr)"
az group create -n $sharedRg -l $Location -o none
if (-not (Test-Exists { az acr show -n $acr --query id -o tsv })) {
    az acr create -n $acr -g $sharedRg --sku Basic --admin-enabled false -o none
}
$acrId = az acr show -n $acr --query id -o tsv

foreach ($e in $envs) {
    $k = $e.key
    $rg = "rg-student-$k"; $law = "law-student-$k"; $cae = "cae-student-$k"
    $app = "student-agent-$k"; $aif = "aif-student-$k-$Suffix"; $proj = "foundry-student-$k"

    Write-Host "== [$k] resource group, Log Analytics, Container Apps environment"
    az group create -n $rg -l $Location -o none
    az monitor log-analytics workspace create -g $rg -n $law -l $Location -o none
    $lawCustomerId = az monitor log-analytics workspace show -g $rg -n $law --query customerId -o tsv
    $lawKey = az monitor log-analytics workspace get-shared-keys -g $rg -n $law --query primarySharedKey -o tsv
    if (-not (Test-Exists { az containerapp env show -g $rg -n $cae --query id -o tsv })) {
        az containerapp env create -g $rg -n $cae -l $Location `
            --logs-workspace-id $lawCustomerId --logs-workspace-key $lawKey -o none
    }

    Write-Host "== [$k] Foundry resource $aif + project $proj + $ModelName deployment"
    $acctUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/${aif}?api-version=2025-06-01"
    Put-Arm $acctUri @{
        location = $Location; kind = "AIServices"; sku = @{ name = "S0" }
        identity = @{ type = "SystemAssigned" }
        properties = @{ customSubDomainName = $aif; allowProjectManagement = $true; publicNetworkAccess = "Enabled"; disableLocalAuth = $true }
    }
    do { Start-Sleep 5; $st = az rest --uri $acctUri --query properties.provisioningState -o tsv } while ($st -notin "Succeeded","Failed")
    $projUri = "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$aif/projects/${proj}?api-version=2025-06-01"
    Put-Arm $projUri @{ location = $Location; identity = @{ type = "SystemAssigned" }; properties = @{ displayName = $proj; description = "Student Support AI Agent - $k" } }
    do { Start-Sleep 5; $st = az rest --uri $projUri --query properties.provisioningState -o tsv } while ($st -notin "Succeeded","Failed")
    az cognitiveservices account deployment create -g $rg -n $aif --deployment-name $ModelName `
        --model-name $ModelName --model-version $ModelVersion --model-format OpenAI `
        --sku-name GlobalStandard --sku-capacity $ModelCapacity -o none

    Write-Host "== [$k] waiting for $cae to finish provisioning (can take 20-50 min)"
    while ((az containerapp env show -g $rg -n $cae --query properties.provisioningState -o tsv) -ne "Succeeded") { Start-Sleep 30 }

    Write-Host "== [$k] Container App $app (placeholder image, system-assigned identity)"
    if (-not (Test-Exists { az containerapp show -g $rg -n $app --query id -o tsv })) {
        az containerapp create -g $rg -n $app --environment $cae `
            --image mcr.microsoft.com/k8se/quickstart:latest --target-port 80 --ingress external `
            --cpu 0.5 --memory 1.0Gi --min-replicas $e.min --max-replicas $e.max `
            --system-assigned -o none
    }
    $principal = az containerapp show -g $rg -n $app --query identity.principalId -o tsv
    $aifId = az cognitiveservices account show -g $rg -n $aif --query id -o tsv

    Write-Host "== [$k] RBAC: AcrPull on ACR, Foundry User (formerly 'Azure AI User') on its own Foundry resource"
    az role assignment create --assignee-object-id $principal --assignee-principal-type ServicePrincipal --role AcrPull --scope $acrId -o none
    az role assignment create --assignee-object-id $principal --assignee-principal-type ServicePrincipal --role "Foundry User" --scope $aifId -o none
    az containerapp registry set -g $rg -n $app --server "$acr.azurecr.io" --identity system -o none
}
Remove-Item $tmp
Write-Host "Done."
