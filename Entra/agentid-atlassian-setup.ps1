<#
  Entra Agent ID <-> Atlassian MCP gateway: lab setup, step by step.
  Uses only Microsoft.Graph.Authentication + Invoke-MgGraphRequest with explicit v1.0/beta URIs.
  Run the blocks one at a time. Nothing here has been executed against the tenant yet.
  Design rationale: agentid-atlassian-design.md (same folder).
#>

# --- 0. Connect (pin one auth module version to avoid assembly conflicts) -------------
# Get-Module Microsoft.Graph.Authentication -ListAvailable | Select Version
Import-Module Microsoft.Graph.Authentication -RequiredVersion '<x.y.z>'
$tenantId = '<tenant-guid>'
Connect-MgGraph -TenantId $tenantId -NoWelcome -Scopes @(
  'Application.ReadWrite.All',                        # gateway + client app regs
  'AgentIdentityBlueprint.ReadWrite.All',
  'AgentIdentityBlueprint.AddRemoveCreds.All',
  'AgentIdentityBlueprint.UpdateAuthProperties.All',
  'AgentIdentity.Create.All',                         # or AgentIdentity.ReadWrite.All
  'AppRoleAssignment.ReadWrite.All',
  'DelegatedPermissionGrant.ReadWrite.All'
)
# Directory role for the signed-in admin: Agent ID Administrator (+ Privileged Role Admin / Cloud App Admin for grants).
# If consent for the AgentIdentity* scopes fails on the Graph CLI app, use your own management app (-ClientId).

$h  = @{ 'OData-Version' = '4.0' }
$bpAppId = 'ed3dafa1-ffe5-4a14-a63a-8176cb3e86de'   # appId (client_id, api://, resourceAppId)
$bpObjId = 'ed3dafa1-ffe5-4a14-a63a-8176cb3e86de'   # application object id -- identical to appId for this blueprint (confirmed in portal)
$bpSpId  = '8c076b2c-116e-4ce2-a8ad-0b7d8d6df0be'   # blueprint PRINCIPAL object id -> use wherever a service principal id is needed
$me      = (Invoke-MgGraphRequest GET 'https://graph.microsoft.com/v1.0/me?$select=id').id

# --- 1. Verify blueprint IDs (read-only) ------------------------------------------------
$bp = Invoke-MgGraphRequest GET "https://graph.microsoft.com/beta/applications(appId='$bpAppId')?`$select=id,appId,displayName,identifierUris,api,web,isSingleInstance" -Headers $h
$bp | Select-Object id, appId, displayName, isSingleInstance, identifierUris
# For this blueprint id == appId (unlike classic app registrations). Sanity check only:
if ($bp.id -ne $bpObjId) { Write-Warning "Object id differs from expected: $($bp.id)"; $bpObjId = $bp.id }
Invoke-MgGraphRequest GET "https://graph.microsoft.com/beta/servicePrincipals/$bpSpId`?`$select=id,appId,displayName,servicePrincipalType" -Headers $h
# Expect @odata.type '#microsoft.graph.agentIdentityBlueprintPrincipal' and appId = $bpAppId -> multi-instance.

# --- 2. Secretless credential: FIC -> user-assigned MI (v1.0) --------------------------
# Create a UAMI in Azure first (portal or: az identity create -g <rg> -n uami-poc-lvl1), attach it to the Container App / AKS node or pod.
$uamiPrincipalId = '<uami-principalId (object id), NOT clientId>'
Invoke-MgGraphRequest POST "https://graph.microsoft.com/v1.0/applications/$bpObjId/federatedIdentityCredentials" -Headers $h -Body (@{
  name      = 'uami-poc-lvl1'
  issuer    = "https://login.microsoftonline.com/$tenantId/v2.0"
  subject   = $uamiPrincipalId
  audiences = @('api://AzureADTokenExchange')
} | ConvertTo-Json)

# Lab/local only (secret is returned once; not for production):
# Invoke-MgGraphRequest POST "https://graph.microsoft.com/v1.0/applications/$bpObjId/addPassword" -Body (@{ passwordCredential = @{ displayName='lab'; endDateTime=(Get-Date).AddDays(30).ToString('o') } } | ConvertTo-Json)

