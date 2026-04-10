<#
.SYNOPSIS
    Obtém token de acesso para Power BI REST API via Service Principal.

.DESCRIPTION
    Autentica usando Client Credentials (Service Principal) e retorna
    o token de acesso para chamadas à API do Power BI.

.PARAMETER TenantId
    ID do tenant Azure AD.

.PARAMETER ClientId
    Application (client) ID do Service Principal.

.PARAMETER ClientSecret
    Client Secret do Service Principal.

.EXAMPLE
    $token = .\Get-PowerBIToken.ps1 -TenantId $env:TENANT_ID -ClientId $env:CLIENT_ID -ClientSecret $env:CLIENT_SECRET
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$ClientSecret
)

$ErrorActionPreference = "Stop"

# Endpoint de autenticação
$tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

# Corpo da requisição
$body = @{
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "https://analysis.windows.net/powerbi/api/.default"
}

try {
    Write-Host "🔐 Autenticando Service Principal..." -ForegroundColor Cyan
    
    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    
    Write-Host "✅ Token obtido com sucesso!" -ForegroundColor Green
    Write-Host "   Expira em: $($response.expires_in) segundos" -ForegroundColor Gray
    
    return $response.access_token
}
catch {
    Write-Error "❌ Falha na autenticação: $_"
    throw
}
