# This script copies the entire content of a OneDrive to the subfolder named "Archived colleagues" of another OneDrive.
# Its main purpose is to archive a user's data as he leaves the company.

# Prefer TLS 1.2 to connect.
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

# Connect to sharepoint service.
$credential             = Get-Credential
$admin                  = $credential.UserName
$sharepoint_admin_url   = "https://tenantName-admin.sharepoint.com"

# Connect to sharepoint service.
Connect-SPOService -Url $sharepoint_admin_url -Credential $credential

# Connect to source site.
Connect-PNPOnline -Url $source_site -Credential $credential

$source_site_id         = Read-Host "Please enter the source site ID (=last part of OneDrive URL, e.g. 'first_last_domain_com')."
$target_site_id         = Read-Host "Please enter the target site ID.(=last part of OneDrive URL, e.g. 'first_last_domain_com')."

$source_site_root       = "/personal/" + $source_site_id
$source_site            = "https://manuchar-my.sharepoint.com" + $source_site_root
$source_path            = $source_site + "/Documents"
$target_site_root       = "/personal/" + $target_site_id
$target_site            = "https://manuchar-my.sharepoint.com" + $target_site_root
$target_path            = $target_site + "/Documents"
$date                   = Get-Date -Format u

# Add admin as site collection admin.
$throwaway              = Set-SPOUser -Site $source_site -LoginName $admin -IsSiteCollectionAdmin $true
$throwaway              = Set-SPOUser -Site $target_site -LoginName $admin -IsSiteCollectionAdmin $true
$items                  = Get-PNPListItem -List Documents -PageSize 1000

# Get ordered folder list from source site.
$folders                = $items | Where-Object {$_.FileSystemObjectType -contains "Folder"}
$folder_paths           = $folders | ForEach-Object { $_.fieldvalues.FileRef }
$ordered_folder_paths   = $folder_paths | sort { $_.length }

# Get files list from source site$
$files                  = $items  | Where-Object {$_.FileSystemObjectType -contains "File"}

# Connect to target site
Connect-PNPOnline -Url $target_site -Credential $credential

# Create target folder on target site.
	Add-PnPFolder -Folder "Documents" -Name "Archived colleagues" -ErrorAction SilentlyContinue
    $user_identifier    = $date + " " + $source_site_id
    $user_identifier    = $user_identifier.Replace(" ","-").Replace(":","-")
	Add-PnPFolder -Folder "Documents\Archived colleagues\" -Name $user_identifier
	$target_folder      = "Documents\Archived colleagues\" + $user_identifier
	Add-PnPFolder -Folder $target_folder -Name Documents

# Create folders on target site.
Write-Host "Creating folders..."
ForEach ($folder in $ordered_folder_paths) {
	$original_parent    = Split-Path -Path $folder
    $new_parent         = $original_parent.replace($source_site_root.replace("/","\"), $target_folder)
	$name               = Split-Path -Path $folder -Leaf

	Write-Host("Creating " + $new_parent + "\" + $name)
	Add-PnPFolder -Folder $new_parent -Name $name
}

# Copy files.
Write-Host "Copying files..."
$errors                 = ""
ForEach ($file in $files) {
	$source_url         = $file.fieldvalues.FileRef
    $naked_url          = $file.fieldvalues.FileRef.replace($source_site_root,"")
    $target_url_temp    = ($target_folder.Replace('\','/') + $naked_url)
    $target_url         = Split-Path -Path $target_url_temp

	Write-Host ("Copying " + $naked_url)
	$throwaway          = Copy-PnPFile -SourceUrl $source_url -TargetUrl $target_url -OverwriteIfAlreadyExists -Force -ErrorVariable new_error
    $errors             = $errors + $new_error
}

Write-Host "Errors:"
Write-Host $errors

# Remove admin as site collection admin.
$throwaway              = Set-SPOUser -Site $source_site -LoginName $admin -IsSiteCollectionAdmin $false
$throwaway              = Set-SPOUser -Site $target_site -LoginName $admin -IsSiteCollectionAdmin $false

