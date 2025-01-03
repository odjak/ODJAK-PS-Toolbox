function New-ADUserFromCSV {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$CSVpath,
        [switch]$WhatIf
    )

    begin {
        # Import necessary modules
        Import-Module ActiveDirectory -ErrorAction Stop
        Import-Module PoshLog -ErrorAction Stop

        # Initialize the logger
        $log = Get-Logger -Name "ADUserCreation"

        # Log the start of the process
        Write-InfoLog "Starting user creation process" -Logger $log
    }

    process {
        ForEach ($user in (Import-Csv -Path $CSVpath)) {
            # Create the samAccountName and userPrincipalName
            $samAccountName     = Get-SamAccountName -givenName $user.givenName -surName $user.surName
            $userPrincipalName  = $samAccountName + $domain
            
            # Set Display Name
            $displayName = $user.givenName.Trim() + " " + $user.surname.Trim()
            
            # Make sure that user doesn't already exist
            if (Get-ADUser -Filter {UserPrincipalName -eq $userPrincipalName} -ErrorAction SilentlyContinue) {
                Write-Host "User $($displayName) already exists" -ForegroundColor Yellow
                Write-InfoLog "User $($displayName) already exists" -Logger $log
                continue
            }

            # Get Email address
            $emailAddress = Get-EmailAddress -givenName $user.givenName -surName $user.surName
            
            # Create all the user properties in a hashtable
            $newUser = @{
                AccountPassWord         = (ConvertTo-SecureString -AsPlainText $password -force)
                ChangePasswordAtLogon   = $true
                City                    = $user.city
                Company                 = $user.company
                Country                 = $user.country
                Department              = $user.department
                Description             = $user.description
                DisplayName             = $displayName
                EmailAddress            = $emailAddress
                Enabled                 = $enabled
                GivenName               = $user.givenName.Trim()
                Manager                 = if ($user.manager) {Get-Manager -name $user.manager} else {$null}
                Mobile                  = $user.mobile
                Name                    = $displayName
                Office                  = $user.office
                OfficePhone             = $user.phone
                Organization            = $user.organization
                Path                    = $path 
                PostalCode              = $user.postalcode
                SamAccountName          = $samAccountName
                StreetAddress           = $user.streetAddress
                Surname                 = $user.surname.Trim()
                Title                   = $user.title
                UserPrincipalName       = $userPrincipalName
            }

            # Create new user with WhatIf support
            try {
                if ($WhatIf) {
                    New-ADUser @newUser -WhatIf
                } else {
                    New-ADUser @newUser
                    Write-Host "- $displayName account is created" -ForegroundColor Green
                    Write-InfoLog "User $($displayName) created" -Logger $log
                }
            }
            catch {
                Write-ErrorLog "Unable to create new account for $displayName" -Logger $log
                Write-ErrorLog "Error - $($_.Exception.Message)" -Logger $log
            }
        }
    }

    end {
        # Log the completion of the process
        Write-Host "User creation process completed." -ForegroundColor Cyan
        Write-InfoLog "User creation process completed." -Logger $log

        # Remove imported modules if necessary
        Remove-Module ActiveDirectory -ErrorAction SilentlyContinue
        Remove-Module PoshLog -ErrorAction SilentlyContinue
    }
}

# Example usage
# New-ADUserFromCSV -CSVpath "path\to\your\csvfile.csv" -WhatIf