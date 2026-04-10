<#
.SYNOPSIS
    Dispara refresh de dataset no Power BI.

.DESCRIPTION
    Inicia o refresh de um dataset e aguarda a conclusão.
    Útil após deploy quando as conexões já estão configuradas.

.PARAMETER WorkspaceId
    GUID do workspace.

.PARAMETER DatasetId
    GUID do dataset.

.PARAMETER AccessToken
    Token de acesso OAuth2.

.PARAMETER WaitForCompletion
    Se deve aguardar a conclusão do refresh.

.EXAMPLE
    .\Invoke-DatasetRefresh.ps1 -WorkspaceId "xxx" -DatasetId "yyy" -AccessToken $token -WaitForCompletion
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$DatasetId,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [switch]$WaitForCompletion,

    [Parameter(Mandatory = $false)]
    [int]$TimeoutMinutes = 30
)

$ErrorActionPreference = "Stop"

$baseUrl = "https://api.powerbi.com/v1.0/myorg"
$headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type"  = "application/json"
}

# ============================================================================
# FUNÇÕES
# ============================================================================

function Get-DatasetInfo {
    param([string]$WorkspaceId, [string]$DatasetId)
    
    $url = "$baseUrl/groups/$WorkspaceId/datasets/$DatasetId"
    return Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}

function Start-Refresh {
    param([string]$WorkspaceId, [string]$DatasetId)
    
    $url = "$baseUrl/groups/$WorkspaceId/datasets/$DatasetId/refreshes"
    $body = @{ notifyOption = "NoNotification" } | ConvertTo-Json
    
    Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $body
}

function Get-RefreshHistory {
    param([string]$WorkspaceId, [string]$DatasetId, [int]$Top = 1)
    
    $url = "$baseUrl/groups/$WorkspaceId/datasets/$DatasetId/refreshes?`$top=$Top"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    return $response.value
}

# ============================================================================
# EXECUÇÃO
# ============================================================================

Write-Host ""
Write-Host "🔄 DATASET REFRESH" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════════════" -ForegroundColor Cyan

# 1. Obter informações do dataset
Write-Host "📊 Obtendo informações do dataset..." -ForegroundColor Gray
$dataset = Get-DatasetInfo -WorkspaceId $WorkspaceId -DatasetId $DatasetId
Write-Host "   Dataset: $($dataset.name)" -ForegroundColor White
Write-Host "   Configurado para refresh: $($dataset.isRefreshable)" -ForegroundColor White

if (-not $dataset.isRefreshable) {
    Write-Host "⚠️  Dataset não suporta refresh (Import mode ou sem fonte configurada)" -ForegroundColor Yellow
    exit 0
}

# 2. Disparar refresh
Write-Host "🚀 Disparando refresh..." -ForegroundColor Cyan
try {
    Start-Refresh -WorkspaceId $WorkspaceId -DatasetId $DatasetId
    Write-Host "✅ Refresh iniciado!" -ForegroundColor Green
}
catch {
    if ($_.Exception.Response.StatusCode -eq 400) {
        Write-Host "⚠️  Refresh já em andamento ou conflito" -ForegroundColor Yellow
    }
    else {
        Write-Host "❌ Falha ao disparar refresh: $_" -ForegroundColor Red
        exit 1
    }
}

# 3. Aguardar conclusão (se solicitado)
if ($WaitForCompletion) {
    Write-Host "⏳ Aguardando conclusão (timeout: $TimeoutMinutes min)..." -ForegroundColor Gray
    
    $startTime = Get-Date
    $timeout = $startTime.AddMinutes($TimeoutMinutes)
    
    while ((Get-Date) -lt $timeout) {
        Start-Sleep -Seconds 10
        
        $history = Get-RefreshHistory -WorkspaceId $WorkspaceId -DatasetId $DatasetId
        $latest = $history[0]
        
        Write-Host "   Status: $($latest.status) | $($latest.refreshType)" -ForegroundColor Gray
        
        if ($latest.status -eq "Completed") {
            $duration = [math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
            Write-Host "✅ Refresh concluído em $duration minutos!" -ForegroundColor Green
            exit 0
        }
        elseif ($latest.status -eq "Failed") {
            Write-Host "❌ Refresh falhou: $($latest.serviceExceptionJson)" -ForegroundColor Red
            exit 1
        }
    }
    
    Write-Host "⚠️  Timeout atingido. Refresh ainda em andamento." -ForegroundColor Yellow
    exit 0
}

Write-Host "✅ Refresh disparado (não aguardando conclusão)" -ForegroundColor Green
exit 0
