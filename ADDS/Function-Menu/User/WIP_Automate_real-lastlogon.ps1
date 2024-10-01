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

# Whitelist of allowed users
$Whitelist = @("john.doe@example.com", "jane.doe@example.com")

# Function to check if a user is in the whitelist
function Is-UserWhitelisted {
    param (
        [string]$UserPrincipalName
    )

    if ($Whitelist -contains $UserPrincipalName) {
        Write-Log "User $UserPrincipalName is whitelisted" "Info"
        return $true
    } else {
        Write-Log "User $UserPrincipalName is not whitelisted" "Warning"
        return $false
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

    if (-not (Is-UserWhitelisted -UserPrincipalName $UserPrincipalName)) {
        Write-Log "Skipping user $UserPrincipalName as they are not whitelisted" "Warning"
        return
    }

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
$UserName           = "john.doe"
$UserPrincipalName  = "john.doe@example.com"

Get-RealLastLogon -UserName $UserName -UserPrincipalName $UserPrincipalName
# - Example Output: 
#  [INFO] User 


# - Logging using PSWriteOutput:
# - Example:
# PSWriteOutput -Level INFO -Message "This is an informational message"
# PSWriteOutput -Level WARNING -Message "This is a warning message"
# PSWriteOutput -Level ERROR -Message "This is an error message"


# - Logging using Write-Log:
# - Example:
# Write-Log -Message "This is an informational message" -Level "Info"

# - Logging using poshlogging:
# - Example:
# Log-Info "This is an informational message"
# Log-Warning "This is a warning message"
# Log-Error "This is an error message"
# Log-Debug "This is a debug message"
# Log-Verbose "This is a verbose message"
# Log-Trace "This is a trace message"
# Log-Output "This is an output message"

# -Example output: 
# [INFO] This is an informational message
# Example customizing the output:
# [INFO] [2021-01-01 12:00:00] This is an informational message
# [WARNING] [2021-01-01 12:00:00] This is a warning message
# [ERROR] [2021-01-01 12:00:00] This is an error message
# [DEBUG] [2021-01-01 12:00:00] This is a debug message

# Customizing the output is done by modifying the Log-Output function in the poshlogging module.
# The function can be found in the poshlogging.psm1 file in the module directory.
# The function can be modified to include additional information in the output message, such as timestamps or other metadata.

# - Example with full function included for mobility:
# function Log-Output {
#     param (
#         [string]$Message,
#         [string]$Level = "INFO"
#     )
#
#     $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
#     Write-Host "[$Level] [$timestamp] $Message"
# }
#
# Log-Output "This is an informational message" "INFO"
# Log-Output "This is a warning message" "WARNING"
# Log-Output "This is an error message" "ERROR"
# Log-Output "This is a debug message" "DEBUG"
# Log-Output "This is a verbose message" "VERBOSE"
# Log-Output "This is a trace message" "TRACE"
# Log-Output "This is an output message" "OUTPUT"
# - Example output:
# [INFO] [2021-01-01 12:00:00] This is an informational message
# [WARNING] [2021-01-01 12:00:00] This is a warning message
# [ERROR] [2021-01-01 12:00:00] This is an error message
# [DEBUG] [2021-01-01 12:00:00] This is a debug message
# [VERBOSE] [2021-01-01 12:00:00] This is a verbose message
# [TRACE] [2021-01-01 12:00:00] This is a trace message
# [OUTPUT] [2021-01-01 12:00:00] This is an output message
# - Example with full function included for mobility:
