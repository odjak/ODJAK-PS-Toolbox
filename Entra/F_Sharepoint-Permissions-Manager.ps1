#Requires -Version 7.4
# PnP.PowerShell 3.x is checked/loaded by Initialize-PnPModule (not #Requires -Modules), so that a conflicting
# older PnP version already loaded in the session gives a clear message instead of an assembly-load exception.

<#
.SYNOPSIS
Interactive PowerShell tool for granting Entra ID applications access to SharePoint Online sites, lists/libraries,
folders, files and list items using "selected" permissions - built entirely on PnP.PowerShell 3.x cmdlets.

.DESCRIPTION
When an Entra ID application uses Sites.Selected / *.SelectedOperations.Selected permissions, access must be
granted per resource in SharePoint. This tool lets an administrator:

    Select SharePoint Site            (Connect-PnPOnline to the tenant admin centre + the site)
            |
            v
    Select Permission Scope                                  App needs (Entra ID, application permission)
            +---- Site            -> *-PnPEntraIDAppSitePermission      Sites.Selected
            +---- List / Library  -> *-PnPEntraIDAppListPermission      Lists.SelectedOperations.Selected
            +---- Folder          -> *-PnPEntraIDAppListItemPermission  ListItems.SelectedOperations.Selected
            +---- File            -> *-PnPEntraIDAppFilePermission      Files.SelectedOperations.Selected
            +---- List Item       -> *-PnPEntraIDAppListItemPermission  ListItems.SelectedOperations.Selected
            |
            v
    Select Application / Service Principal   (Get-PnPEntraIDServicePrincipal)
            |
            v
    Select Permission Level
            +---- Site:        Read / Write / Manage / FullControl
            +---- Other scope: Read / Write / Owner  / FullControl
            v
    Grant (or update) permission -> read it back with Get-* to verify -> show result
            |
            v
    Return to main menu

