# Scripts de Deploy Power BI

Scripts para automação de deploy de relatórios Power BI via REST API.

## Pré-requisitos

### 1. Service Principal no Azure AD

Criar um App Registration com as seguintes permissões da API do Power BI:
- `Dataset.ReadWrite.All`
- `Report.ReadWrite.All`
- `Workspace.ReadWrite.All`

### 2. Configurar no Power BI Admin Portal

1. Acesse **Admin Portal** → **Tenant settings**
2. Em **Developer settings**, habilite:
   - "Service principals can use Fabric APIs"
   - "Service principals can access read-only admin APIs"
3. Adicione o Security Group do Service Principal

### 3. Permissões no Workspace

Adicione o Service Principal como **Admin** ou **Member** em cada workspace.

## GitHub Secrets Necessários

Configure os seguintes secrets no repositório:

| Secret | Descrição |
|--------|-----------|
| `AZURE_TENANT_ID` | ID do tenant Azure AD |
| `AZURE_CLIENT_ID` | Application (client) ID do Service Principal |
| `AZURE_CLIENT_SECRET` | Client Secret gerado |

## Scripts Disponíveis

### `Get-PowerBIToken.ps1`

Obtém token OAuth2 para autenticação na API.

```powershell
$token = .\Get-PowerBIToken.ps1 `
  -TenantId "seu-tenant-id" `
  -ClientId "seu-client-id" `
  -ClientSecret "seu-secret"
```

### `Deploy-PowerBIReport.ps1`

Publica um arquivo .pbix no workspace especificado.

```powershell
.\Deploy-PowerBIReport.ps1 `
  -PbixPath "./MeuRelatorio.pbix" `
  -WorkspaceId "guid-do-workspace" `
  -ReportName "Nome do Relatório" `
  -AccessToken $token `
  -ConflictAction "CreateOrOverwrite"
```

**Parâmetros:**
- `ConflictAction`: `CreateOrOverwrite` (sobrescreve), `Ignore`, ou `Abort`

### `Invoke-DatasetRefresh.ps1`

Dispara refresh do dataset após deploy.

```powershell
.\Invoke-DatasetRefresh.ps1 `
  -WorkspaceId "guid-do-workspace" `
  -DatasetId "guid-do-dataset" `
  -AccessToken $token `
  -WaitForCompletion
```

## Estrutura de Environments do GitHub

Configure os seguintes environments em **Settings → Environments**:

| Environment | Proteção | Uso |
|-------------|----------|-----|
| `HML` | Nenhuma (deploy automático) | Homologação |
| `PROD_SUSTENTACAO` | Required reviewers | Gate 1 - Time de Sustentação |
| `PROD_OWNER_*` | Required reviewers | Gate 2 - Owner do workspace |

Exemplo para workspace `exemplo_fin`:
- Crie `PROD_OWNER_EXEMPLO` com os aprovadores do negócio

## Fluxo Completo

```
Issue criada → Validação → Deploy HML → [Aprovação Sustentação] → [Aprovação Owner] → Deploy PROD
```