# --- 3. Gateway resource app (separate from the blueprint) ------------------------------
# Needs: Application.ReadWrite.All (delegated) + Cloud Application Administrator / Application Administrator.
# Idempotent: upsert on uniqueName, existing role/scope GUIDs are reused on re-run.
$gwUnique = 'atlassian-mcp-gateway-lab'          # immutable once set
$gwName   = 'Atlassian MCP Gateway (lab)'
# Optional: force a specific existing gateway by appId. Leave empty to auto-detect (uniqueName, then displayName).
$gwAppIdExisting = ''                             # e.g. '11111111-2222-...'

# App roles = Atlassian MCP v2 permission groups (supported-tools page, 2026-11-18). Tool mapping: gateway-policy.yaml.
# A = Application (agent identities, app-only), U = User (groups, OBO). OAuth-only groups are User-only:
# Atlassian service-account keys / API tokens cannot serve them, so an app-only agent must never hold them.
$roleDefs = @(
  @{ v='Jira.Read';              m='AU'; d='Read Jira work items, projects, boards (read:jira:agent-interface)' }
  @{ v='Jira.Search';            m='AU'; d='JQL search (search:jira:agent-interface)' }
  @{ v='Jira.Write';             m='AU'; d='Create/edit/transition/comment Jira (write:jira:agent-interface)' }
  @{ v='Jira.Delete';            m='AU'; d='Permanently delete Jira issues/comments/attachments (delete:jira:agent-interface)' }
  @{ v='Jira.Manage';            m='AU'; d='Jira project/workflow/screen admin (manage:jira:agent-interface)' }
  @{ v='Confluence.Read';        m='AU'; d='Read Confluence content (read:confluence:agent-interface)' }
  @{ v='Confluence.Search';      m='AU'; d='CQL search (search:confluence:agent-interface)' }
  @{ v='Confluence.Write';       m='AU'; d='Create/update Confluence content (write:confluence:agent-interface)' }
  @{ v='Confluence.Share';       m='AU'; d='Change Confluence permissions/public links (write:confluence:agent-interface)' }
  @{ v='Jsm.Read';               m='AU'; d='Read JSM requests/ops (read:jsm:agent-interface)' }
  @{ v='Jsm.Write';              m='AU'; d='Create/transition/approve JSM (write:jsm:agent-interface)' }
  @{ v='Bitbucket.Read';         m='AU'; d='Read Bitbucket repos/PRs/pipelines (read:bitbucket:agent-interface)' }
  @{ v='Bitbucket.Write';        m='AU'; d='PRs, branches, commits, pipelines (write:bitbucket:agent-interface)' }
  @{ v='TeamworkGraph.Read';     m='AU'; d='Teamwork Graph context, Rovo credits (read:all:twg)' }
  @{ v='TeamworkGraph.Write';    m='AU'; d='Add Teamwork Graph relationships (write:all:twg)' }
  @{ v='Rovo.Search';            m='AU'; d='Rovo semantic search, Rovo credits (search:rovo:agent-interface)' }
  @{ v='Code.Search';            m='U';  d='Code search, OAuth only (search:code:agent-interface)' }
  @{ v='Assets.Read';            m='AU'; d='Read Assets objects (read:assets:agent-interface)' }
  @{ v='Loom.Read';              m='AU'; d='Read Loom (read:loom:agent-interface)' }
  @{ v='Loom.Write';             m='AU'; d='Write Loom (write:loom:agent-interface)' }
  @{ v='Goals.Read';             m='AU'; d='Read Goals (read:goals:agent-interface)' }
  @{ v='Goals.Write';            m='AU'; d='Write Goals (write:goals:agent-interface)' }
  @{ v='Projects.Read';          m='AU'; d='Read Projects (read:projects:agent-interface)' }
  @{ v='Projects.Write';         m='AU'; d='Write Projects (write:projects:agent-interface)' }
  @{ v='Teams.Read';             m='U';  d='Read Teams, OAuth only (read:teams:agent-interface)' }
  @{ v='Teams.Write';            m='U';  d='Write Teams, OAuth only (write:teams:agent-interface)' }
  @{ v='Focus.Read';             m='AU'; d='Read Focus areas (read:focus:agent-interface)' }
  @{ v='Focus.Write';            m='AU'; d='Write Focus areas (write:focus:agent-interface)' }
  @{ v='Talent.Read';            m='AU'; d='Read Talent (read:talent:agent-interface)' }
  @{ v='Talent.Write';           m='AU'; d='Write Talent (write:talent:agent-interface)' }
  @{ v='CapacityPlanning.Read';  m='AU'; d='Read capacity plans (read:capacity-planning:agent-interface)' }
  @{ v='CapacityPlanning.Write'; m='AU'; d='Write capacity plans (write:capacity-planning:agent-interface)' }
  @{ v='JiraAlign.Read';         m='U';  d='Read Jira Align, OAuth only (read:jira-align:agent-interface)' }
  @{ v='JiraAlign.Write';        m='U';  d='Write Jira Align, OAuth only (write:jira-align:agent-interface)' }
  @{ v='Insights.Read';          m='U';  d='Insights incl. SQL/AI queries, OAuth only (read:insights:agent-interface)' }
)
$scopeDefs = [ordered]@{                          # coarse delegated scopes for OBO (inherited by blueprint children)
  'Atlassian.Read'   = 'Read/search Atlassian content via the gateway on behalf of the signed-in user'
  'Atlassian.Write'  = 'Create/update Atlassian content via the gateway on behalf of the signed-in user'
  'Atlassian.Delete' = 'Delete content and administer Jira projects via the gateway on behalf of the signed-in user'
}