There is no dedicated folder cmdlet in PnP, so folders are granted through their underlying list item
(*-PnPEntraIDAppListItemPermission with the folder's list item ID).

.PREREQUISITES
- PowerShell 7.4+ and PnP.PowerShell 3.x  (Install-Module PnP.PowerShell -Scope CurrentUser)
- An Entra ID app registration for PnP interactive login (your "admin" app), with DELEGATED permissions:
      Microsoft Graph : Sites.FullControl.All, Application.Read.All
      SharePoint      : AllSites.FullControl
  -ClientId is required for -Interactive. Create one with Register-PnPEntraIDAppForInteractiveLogin.
- The signed-in user must be a SharePoint Administrator (or Global Administrator).

.PARAMETER ClientId
Client ID of the PnP admin app registration. Defaults to $env:ENTRAID_APP_ID / $env:ENTRAID_CLIENT_ID,
and you are prompted for it if neither is set.

.EXAMPLE
.\F_Sharepoint-Permissions-Manager.ps1 -ClientId 00000000-0000-0000-0000-000000000000
#>

[CmdletBinding()]
param(
    [string]$ClientId = $(if ($env:ENTRAID_APP_ID) { $env:ENTRAID_APP_ID } else { $env:ENTRAID_CLIENT_ID })
)

$ErrorActionPreference = 'Stop'

#region Global state

$Script:ClientId        = $ClientId
$Script:AdminConnection = $null     # PnP connection to https://<tenant>-admin.sharepoint.com
$Script:SiteConnection  = $null     # PnP connection to the selected site
$Script:CurrentUserUpn  = $null

$Script:AppState = [ordered]@{
    SiteUrl     = $null
    SiteTitle   = $null
    Scope       = $null     # Site | List | Folder | File | Item
    List        = $null     # [pscustomobject] Id, Title, RootUrl
    Target      = $null     # [pscustomobject] Id, Path, RelativePath   (folder / file / list item)
    Application = $null     # [pscustomobject] AppId, DisplayName
    Permission  = $null     # Read | Write | Manage | Owner | FullControl
    IsSiteAdmin = $false    # True when THIS script added the current user as temporary site collection admin
}

$Script:ScopeLabels = [ordered]@{
    Site   = 'Site'
    List   = 'List / Document Library'
    Folder = 'Folder'
    File   = 'File (document library)'
    Item   = 'List Item'
}

# PnP cmdlet noun used for each scope: <Verb>-PnPEntraIDApp<Noun>Permission
$Script:ScopeNouns = @{
    Site   = 'Site'
    List   = 'List'
    Folder = 'ListItem'
    File   = 'File'
    Item   = 'ListItem'
}

#endregion

#region Banner

$Script:Banner = @'

░        ░░   ░░░  ░░        ░░       ░░░░      ░░░░░░░░░        ░░       ░░
▒  ▒▒▒▒▒▒▒▒    ▒▒  ▒▒▒▒▒  ▒▒▒▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒  ▒▒▒▒  ▒
▓      ▓▓▓▓  ▓  ▓  ▓▓▓▓▓  ▓▓▓▓▓       ▓▓▓  ▓▓▓▓  ▓▓▓▓▓▓▓▓▓▓▓  ▓▓▓▓▓  ▓▓▓▓  ▓
█  ████████  ██    █████  █████  ███  ███        ███████████  █████  ████  █
█        ██  ███   █████  █████  ████  ██  ████  ████████        ██       ██

░░      ░░░  ░░░░  ░░░      ░░░       ░░░        ░░       ░░░░      ░░░        ░░   ░░░  ░░        ░
▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒▒▒▒  ▒▒▒▒▒    ▒▒  ▒▒▒▒▒  ▒▒▒▒
▓▓      ▓▓▓        ▓▓  ▓▓▓▓  ▓▓       ▓▓▓      ▓▓▓▓       ▓▓▓  ▓▓▓▓  ▓▓▓▓▓  ▓▓▓▓▓  ▓  ▓  ▓▓▓▓▓  ▓▓▓▓
███████  ██  ████  ██        ██  ███  ███  ████████  ████████  ████  █████  █████  ██    █████  ████
██      ███  ████  ██  ████  ██  ████  ██        ██  █████████      ███        ██  ███   █████  ████

░░      ░░░        ░░        ░░        ░░░░░░░░░      ░░░        ░░  ░░░░░░░░        ░░░      ░░░        ░░        ░░       ░░
▒  ▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒▒  ▒▒▒▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒  ▒▒▒▒▒  ▒▒▒▒▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒  ▒
▓▓      ▓▓▓▓▓▓  ▓▓▓▓▓▓▓▓  ▓▓▓▓▓      ▓▓▓▓▓▓▓▓▓▓▓      ▓▓▓      ▓▓▓▓  ▓▓▓▓▓▓▓▓      ▓▓▓▓  ▓▓▓▓▓▓▓▓▓▓▓  ▓▓▓▓▓      ▓▓▓▓  ▓▓▓▓  ▓
███████  █████  ████████  █████  ████████████████████  ██  ████████  ████████  ████████  ████  █████  █████  ████████  ████  █
██      ███        █████  █████        █████████      ███        ██        ██        ███      ██████  █████        ██       ██
'@

#endregion

#region Main

function Initialize-PnPModule {
    <#
        Loads PnP.PowerShell 3.x. A .NET process can only hold ONE PnP.PowerShell assembly, and it can't be
        unloaded - so if an older version (e.g. 2.x) was already used in this PowerShell window, 3.x can't load.
        Returns $true when PnP 3.x is ready.
    #>
    $minimum = [version]'3.0.0'

    $loadedAssembly = [AppDomain]::CurrentDomain.GetAssemblies() |
        Where-Object { $_.GetName().Name -eq 'PnP.PowerShell' } |
        Select-Object -First 1

    if ($loadedAssembly -and $loadedAssembly.GetName().Version -lt $minimum) {
        Write-Host ''
        Write-Host "PnP.PowerShell $($loadedAssembly.GetName().Version) is already loaded in this PowerShell window." -ForegroundColor Red
        Write-Host "This tool needs PnP.PowerShell $minimum or later, and .NET can't load a second version into the same process." -ForegroundColor Red
        Write-Host ''
        Write-Host 'Open a NEW PowerShell 7 window and run the script there (before using any other PnP command).' -ForegroundColor Yellow
        Write-Host 'Tip: uninstall old versions so they are never auto-loaded:' -ForegroundColor DarkGray
        Write-Host '     Uninstall-Module PnP.PowerShell -RequiredVersion <old version>' -ForegroundColor DarkGray
        return $false
    }

    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell | Where-Object Version -ge $minimum)) {
        Write-Host "PnP.PowerShell $minimum or later is not installed." -ForegroundColor Red
        Write-Host 'Install it with: Install-Module PnP.PowerShell -Scope CurrentUser' -ForegroundColor Yellow
        return $false
    }

    Import-Module PnP.PowerShell -MinimumVersion $minimum -ErrorAction Stop
    return $true
}

