# - Import the Active Directory module
Import-Module ActiveDirectory

# - Logging function with color output and log tags   
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "Info"
    )

    switch ($Level) {
        "Info" {
            Write-Host "[INFO] $Message" -ForegroundColor Green
        }
        "Warning" {
            Write-Host "[WARNING] $Message" -ForegroundColor Yellow
        }
        "Error" {
            Write-Host "[ERROR] $Message" -ForegroundColor Red
        }
        default {
            Write-Host "[UNKNOWN] $Message" -ForegroundColor White
        }
    }
}


# . Check if the logger is actually enabled, otherwise write to the console only
if (Confirm-LoggerIsEnabled) {
    Write-InfoLog $Title
} else {
    Write-Host $Title
}



# Function to delegate permissions to a group on an OU and its child OUs
function Set-ADPermissions {
    param (
        [string]$OU,
        [string]$GroupName
    )

    try {
        # Retrieve the distinguished name of the group
        $Group = Get-ADGroup -Identity $GroupName
        if (-not $Group) {
            throw "Group '$GroupName' not found."
        }
        $GroupDN = $Group.DistinguishedName

        Write-Log "Retrieved group DN: $GroupDN" "Info"

        # Define the permissions to be delegated
        $permissions = @(
            ([System.DirectoryServices.ActiveDirectoryAccessRule]::new(
                [System.Security.Principal.SecurityIdentifier]::new($Group.SID),
                [System.DirectoryServices.ActiveDirectoryRights]::WriteProperty,
                [System.Security.AccessControl.AccessControlType]::Allow
            )),
            ([System.DirectoryServices.ActiveDirectoryAccessRule]::new(
                [System.Security.Principal.SecurityIdentifier]::new($Group.SID),
                [System.DirectoryServices.ActiveDirectoryRights]::Delete,
                [System.Security.AccessControl.AccessControlType]::Allow
            )),
            ([System.DirectoryServices.ActiveDirectoryAccessRule]::new(
                [System.Security.Principal.SecurityIdentifier]::new($Group.SID),
                [System.DirectoryServices.ActiveDirectoryRights]::CreateChild,
                [System.Security.AccessControl.AccessControlType]::Allow
            )),
            ([System.DirectoryServices.ActiveDirectoryAccessRule]::new(
                [System.Security.Principal.SecurityIdentifier]::new($Group.SID),
                [System.DirectoryServices.ActiveDirectoryRights]::DeleteChild,
                [System.Security.AccessControl.AccessControlType]::Allow
            ))
        )

        Write-Log "Permissions defined" "Info"

        # Function to apply permissions to a specific OU
        function Apply-Permissions {
            param (
                [string]$OU,
                [array]$permissions
            )

            try {
                # Get the security descriptor of the OU
                $OUACL = Get-ACL "AD:$OU"
                Write-Log "Retrieved ACL for OU: $OU" "Info"

                # Apply each permission rule to the OU
                foreach ($permission in $permissions) {
                    $OUACL.AddAccessRule($permission)
                }

                # Set the modified security descriptor back to the OU
                Set-ACL -Path "AD:$OU" -AclObject $OUACL
                Write-Log "Applied permissions to OU: $OU" "Info"
            } catch {
                Write-Log "Failed to apply permissions to OU: $OU. Error: $_" "Error"
                throw $_
            }
        }

        # Apply permissions to the specified OU
        Apply-Permissions -OU $OU -permissions $permissions

        # Retrieve all child OUs of the specified OU
        $ChildOUs = Get-ADOrganizationalUnit -Filter * -SearchBase $OU

        # Apply permissions to each child OU
        foreach ($ChildOU in $ChildOUs) {
            Apply-Permissions -OU $ChildOU.DistinguishedName -permissions $permissions
        }

        Write-Log "Permissions delegated to group '$GroupName' on OU '$OU' and its child OUs." "Info"
    } catch {
        Write-Log "Failed to delegate permissions. Error: $_" "Error"
    }
}

# Example usage of the function
$OU = "OU=MyOU,DC=example,DC=com"
$GroupName = "MyGroup"

Set-ADPermissions -OU $OU -GroupName $GroupName
