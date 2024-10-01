# Import necessary modules
Import-Module ActiveDirectory
Import-Module Microsoft.Graph

# Logging function with color output and log tags
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

# Function to get the last logon time for an on-premises AD user
function Get-OnPremLastLogon {
    param (
        [string]$UserName
    )

    try {
        $user = Get-ADUser -Identity $UserName -Properties LastLogonTimestamp
        if ($user) {
            $lastLogon = [DateTime]::FromFileTime($user.LastLogonTimestamp)
            Write-Log "On-premises last logon for user $UserName: $lastLogon" "Info"
            return $lastLogon
        } else {
            throw "User '$UserName' not found in on-premises AD."
        }
    } catch {
        Write-Log "Error retrieving on-premises last logon for user $UserName. Error: $_" "Error"
        return $null
    }
}

# Function to get the last logon time for an Azure AD user using Microsoft Graph SDK
function Get-AzureADLastLogon {
    param (
        [string]$UserPrincipalName
    )

    try {
        $user = Get-MgUser -UserId $UserPrincipalName
        if ($user) {
            $signIns = Get-MgUserSignInLog -UserId $UserPrincipalName -Top 1 -Sort "createdDateTime desc"
            if ($signIns) {
                $lastLogon = $signIns[0].CreatedDateTime
                Write-Log "Azure AD last logon for user $UserPrincipalName: $lastLogon" "Info"
                return $lastLogon
            } else {
                Write-Log "No sign-in logs found for user $UserPrincipalName" "Warning"
                return $null
            }
        } else {
            throw "User '$UserPrincipalName' not found in Azure AD."
        }
    } catch {
        Write-Log "Error retrieving Azure AD last logon for user $UserPrincipalName. Error: $_" "Error"
        return $null
    }
}

# Function to compare last logon times and determine the "real" last logon
function Get-RealLastLogon {
    param (
        [string]$UserName,
        [string]$UserPrincipalName
    )

    $onPremLastLogon = Get-OnPremLastLogon -UserName $UserName
    $azureADLastLogon = Get-AzureADLastLogon -UserPrincipalName $UserPrincipalName

    if ($onPremLastLogon -and $azureADLastLogon) {
        if ($onPremLastLogon -gt $azureADLastLogon) {
            Write-Log "Real last logon for user $UserName (on-premises): $onPremLastLogon" "Info"
            return $onPremLastLogon
        } else {
            Write-Log "Real last logon for user $UserName (Azure AD): $azureADLastLogon" "Info"
            return $azureADLastLogon
        }
    } elseif ($onPremLastLogon) {
        Write-Log "Real last logon for user $UserName (on-premises only): $onPremLastLogon" "Info"
        return $onPremLastLogon
    } elseif ($azureADLastLogon) {
        Write-Log "Real last logon for user $UserName (Azure AD only): $azureADLastLogon" "Info"
        return $azureADLastLogon
    } else {
        Write-Log "No logon information available for user $UserName" "Warning"
        return $null
    }
}

# Example usage of the function
$UserName = "john.doe"
$UserPrincipalName = "john.doe@example.com"

Get-RealLastLogon -UserName $UserName -UserPrincipalName $UserPrincipalName