function Main {

    if (-not (Initialize-PnPModule)) { return }

    $Options = [ordered]@{
        '1' = 'Select SharePoint Site (connect)'
        '2' = 'Add me as temporary Site Collection Admin'
        '3' = 'Select Permission Scope (Site / List / Folder / File / Item)'
        '4' = 'Select Application / Service Principal to grant permission to'
        '5' = 'Select Permission Level'
        '6' = 'Grant Permission (and verify)'
        '7' = 'View existing app permissions on current scope'
        '8' = 'Revoke an app permission on current scope'
        '9' = 'Remove temporary Site Collection Admin'
    }

    while ($true) {

        $Selection = Show-Menu -Title 'SharePoint Application Permission Management' -Options $Options -ShowStatus

        if ($null -eq $Selection) {
            Exit-Tool
            break
        }

        try {
            switch ($Selection) {
                '1' { Select-SharePointSite }
                '2' { if (Assert-SelectedSite) { Add-AdminPermissionToSite } }
                '3' { if (Assert-SelectedSite) { Select-PermissionScope } }
                '4' { if (Assert-SelectedSite) { Resolve-SelectedApplication } }
                '5' { Select-PermissionLevel }
                '6' { Invoke-PermissionGrant }
                '7' { Show-ExistingPermissions }
                '8' { Invoke-PermissionRevoke }
                '9' { if (Assert-SelectedSite) { Remove-AdminPermissionFromSite } }
            }
        }
        catch {
            Write-Host ''
            Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
        }

        Write-Host ''
        Read-Host 'Press Enter to return to main menu' | Out-Null
    }
}

#endregion

#region User interface

function Show-Menu {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        # IDictionary accepts both [hashtable] and [ordered] dictionaries, and keeps insertion order.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Options,

        [switch]$ShowStatus
    )

    while ($true) {

        Clear-Host
        Write-Host $Script:Banner -ForegroundColor Cyan
        Write-Host ''
        Write-Host ('═' * 70) -ForegroundColor DarkCyan
        Write-Host " $Title" -ForegroundColor Yellow
        Write-Host ('═' * 70) -ForegroundColor DarkCyan

        if ($ShowStatus) { Show-Status }

        Write-Host ''
        foreach ($key in $Options.Keys) {
            Write-Host " [$key] $($Options[$key])"
        }
        Write-Host ''
        Write-Host ' [Q] Back / Exit' -ForegroundColor DarkGray
        Write-Host ''

        $selection = (Read-Host 'Select an option').Trim()

        if ($selection -eq 'Q') {
            return $null
        }

        if ($Options.Contains($selection)) {
            return $selection
        }

        Write-Host 'Invalid selection!' -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
}

function Show-Status {
    $s = $Script:AppState

    $scopeText = if ($s.Scope) { $Script:ScopeLabels[$s.Scope] } else { $null }
    $target = switch ($s.Scope) {
        'List'  { $s.List.Title }
        { $_ -in 'Folder', 'File', 'Item' } { "$($s.List.Title) -> $($s.Target.Path)" }
        default { $null }
    }
    $app = if ($s.Application) { "$($s.Application.DisplayName) ($($s.Application.AppId))" } else { $null }

    Write-Host ''
    Write-StatusLine 'Signed in as' $Script:CurrentUserUpn
    Write-StatusLine 'Site'         $(if ($s.SiteUrl) { "$($s.SiteTitle) - $($s.SiteUrl)" })
    Write-StatusLine 'Temp admin'   $(if ($s.IsSiteAdmin) { 'Yes (remember to remove)' })
    Write-StatusLine 'Scope'        $scopeText
    if ($target) { Write-StatusLine 'Target' $target }
    Write-StatusLine 'Application'  $app
    Write-StatusLine 'Permission'   $s.Permission
    Write-Host ('─' * 70) -ForegroundColor DarkCyan
}

