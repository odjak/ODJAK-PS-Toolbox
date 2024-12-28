#
# Script to migrate onedrive data from one account to another in the same tenant (To begin with).
# Most modules out there are built for use with MSOnline and Sharepoint Online Management Shell, but this script uses primarily the Graph API.
# - > Status     - This script needs debug - testing - > finalize
# - > Testing    - This script is not yet tested.
# - > Created by - Robin Johansson 
# - > Created on - 2024-04-29

function Move-OneDriveUser2User {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$sourceuser,
        [Parameter(Mandatory = $true)]
        [string]$targetuser
    )
    begin{
        # Check if the required modules are installed
        $requiredmodules    = @('Microsoft.Graph', 
                                'Microsoft.Graph.Authentication',
                                'Microsoft.Graph.Core',
                                'Microsoft.Graph.Users',
                                'Microsoft.Graph.Files',
                                'Microsoft.Graph.Groups',
                                'Microsoft.Graph.Groups',
                                'Microsoft.Graph.Mail',
                                'PoshLog'
                                )

        $missingmodules     = @()

        foreach ($module in $requiredmodules) {
            if (-not(Get-Module -Name $module -ListAvailable)) {
                $missingmodules += $module
            }
        }

        if ($missingmodules.Count -gt 0) {
            Write-Host "The following modules are missing: $($missingmodules -join ', ')"
            Write-Host "Please install the missing modules before running this script."
            Exit
        }

        # Import the required modules
        import-module Microsoft.Graph
        Import-module Poshlog

        # Initiate the PoshLog
        $timestamp      = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $logname        = "move-useronedrivetouseronedrive_$timestamp.log"
        $logpath        = ".\logs\" + $logname 

        New-Log -Name "Move-Onedrive-Data" -Path $logpath -Level INFO -Append
        Add-SinkConsole -Name "Move-Onedrive-Data" -Level INFO
        Add-SinkFile -Name "Move-Onedrive-Data" -Path $logpath -Level INFO

        # Authenticate to the Graph API
        $tenantid       = "tenantname.onmicrosoft.com"
        $tenantcred     = Get-Credential -Message "Enter your tenant admin credentials"

        Connect-MgGraph -TenantId $tenantid -Credential $tenantcred -Scopes "User.Read.All", "Files.ReadWrite.All", "Sites.Read.All", "Group.ReadWrite.All"

        # Get the source and destination users
        $sourceuserobj      = Get-MgUser -UserId $sourceuser
        $targetuserobj      = Get-MgUser -UserId $targetuser
        $sourceuserid       = $sourceuserobj.id
        $targetuserid       = $targetuserobj.id

        Write-InfoLog -Message "Initiation of function is done and processing of the Source user files into the target user files is in progress." 
    }
    process {
        Write-InfoLog "Fetching the source user files and preparing to copy them to the target user's onedrive."
        $sourceonedriveitems = Get-MgUserOnedriveItem -UserId $sourceuserid -ItemType File -Recurse
        
        # Copy the source user's onedrive items to the target user's onedrive
        foreach ($item in $sourceonedriveitems) {
            $itempath       = $item.parentReference.path + "/" + $item.name
            $itemcontent    = Get-MgUserOnedriveItemContent -UserId $sourceuserid -ItemId $item.id
            try {
                Set-MgUserOnedriveItemContent -UserId $targetuserid -ItemId $item.id -Content $itemcontent
                Write-InfoLog "Copied item:" + $itempath "to: " + $targetuser
            } 
            catch {
                Write-ErrorLog "Failed to copy item: " $itempath + " to: " + $targetuser "Error: " $_.Exception.Message
            }
        }
    }
    end {
        # Finishing up the script
        Write-InfoLog "Processing of the Source user files into the target user files is completed."
        # Disconnect sessions and remove modules
        Disconnect-MgGraph
        Remove-Module Microsoft.Graph
        Remove-Module PoshLog
    }
}
