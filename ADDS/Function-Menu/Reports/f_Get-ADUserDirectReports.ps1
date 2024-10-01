Function Get-DirectReport {
<#
.SYNOPSIS
    This script will get a user's direct reports recursively from ActiveDirectory unless specified with the NoRecurse parameter.
    It also uses the user's EmployeeID attribute as a way to exclude service accounts and/or non standard accounts that are in the reporting structure.

.DESCRIPTION
    This script will get a user's direct reports recursively from ActiveDirectory unless specified with the NoRecurse parameter.
    It also uses the user's EmployeeID attribute as a way to exclude service accounts and/or non standard accounts that are in the reporting structure.

.LINK
    https://thesysadminchannel.com/get-direct-reports-in-active-directory-using-powershell-recursive -   
  
.PARAMETER SamAccountName
    Specify the samaccountname (username) to see their direct reports.
  
.PARAMETER NoRecurse
    Using this option will not drill down further than one level.
  
.EXAMPLE
    Get-DirectReport username
  
.EXAMPLE
    Get-DirectReport -SamAccountName username -NoRecurse
  
.EXAMPLE
    "username" | Get-DirectReport

.NOTES
    Requires -Module ActiveDirectory
    Version: 1.0
    DateCreated: 2020-Jan-28
#>
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(
            Mandatory                       = $false,
            ValueFromPipeline               = $true,
            ValueFromPipelineByPropertyName = $true
        )]
        [string]  $SamAccountName,
         [switch]  $NoRecurse
    )
 
    BEGIN {
        if(-not (Get-Module -Name ActiveDirectory -ListAvailable)) {
            Write-Host "This script requires the ActiveDirectory module to be installed. Please install the module and try again." -ForegroundColor Red
            # wait for press any key to continue
            break
        }
        
    }
 
    PROCESS {
        # - Getting the user's direct reports and their information from Active Directory.
        $UserAccount = Get-ADUser $SamAccountName -Properties DirectReports, DisplayName
        $UserAccount | select -ExpandProperty DirectReports | ForEach-Object {
            $User = Get-ADUser $_ -Properties DirectReports, DisplayName, Title, EmployeeID
            
            # - If the user has an EmployeeID, then we will include them in the output.
            if ($null -ne $User.EmployeeID) {
                if (-not $NoRecurse) {
                    Get-DirectReport $User.SamAccountName
                }
                [PSCustomObject]@{
                    SamAccountName     = $User.SamAccountName
                    UserPrincipalName  = $User.UserPrincipalName
                    DisplayName        = $User.DisplayName
                    Manager            = $UserAccount.DisplayName
                }
            }
            # - If the user does not have an EmployeeID, then we will exclude them from the output.
            else {
                Write-InfoLog "User $($User.SamAccountName) does not have an EmployeeID. Excluding from the output." -ForegroundColor Yellow
            }
        }
    }
 
    END {
        # - Wrapping up the script returning the results and clearing the variables.
        return $User | Select-Object SamAccountName, UserPrincipalName, DisplayName, Manager | Format-Table -AutoSize # returning the results before clearing the variables.
        $UserAccount = $null
        $User = $null
        
    }
 
}