function Write-StatusLine {
    param([string]$Label, [string]$Value)
    Write-Host (' {0,-13}: ' -f $Label) -NoNewline -ForegroundColor DarkGray
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Host '<not set>' -ForegroundColor DarkYellow
    }
    else {
        Write-Host $Value -ForegroundColor White
    }
}

function Select-FromList {
    <#
        Generic numbered picker. Returns the selected object, or $null when cancelled.
        Type "/text" to filter the list, "*" to clear the filter.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Items,

        # Scriptblock that turns an item into a display string, e.g. { param($x) $x.Title }
        [Parameter(Mandatory)]
        [scriptblock]$Label,

        [int]$PageSize = 40
    )

    if ($Items.Count -eq 0) {
        Write-Host 'Nothing to select.' -ForegroundColor Yellow
        return $null
    }

    $view = @($Items)

    while ($true) {
        Write-Host ''
        Write-Host " $Title" -ForegroundColor Yellow

        $max = [Math]::Min($view.Count, $PageSize)
        for ($i = 0; $i -lt $max; $i++) {
            Write-Host (' [{0,3}] {1}' -f ($i + 1), (& $Label $view[$i]))
        }
        if ($view.Count -gt $max) {
            Write-Host "   ... $($view.Count - $max) more. Type /text to filter." -ForegroundColor DarkGray
        }
        if ($view.Count -eq 0) {
            Write-Host '   (no matches - type * to clear filter)' -ForegroundColor DarkGray
        }

        $answer = (Read-Host 'Number, /filter, * = clear filter, Q = cancel').Trim()

        if ($answer -eq 'Q' -or $answer -eq '') { return $null }

        if ($answer -eq '*') { $view = @($Items); continue }

        if ($answer.StartsWith('/')) {
            $text = $answer.Substring(1)
            $view = @($Items | Where-Object { (& $Label $_) -like "*$text*" })
            continue
        }

        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $max) {
            return $view[$n - 1]
        }

        Write-Host 'Invalid selection!' -ForegroundColor Red
    }
}

function Read-YesNo {
    param([Parameter(Mandatory)][string]$Prompt)
    while ($true) {
        $a = (Read-Host "$Prompt [Y/N]").Trim()
        if ($a -match '^(y|yes)$') { return $true }
        if ($a -match '^(n|no)$')  { return $false }
    }
}

#endregion

#region Connection

function Get-ClientId {
    while ([string]::IsNullOrWhiteSpace($Script:ClientId)) {
        Write-Host 'PnP.PowerShell needs the Client ID of an Entra ID app registration for interactive login.' -ForegroundColor Green
        $id = (Read-Host 'Enter Client ID (or Q to cancel)').Trim()
        if ($id -eq 'Q') { return $null }
        if ($id -as [guid]) { $Script:ClientId = $id }
        else { Write-Host 'Not a valid GUID.' -ForegroundColor Red }
    }
    return $Script:ClientId
}

function Connect-ToSharePoint {
    <#
        Connects (interactively) to the tenant admin centre and to the selected site.
        Both connections are kept in script variables and passed explicitly with -Connection.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SiteUrl
    )

    $clientId = Get-ClientId
    if (-not $clientId) { return $false }

    $tenant   = ([uri]$SiteUrl).Host.Split('.')[0]          # contoso.sharepoint.com -> contoso
    $adminUrl = "https://$tenant-admin.sharepoint.com"

    if (-not $Script:AdminConnection -or $Script:AdminConnection.Url.TrimEnd('/') -ne $adminUrl) {
        Write-Host "Connecting to $adminUrl ..." -ForegroundColor Green
        $Script:AdminConnection = Connect-PnPOnline -Url $adminUrl -Interactive -ClientId $clientId -ReturnConnection
    }

    Write-Host "Connecting to $SiteUrl ..." -ForegroundColor Green
    $Script:SiteConnection = Connect-PnPOnline -Url $SiteUrl -Interactive -ClientId $clientId -ReturnConnection

    if (-not $Script:CurrentUserUpn) {
        # LoginName is a claims string like "i:0#.f|membership|user@contoso.com"
        $me = (Get-PnPWeb -Includes CurrentUser -Connection $Script:SiteConnection).CurrentUser
        $Script:CurrentUserUpn = ($me.LoginName -split '\|')[-1]
    }

    return $true
}

