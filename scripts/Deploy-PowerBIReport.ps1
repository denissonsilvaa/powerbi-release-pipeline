<#
.SYNOPSIS
    Deploy de relatório Power BI para workspace especificado.

.DESCRIPTION
    Importa um arquivo .pbix para um workspace do Power BI via REST API.
    Suporta substituição de relatórios existentes e configuração de conexões.

.PARAMETER PbixPath
    Caminho para o arquivo .pbix a ser publicado.

.PARAMETER WorkspaceId
    GUID do workspace de destino.

.PARAMETER ReportName
    Nome do relatório no Power BI (sem extensão).

.PARAMETER AccessToken
    Token de acesso OAuth2.

.PARAMETER ConflictAction
    Ação em caso de conflito: CreateOrOverwrite, Ignore, Abort. Default: CreateOrOverwrite.

.EXAMPLE
    .\Deploy-PowerBIReport.ps1 -PbixPath "./report.pbix" -WorkspaceId "xxx-xxx" -ReportName "Vendas" -AccessToken $token
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$PbixPath,

    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId,

    [Parameter(Mandatory = $true)]
    [string]$ReportName,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [ValidateSet("CreateOrOverwrite", "Ignore", "Abort")]
    [string]$ConflictAction = "CreateOrOverwrite"
)

$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURAÇÃO
# ============================================================================

$baseUrl = "https://api.powerbi.com/v1.0/myorg"
$headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type"  = "application/json"
}

# ============================================================================
# FUNÇÕES AUXILIARES
# ============================================================================

function Write-Step {
    param([string]$Message, [string]$Status = "INFO")
    $icon = switch ($Status) {
        "INFO"    { "📋" }
        "SUCCESS" { "✅" }
        "ERROR"   { "❌" }
        "WARN"    { "⚠️" }
        default   { "▶️" }
    }
    Write-Host "$icon $Message" -ForegroundColor $(
        switch ($Status) {
            "SUCCESS" { "Green" }
            "ERROR"   { "Red" }
            "WARN"    { "Yellow" }
            default   { "Cyan" }
        }
    )
}

function Test-WorkspaceAccess {
    param([string]$WorkspaceId)
    
    try {
        $url = "$baseUrl/groups/$WorkspaceId"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        return $response
    }
    catch {
        return $null
    }
}

function Get-ExistingReport {
    param([string]$WorkspaceId, [string]$ReportName)
    
    $url = "$baseUrl/groups/$WorkspaceId/reports"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    
    return $response.value | Where-Object { $_.name -eq $ReportName }
}

function Import-PbixFile {
    param(
        [string]$WorkspaceId,
        [string]$PbixPath,
        [string]$ReportName,
        [string]$ConflictAction
    )
    
    # Prepara multipart form-data
    $fileName = [System.IO.Path]::GetFileName($PbixPath)
    $fileBytes = [System.IO.File]::ReadAllBytes($PbixPath)
    $fileEnc = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($fileBytes)
    
    $boundary = [System.Guid]::NewGuid().ToString()
    
    $bodyLines = @(
        "--$boundary",
        "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"",
        "Content-Type: application/octet-stream",
        "",
        $fileEnc,
        "--$boundary--"
    ) -join "`r`n"
    
    $url = "$baseUrl/groups/$WorkspaceId/imports?datasetDisplayName=$ReportName&nameConflict=$ConflictAction"
    
    $importHeaders = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "multipart/form-data; boundary=$boundary"
    }
    
    $response = Invoke-RestMethod -Uri $url -Headers $importHeaders -Method Post -Body $bodyLines
    
    return $response
}

function Wait-ImportCompletion {
    param(
        [string]$WorkspaceId,
        [string]$ImportId,
        [int]$TimeoutSeconds = 300,
        [int]$PollIntervalSeconds = 5
    )
    
    $url = "$baseUrl/groups/$WorkspaceId/imports/$ImportId"
    $elapsed = 0
    
    while ($elapsed -lt $TimeoutSeconds) {
        $status = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        
        Write-Host "   Status: $($status.importState)" -ForegroundColor Gray
        
        if ($status.importState -eq "Succeeded") {
            return $status
        }
        elseif ($status.importState -eq "Failed") {
            throw "Import falhou: $($status.error.code) - $($status.error.message)"
        }
        
        Start-Sleep -Seconds $PollIntervalSeconds
        $elapsed += $PollIntervalSeconds
    }
    
    throw "Timeout aguardando conclusão do import ($TimeoutSeconds segundos)"
}

# ============================================================================
# EXECUÇÃO PRINCIPAL
# ============================================================================

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "  POWER BI DEPLOY SCRIPT" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

# 1. Validar arquivo PBIX
Write-Step "Validando arquivo PBIX..."
if (-not (Test-Path $PbixPath)) {
    Write-Step "Arquivo não encontrado: $PbixPath" "ERROR"
    exit 1
}
$fileSize = (Get-Item $PbixPath).Length / 1MB
Write-Step "Arquivo: $PbixPath ($([math]::Round($fileSize, 2)) MB)" "SUCCESS"

# 2. Verificar acesso ao workspace
Write-Step "Verificando acesso ao workspace..."
$workspace = Test-WorkspaceAccess -WorkspaceId $WorkspaceId
if (-not $workspace) {
    Write-Step "Sem acesso ao workspace $WorkspaceId" "ERROR"
    exit 1
}
Write-Step "Workspace: $($workspace.name)" "SUCCESS"

# 3. Verificar relatório existente
Write-Step "Verificando relatório existente..."
$existingReport = Get-ExistingReport -WorkspaceId $WorkspaceId -ReportName $ReportName
if ($existingReport) {
    Write-Step "Relatório '$ReportName' existe (ID: $($existingReport.id)). Ação: $ConflictAction" "WARN"
} else {
    Write-Step "Relatório '$ReportName' será criado" "INFO"
}

# 4. Importar PBIX
Write-Step "Iniciando upload do PBIX..."
try {
    $importResult = Import-PbixFile -WorkspaceId $WorkspaceId -PbixPath $PbixPath -ReportName $ReportName -ConflictAction $ConflictAction
    Write-Step "Upload iniciado. Import ID: $($importResult.id)" "SUCCESS"
}
catch {
    Write-Step "Falha no upload: $_" "ERROR"
    exit 1
}

# 5. Aguardar conclusão
Write-Step "Aguardando processamento..."
try {
    $finalStatus = Wait-ImportCompletion -WorkspaceId $WorkspaceId -ImportId $importResult.id
    Write-Step "Import concluído com sucesso!" "SUCCESS"
}
catch {
    Write-Step "Falha no processamento: $_" "ERROR"
    exit 1
}

# 6. Resultado final
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  DEPLOY CONCLUÍDO" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  📊 Relatório: $ReportName" -ForegroundColor White
Write-Host "  📁 Workspace: $($workspace.name)" -ForegroundColor White
Write-Host "  🔗 Report ID: $($finalStatus.reports[0].id)" -ForegroundColor White
Write-Host "  📦 Dataset ID: $($finalStatus.datasets[0].id)" -ForegroundColor White
Write-Host ""

# Output para GitHub Actions
if ($env:GITHUB_OUTPUT) {
    "report_id=$($finalStatus.reports[0].id)" >> $env:GITHUB_OUTPUT
    "dataset_id=$($finalStatus.datasets[0].id)" >> $env:GITHUB_OUTPUT
    "workspace_name=$($workspace.name)" >> $env:GITHUB_OUTPUT
}

exit 0