# Resolve the gateway app - works for both portal-created and script-created apps:
#   1. $gwAppIdExisting set            -> that app (must exist)
#   2. app with uniqueName $gwUnique   -> script-created app
#   3. exactly one app named $gwName   -> portal-created app (matched by displayName)
#   4. none found                      -> create via upsert on uniqueName
#   more than one match by name        -> stop; set $gwAppIdExisting to pick one
$g = 'https://graph.microsoft.com/v1.0'
function Get-GatewayApp {
  param($AppId, $UniqueName, $DisplayName)
  if ($AppId) {
    $a = try { Invoke-MgGraphRequest GET "$g/applications(appId='$AppId')" } catch { $null }
    if (-not $a) { throw "No application with appId $AppId" }
    return @{ App = $a; Mode = 'appId (explicit)'; Uri = "$g/applications(appId='$AppId')" }
  }
  $a = try { Invoke-MgGraphRequest GET "$g/applications(uniqueName='$UniqueName')" } catch { $null }
  if ($a) { return @{ App = $a; Mode = 'uniqueName (script-created)'; Uri = "$g/applications(uniqueName='$UniqueName')" } }
  $byName = @((Invoke-MgGraphRequest GET "$g/applications?`$filter=displayName eq '$($DisplayName -replace "'","''")'").value)
  if ($byName.Count -gt 1) { throw "$($byName.Count) apps named '$DisplayName' (appIds: $($byName.appId -join ', ')). Set `$gwAppIdExisting to the right one." }
  if ($byName.Count -eq 1) { return @{ App = $byName[0]; Mode = 'displayName (portal-created)'; Uri = "$g/applications(appId='$($byName[0].appId)')" } }
  return @{ App = $null; Mode = 'new (create via uniqueName upsert)'; Uri = "$g/applications(uniqueName='$UniqueName')" }
}
$resolved   = Get-GatewayApp -AppId $gwAppIdExisting -UniqueName $gwUnique -DisplayName $gwName
$gwExisting = $resolved.App
$gwUri      = $resolved.Uri
"Gateway resolved by: $($resolved.Mode)$(if ($gwExisting) { "  appId=$($gwExisting.appId)" })"
function Get-StableId($list, $value) {
  $hit = @($list) | Where-Object { $_.value -eq $value } | Select-Object -First 1
  if ($hit) { $hit.id } else { [guid]::NewGuid().Guid }
}

$appRoles = foreach ($r in $roleDefs) {
  $mt = @(); if ($r.m -like '*A*') { $mt += 'Application' }; if ($r.m -like '*U*') { $mt += 'User' }
  @{ id = (Get-StableId $gwExisting.appRoles $r.v); value = $r.v; displayName = $r.v; description = $r.d
     allowedMemberTypes = $mt; isEnabled = $true }
}
# Keep roles/scopes that exist on the app but are no longer defined here (Graph refuses to drop enabled ones).
$appRoles += @($gwExisting.appRoles | Where-Object { $_.value -notin $roleDefs.v })
$definedScopes = @($scopeDefs.Keys)
$scopes = foreach ($k in $scopeDefs.Keys) {
  @{ id = (Get-StableId $gwExisting.api.oauth2PermissionScopes $k); value = $k; type = 'Admin'; isEnabled = $true
     adminConsentDisplayName = $k; adminConsentDescription = $scopeDefs[$k] }
}
$scopes = @($scopes) + @($gwExisting.api.oauth2PermissionScopes | Where-Object { $_.value -notin $definedScopes })

# 3a. Upsert the application object
$upsertHeaders = if ($gwExisting) { @{} } else { @{ Prefer = 'create-if-missing' } }   # only create when nothing was found
$gwBody = @{
  api            = @{ requestedAccessTokenVersion = 2; oauth2PermissionScopes = @($scopes) }
  appRoles       = @($appRoles)
  optionalClaims = @{ accessToken = @(@{ name = 'idtyp' }) }   # 'app' vs 'user' token type for the gateway
}
if (-not $gwExisting) { $gwBody.displayName = $gwName; $gwBody.signInAudience = 'AzureADMyOrg' }   # existing app keeps its name/audience
Invoke-MgGraphRequest PATCH $gwUri -Headers $upsertHeaders -Body ($gwBody | ConvertTo-Json -Depth 8)
$gw = Invoke-MgGraphRequest GET "$gwUri`?`$select=id,appId,displayName,identifierUris,appRoles,api"

# 3b. Application ID URI (needs appId, so a second call)
if ($gw.identifierUris -notcontains "api://$($gw.appId)") {
  Invoke-MgGraphRequest PATCH "https://graph.microsoft.com/v1.0/applications/$($gw.id)" -Body (@{ identifierUris = @("api://$($gw.appId)") } | ConvertTo-Json)
}

# 3c. Owner (you) on the app object
try { Invoke-MgGraphRequest POST "https://graph.microsoft.com/v1.0/applications/$($gw.id)/owners/`$ref" -Body (@{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$me" } | ConvertTo-Json) } catch { }   # 400 if already owner

# 3d. Service principal, assignment required from the start
$gwSp = try { Invoke-MgGraphRequest GET "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$($gw.appId)')" } catch { $null }
if (-not $gwSp) {
  $gwSp = Invoke-MgGraphRequest POST 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body (@{
    appId = $gw.appId
    appRoleAssignmentRequired = $true
    tags = @('HideApp','WindowsAzureActiveDirectoryIntegratedApp')     # hide from My Apps
  } | ConvertTo-Json)
} elseif (-not $gwSp.appRoleAssignmentRequired) {
  Invoke-MgGraphRequest PATCH "https://graph.microsoft.com/v1.0/servicePrincipals/$($gwSp.id)" -Body (@{ appRoleAssignmentRequired = $true } | ConvertTo-Json)
}

# 3e. Verify + capture IDs used later
$gwSp = Invoke-MgGraphRequest GET "https://graph.microsoft.com/v1.0/servicePrincipals/$($gwSp.id)?`$select=id,appId,appRoleAssignmentRequired,appRoles,oauth2PermissionScopes"
$roleId  = @{}; $gwSp.appRoles               | ForEach-Object { $roleId[$_.value]  = $_.id }
$scopeId = @{}; $gwSp.oauth2PermissionScopes | ForEach-Object { $scopeId[$_.value] = $_.id }
[pscustomobject]@{ AppObjectId = $gw.id; AppId = $gw.appId; SpObjectId = $gwSp.id; AssignmentRequired = $gwSp.appRoleAssignmentRequired
                   IdentifierUri = "api://$($gw.appId)"; Roles = ($roleId.Keys -join ','); Scopes = ($scopeId.Keys -join ',') } | Format-List
# Removing a role/scope later: first PATCH it with isEnabled=$false, then PATCH again without it (Graph rejects deleting an enabled one).
# No credential on this app: the gateway only VALIDATES tokens. Its own outbound access (Key Vault, Graph) uses the gateway host's UAMI.

# --- 4. Agent identity (beta) -----------------------------------------------------------
$agent = Invoke-MgGraphRequest POST 'https://graph.microsoft.com/beta/servicePrincipals/microsoft.graph.agentIdentity' -Headers $h -Body (@{
  displayName              = 'POC-LVL1-agent-01'
  agentIdentityBlueprintId = $bpAppId     # docs conflict (appId vs object id) -- moot here, both are ed3dafa1-...
  'sponsors@odata.bind'    = @("https://graph.microsoft.com/v1.0/users/$me")
} | ConvertTo-Json)
$agent | Select-Object id, appId, displayName, agentIdentityBlueprintId, instanceMode
# id    -> appRoleAssignments, Graph object ops
# appId -> fmi_path, client_id in token requests, sidecar AgentIdentity

# --- 5. MODE 1: app-role assignment per agent identity (v1.0) ---------------------------
foreach ($cap in 'Jira.Read','Rovo.Search') {   # capabilities for this agent
  Invoke-MgGraphRequest POST "https://graph.microsoft.com/v1.0/servicePrincipals/$($gwSp.id)/appRoleAssignedTo" -Body (@{
    principalId = $agent.id; resourceId = $gwSp.id; appRoleId = $roleId[$cap]
  } | ConvertTo-Json)
}

# --- 6. MODE 2: blueprint as inbound audience + inheritable delegated scope ------------
# 6a. Expose api://<blueprintAppId>/access_agent (PATCH replaces arrays -> merge with existing $bp.api.oauth2PermissionScopes)
$existing = @($bp.api.oauth2PermissionScopes)
$accessAgent = @{ id = [guid]::NewGuid().Guid; value = 'access_agent'; type = 'User'; isEnabled = $true
  adminConsentDisplayName = 'Access agent'; adminConsentDescription = 'Allow the client to call the agent on behalf of the signed-in user.' }
Invoke-MgGraphRequest PATCH "https://graph.microsoft.com/v1.0/applications/$bpObjId" -Headers $h -Body (@{
  identifierUris = @("api://$bpAppId")
  api = @{ requestedAccessTokenVersion = 2; oauth2PermissionScopes = @($existing + $accessAgent) }
} | ConvertTo-Json -Depth 6)

# 6b. Inheritable permissions (BETA): children may inherit AtlassianMcp.Invoke on the gateway
Invoke-MgGraphRequest POST "https://graph.microsoft.com/beta/applications/$bpObjId/microsoft.graph.agentIdentityBlueprint/inheritablePermissions" -Body (@{
  resourceAppId     = $gw.appId
  inheritableScopes = @{ '@odata.type' = 'microsoft.graph.enumeratedScopes'; scopes = @('Atlassian.Read','Atlassian.Write') }
} | ConvertTo-Json)

# 6c. Admin consent on the BLUEPRINT PRINCIPAL (inheritance only flows if the scope is granted here)
Invoke-MgGraphRequest POST 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -Body (@{
  clientId = $bpSpId; consentType = 'AllPrincipals'; resourceId = $gwSp.id; scope = 'Atlassian.Read Atlassian.Write'
} | ConvertTo-Json)

# 6d. Front-end client app (user signs in here; gets token aud = blueprint). SPA example:
$fe = Invoke-MgGraphRequest POST 'https://graph.microsoft.com/v1.0/applications' -Body (@{
  displayName = 'POC-LVL1 chat client (lab)'; signInAudience = 'AzureADMyOrg'
  spa = @{ redirectUris = @('http://localhost:5173') }
  requiredResourceAccess = @(@{ resourceAppId = $bpAppId; resourceAccess = @(@{ id = $accessAgent.id; type = 'Scope' }) })
} | ConvertTo-Json -Depth 6)
$feSp = Invoke-MgGraphRequest POST 'https://graph.microsoft.com/v1.0/servicePrincipals' -Body (@{ appId = $fe.appId } | ConvertTo-Json)
Invoke-MgGraphRequest POST 'https://graph.microsoft.com/v1.0/oauth2PermissionGrants' -Body (@{
  clientId = $feSp.id; consentType = 'AllPrincipals'; resourceId = $bpSpId; scope = 'access_agent'
} | ConvertTo-Json)
# resourceId = blueprint PRINCIPAL object id (8c076b2c-...), never the blueprint app/object id ed3dafa1-...
# (assumes the blueprint principal acts as the resource SP for api://<bpAppId> -- verify)

# --- 7. Token flows the sidecar performs (for testing from a host with the UAMI, or with the lab secret) ----
$tokenUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
# 7a. UAMI token (Azure IMDS; Container Apps uses IDENTITY_ENDPOINT/IDENTITY_HEADER instead)
# $mi = Invoke-RestMethod -Headers @{Metadata='true'} "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=api://AzureADTokenExchange&client_id=<uami-clientId>"
# 7b. T1 (blueprint impersonation for this agent)
# $t1 = Invoke-RestMethod -Method POST $tokenUrl -Body @{ client_id=$bpAppId; scope='api://AzureADTokenExchange/.default'; fmi_path=$agent.appId;
#        client_assertion_type='urn:ietf:params:oauth:client-assertion-type:jwt-bearer'; client_assertion=$mi.access_token; grant_type='client_credentials' }
#        (lab: replace the assertion pair with client_secret=<secret>)
# 7c. MODE 1 app-only token for the gateway
# $tr = Invoke-RestMethod -Method POST $tokenUrl -Body @{ client_id=$agent.appId; scope="api://$($gw.appId)/.default";
#        client_assertion_type='urn:ietf:params:oauth:client-assertion-type:jwt-bearer'; client_assertion=$t1.access_token; grant_type='client_credentials' }
# 7d. MODE 2 OBO (userToken must have aud = $bpAppId, scp access_agent)
# $obo = Invoke-RestMethod -Method POST $tokenUrl -Body @{ client_id=$agent.appId; scope="api://$($gw.appId)/Atlassian.Read api://$($gw.appId)/Atlassian.Write";
#        client_assertion_type='urn:ietf:params:oauth:client-assertion-type:jwt-bearer'; client_assertion=$t1.access_token;
#        grant_type='urn:ietf:params:oauth:grant-type:jwt-bearer'; assertion=$userToken; requested_token_use='on_behalf_of' }
# Decode and check: aud = gateway, roles/scp, azp(appid) = agent appId, oid = agent (mode 1) or user (mode 2).

# --- 8. Atlassian side (manual, Atlassian Administration) -------------------------------
# Mode 1: Connectors > Atlassian MCP server > Authentication: API token ON; create service account + API key (scopes);
#         store key in Key Vault (gateway UAMI = Key Vault Secrets User); IP allowlist: gateway egress IP.
# Mode 2: gateway registers as OAuth client via DCR  POST https://mcp.atlassian.com/v1/register  (redirect https://<gateway>/atlassian/callback),
#         auth code + PKCE S256 at /v1/authorize, /v1/token; scopes e.g. read:jira:agent-interface search:rovo:agent-interface read:me offline_access;
#         add gateway domain under Connectors > Atlassian MCP server > domains; Atlassian Guard SSO with Entra so users sign in with the same identity.

# --- Cleanup -----------------------------------------------------------------------------
# Invoke-MgGraphRequest DELETE "https://graph.microsoft.com/beta/servicePrincipals/$($agent.id)/microsoft.graph.agentIdentity" -Headers $h