function Assert-SelectedSite {
    # Makes sure a site is selected and connected. Prompts once if not. Never recurses.
    if ($Script:AppState.SiteUrl -and $Script:SiteConnection) { return $true }

    Write-Host 'No SharePoint site selected.' -ForegroundColor Yellow
    Select-SharePointSite
    return [bool]$Script:AppState.SiteUrl
}

#endregion

#region Temporary site collection admin

function Add-AdminPermissionToSite {
    $url = $Script:AppState.SiteUrl
    $upn = $Script:CurrentUserUpn

    Write-Host "Adding $upn as Site Collection Admin on $url ..." -ForegroundColor Green
    # Set-PnPTenantSite -Owners ADDS site collection admins (it does not replace existing ones).
    Set-PnPTenantSite -Identity $url -Owners $upn -Connection $Script:AdminConnection
    $Script:AppState.IsSiteAdmin = $true
    Write-Host 'Done.' -ForegroundColor Green
}

function Remove-AdminPermissionFromSite {
    $url = $Script:AppState.SiteUrl
    $upn = $Script:CurrentUserUpn

    if (-not $Script:AppState.IsSiteAdmin) {
        if (-not (Read-YesNo "This session did not add you as admin on $url. Remove $upn anyway?")) { return }
    }

    Write-Host "Removing $upn as Site Collection Admin from $url ..." -ForegroundColor Green
    Remove-PnPSiteCollectionAdmin -Owners $upn -Connection $Script:SiteConnection
    $Script:AppState.IsSiteAdmin = $false
    Write-Host 'Done.' -ForegroundColor Green
}

function Exit-Tool {
    if ($Script:AppState.IsSiteAdmin) {
        Write-Host ''
        if (Read-YesNo "You are still a temporary Site Collection Admin on $($Script:AppState.SiteUrl). Remove now?") {
            try { Remove-AdminPermissionFromSite }
            catch { Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red }
        }
    }
    Write-Host 'Goodbye.' -ForegroundColor Green
}

#endregion

#region Discovery / selection

function Select-SharePointSite {
    Write-Host 'SharePoint Site URL format: https://<tenant>.sharepoint.com/sites/<site-name>' -ForegroundColor Green
    $url = (Read-Host 'Enter the URL of the SharePoint site (or Q to cancel)').Trim().TrimEnd('/')

    if ($url -eq 'Q' -or $url -eq '') { return }

    if ($url -notmatch '^https://[a-z0-9-]+\.sharepoint\.com(/(sites|teams)/[^/]+)?$') {
        Write-Host 'That does not look like a SharePoint Online site URL.' -ForegroundColor Red
        return
    }

    # Clean up the temp admin on the previous site before switching.
    if ($Script:AppState.IsSiteAdmin -and $Script:AppState.SiteUrl -ne $url) {
        if (Read-YesNo "You are temporary admin on $($Script:AppState.SiteUrl). Remove before switching?") {
            Remove-AdminPermissionFromSite
        }
        else {
            $Script:AppState.IsSiteAdmin = $false   # can no longer track it after switching
        }
    }

    if (-not (Connect-ToSharePoint -SiteUrl $url)) { return }

    $web = Get-PnPWeb -Connection $Script:SiteConnection

    $Script:AppState.SiteUrl   = $url
    $Script:AppState.SiteTitle = $web.Title

    # Reset selections that depend on the site
    $Script:AppState.Scope      = $null
    $Script:AppState.List       = $null
    $Script:AppState.Target     = $null
    $Script:AppState.Permission = $null

    Write-Host "Selected site: $($web.Title)" -ForegroundColor Green
}

function Select-PermissionScope {
    $keys = @($Script:ScopeLabels.Keys)
    $scopeOptions = [ordered]@{}
    for ($i = 0; $i -lt $keys.Count; $i++) { $scopeOptions["$($i + 1)"] = $Script:ScopeLabels[$keys[$i]] }

    $choice = Show-Menu -Title 'Select Permission Scope' -Options $scopeOptions
    if ($null -eq $choice) { return }

    $scope  = $keys[[int]$choice - 1]
    $list   = $null
    $target = $null

    if ($scope -ne 'Site') {
        # Folders and files only exist in document libraries.
        $list = Get-SelectedLibrary -DocumentLibrariesOnly:($scope -in 'Folder', 'File')
        if (-not $list) { return }

        switch ($scope) {
            'Folder' { $target = Get-SelectedListEntry -List $list -FSObjType 1 -Title "Select Folder in '$($list.Title)'" }
            'File'   { $target = Get-SelectedListEntry -List $list -FSObjType 0 -Title "Select File in '$($list.Title)'" }
            'Item'   { $target = Get-SelectedListEntry -List $list -FSObjType 0 -Title "Select Item in '$($list.Title)'" }
        }
        if ($scope -ne 'List' -and -not $target) { return }
    }

    # Only commit once the full selection succeeded
    $Script:AppState.Scope  = $scope
    $Script:AppState.List   = $list
    $Script:AppState.Target = $target

    # Available permission levels differ per scope - clear an incompatible one.
    if ($Script:AppState.Permission -and $Script:AppState.Permission -notin (Get-AvailablePermissionLevels)) {
        $Script:AppState.Permission = $null
    }

    Write-Host "Scope set to: $($Script:ScopeLabels[$scope])" -ForegroundColor Green
}

function Get-SelectedLibrary {
    param([switch]$DocumentLibrariesOnly)

    Write-Host 'Loading lists ...' -ForegroundColor DarkGray
    $lists = @(Get-PnPList -Includes RootFolder -Connection $Script:SiteConnection | Where-Object {
            -not $_.Hidden -and (-not $DocumentLibrariesOnly -or $_.BaseTemplate -eq 101)
        } | Sort-Object Title)

    $picked = Select-FromList -Title 'Select List / Library' -Items $lists -Label {
        param($l) '{0}  ({1} items)' -f $l.Title, $l.ItemCount
    }
    if (-not $picked) { return $null }

    return [pscustomobject]@{
        Id      = $picked.Id.ToString()
        Title   = $picked.Title
        RootUrl = $picked.RootFolder.ServerRelativeUrl.TrimEnd('/')
    }
}

function Get-SelectedListEntry {
    <#
        Lists folders (FSObjType 1) or files / items (FSObjType 0) in a list and lets the user pick one.
        Returns Id (list item ID), Path (server-relative) and RelativePath (relative to the library root,
        used by the *-PnPEntraIDAppFilePermission cmdlets).
    #>
    param(
        [Parameter(Mandatory)]$List,
        [Parameter(Mandatory)][int]$FSObjType,
        [Parameter(Mandatory)][string]$Title
    )

    Write-Host 'Loading items (large lists can take a while) ...' -ForegroundColor DarkGray
    $entries = @(Get-PnPListItem -List $List.Id -PageSize 2000 -Fields 'FileRef', 'Title', 'FSObjType' -Connection $Script:SiteConnection |
        Where-Object { [int]$_.FieldValues['FSObjType'] -eq $FSObjType } |
        ForEach-Object {
            $fileRef = [string]$_.FieldValues['FileRef']
            $relative = if ($fileRef.StartsWith("$($List.RootUrl)/", [StringComparison]::OrdinalIgnoreCase)) {
                $fileRef.Substring($List.RootUrl.Length + 1)
            }
            else { $fileRef }

            [pscustomobject]@{
                Id           = [int]$_.Id
                Path         = if ($fileRef) { $fileRef } else { $_.FieldValues['Title'] }
                RelativePath = $relative
            }
        } | Sort-Object Path)

    Select-FromList -Title $Title -Items $entries -Label { param($e) "[$($e.Id)] $($e.Path)" }
}

function Resolve-SelectedApplication {
    $q = (Read-Host 'Enter the Application (client) ID or the start of the display name (Q to cancel)').Trim()
    if ($q -eq 'Q' -or $q -eq '') { return }

    $candidates = @()
    try {
        if ($q -as [guid]) {
            $candidates = @(Get-PnPEntraIDServicePrincipal -AppId $q -Connection $Script:AdminConnection)
        }
        else {
            $escaped = $q.Replace("'", "''")
            $candidates = @(Get-PnPEntraIDServicePrincipal -Filter "startswith(displayName,'$escaped')" -Connection $Script:AdminConnection)
        }
    }
    catch {
        Write-Host "Lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    $candidates = @($candidates | Where-Object { $_ })
    if ($candidates.Count -eq 0) {
        Write-Host "No service principal found for '$q'." -ForegroundColor Yellow
        return
    }

    $sp = if ($candidates.Count -eq 1) { $candidates[0] } else {
        Select-FromList -Title 'Select Application' -Items $candidates -Label { param($p) "$($p.DisplayName)  ($($p.AppId))" }
    }
    if (-not $sp) { return }

    $Script:AppState.Application = [pscustomobject]@{ AppId = [string]$sp.AppId; DisplayName = $sp.DisplayName }
    Write-Host "Selected application: $($sp.DisplayName) ($($sp.AppId))" -ForegroundColor Green
}

function Get-AvailablePermissionLevels {
    if ($Script:AppState.Scope -eq 'Site') { @('Read', 'Write', 'Manage', 'FullControl') }
    else { @('Read', 'Write', 'Owner', 'FullControl') }
}

function Select-PermissionLevel {
    if (-not $Script:AppState.Scope) {
        Write-Host 'Select a permission scope first (option 3).' -ForegroundColor Yellow
        return
    }

    $levels  = Get-AvailablePermissionLevels
    $options = [ordered]@{}
    for ($i = 0; $i -lt $levels.Count; $i++) { $options["$($i + 1)"] = $levels[$i] }

    $choice = Show-Menu -Title "Select Permission Level ($($Script:ScopeLabels[$Script:AppState.Scope]))" -Options $options
    if ($null -eq $choice) { return }

    $Script:AppState.Permission = $options[$choice]
    Write-Host "Permission level set to: $($Script:AppState.Permission)" -ForegroundColor Green
}

#endregion

#region Grant / verify / revoke  (all through *-PnPEntraIDApp<Scope>Permission cmdlets)

function Invoke-ScopedPermissionCmdlet {
    <#
        Calls <Verb>-PnPEntraIDApp<Site|List|ListItem|File>Permission for the current scope, adding the
        scope-specific target parameters (-List, -ListItem, -Path) automatically.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Get', 'Grant', 'Set', 'Revoke')]
        [string]$Verb,

        [hashtable]$Parameters = @{}
    )

    $s       = $Script:AppState
    $noun    = $Script:ScopeNouns[$s.Scope]
    $cmdlet  = "$Verb-PnPEntraIDApp$($noun)Permission"

    $params = @{
        Site       = $s.SiteUrl
        Connection = $Script:SiteConnection
    }
    switch ($s.Scope) {
        'List'   { $params.List = $s.List.Id }
        'Folder' { $params.List = $s.List.Id; $params.ListItem = $s.Target.Id }
        'Item'   { $params.List = $s.List.Id; $params.ListItem = $s.Target.Id }
        'File'   { $params.List = $s.List.Id; $params.Path = $s.Target.RelativePath }
    }
    foreach ($k in $Parameters.Keys) { $params[$k] = $Parameters[$k] }

    & $cmdlet @params
}

function Get-AppPermissionEntries {
    <#
        Returns the app permissions on the current scope as uniform objects:
        Id, Roles, AppId, AppName. Optionally filtered to a single AppId.
    #>
    param([string]$AppId)

    $extra = @{}
    if ($AppId) { $extra.AppIdentity = $AppId }

    # PnP throws when nothing matches -AppIdentity, so treat an error as "no permissions".
    $raw = @(try { Invoke-ScopedPermissionCmdlet -Verb Get -Parameters $extra } catch { })

    return @($raw | Where-Object { $_ } | ForEach-Object {
            $p = $_
            foreach ($a in @($p.Apps)) {
                if (-not $a) { continue }
                if ($AppId -and $a.Id -ne $AppId) { continue }
                [pscustomobject]@{ Id = $p.Id; Roles = (@($p.Roles) -join ', '); AppId = $a.Id; AppName = $a.DisplayName }
            }
        })
}

function Test-ReadyForGrant {
    $s = $Script:AppState
    $missing = @()
    if (-not $s.SiteUrl)     { $missing += 'Site (1)' }
    if (-not $s.Scope)       { $missing += 'Scope (3)' }
    if (-not $s.Application) { $missing += 'Application (4)' }
    if (-not $s.Permission)  { $missing += 'Permission level (5)' }
    if ($missing) {
        Write-Host "Missing selections: $($missing -join ', ')" -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Invoke-PermissionGrant {
    if (-not (Test-ReadyForGrant)) { return }

    $s     = $Script:AppState
    $app   = $s.Application
    $level = $s.Permission

    Write-Host ''
    Write-Host 'About to grant:' -ForegroundColor Yellow
    Write-Host "  Application : $($app.DisplayName) ($($app.AppId))"
    Write-Host "  Site        : $($s.SiteUrl)"
    Write-Host "  Scope       : $($Script:ScopeLabels[$s.Scope])"
    if ($s.List)   { Write-Host "  List        : $($s.List.Title)" }
    if ($s.Target) { Write-Host "  Target      : $($s.Target.Path)" }
    Write-Host "  Permission  : $level"
    Write-Host ''
    if (-not (Read-YesNo 'Proceed?')) { return }

    $existing = @(Get-AppPermissionEntries -AppId $app.AppId)

    if ($existing.Count -gt 0) {
        Write-Host "App already has '$($existing[0].Roles)' - updating to '$level' ..." -ForegroundColor Green
        Invoke-ScopedPermissionCmdlet -Verb Set -Parameters @{ PermissionId = $existing[0].Id; Permissions = $level } | Out-Null
    }
    else {
        Write-Host "Granting $($Script:ScopeLabels[$s.Scope]) permission ..." -ForegroundColor Green
        $grant = @{ AppId = $app.AppId; DisplayName = $app.DisplayName; Permissions = $level }
        try {
            Invoke-ScopedPermissionCmdlet -Verb Grant -Parameters $grant | Out-Null
        }
        catch {
            # Fallback if the service rejects a high role on create: grant Read, then elevate with Set.
            if ($level -notin 'Manage', 'Owner', 'FullControl') { throw }
            Write-Host "Direct grant of '$level' failed ($($_.Exception.Message)). Granting Read, then elevating ..." -ForegroundColor DarkYellow
            $grant.Permissions = 'Read'
            $perm = Invoke-ScopedPermissionCmdlet -Verb Grant -Parameters $grant
            Invoke-ScopedPermissionCmdlet -Verb Set -Parameters @{ PermissionId = $perm.Id; Permissions = $level } | Out-Null
        }
    }

    # Verify by reading it back
    Write-Host 'Verifying ...' -ForegroundColor DarkGray
    $after = @(Get-AppPermissionEntries -AppId $app.AppId)
    if ($after.Count -gt 0) {
        Write-Host 'SUCCESS - permission is in place:' -ForegroundColor Green
        $after | Format-Table AppName, AppId, Roles, Id -AutoSize | Out-Host
    }
    else {
        Write-Host 'WARNING - the grant call returned, but the permission could not be read back.' -ForegroundColor Yellow
    }
}

function Test-ScopeSelected {
    if ($Script:AppState.SiteUrl -and $Script:AppState.Scope) { return $true }
    Write-Host 'Select a site (1) and scope (3) first.' -ForegroundColor Yellow
    return $false
}

function Show-ExistingPermissions {
    if (-not (Test-ScopeSelected)) { return }

    $entries = @(Get-AppPermissionEntries)
    if ($entries.Count -eq 0) {
        Write-Host 'No application permissions found on this scope.' -ForegroundColor Yellow
        return
    }
    $entries | Format-Table AppName, AppId, Roles, Id -AutoSize | Out-Host
}

function Invoke-PermissionRevoke {
    if (-not (Test-ScopeSelected)) { return }

    $entries = @(Get-AppPermissionEntries)
    $picked  = Select-FromList -Title 'Select permission to revoke' -Items $entries -Label {
        param($e) "$($e.AppName) ($($e.AppId)) - $($e.Roles)"
    }
    if (-not $picked) { return }

    if (-not (Read-YesNo "Revoke '$($picked.Roles)' for $($picked.AppName)?")) { return }

    Invoke-ScopedPermissionCmdlet -Verb Revoke -Parameters @{ PermissionId = $picked.Id; Force = $true }
    Write-Host 'Permission revoked.' -ForegroundColor Green
}

#endregion

# Start
Clear-Host
Main
