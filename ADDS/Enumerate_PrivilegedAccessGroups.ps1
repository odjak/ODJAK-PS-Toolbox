# - Script status: Need debug and verify

# Import necessary modules
Import-Module ActiveDirectory
Import-Module PSHTML

# Define the output paths
$reportPath = "C:\Reports\PrivilegedAccessGroups.html"
$hashPath = "C:\Reports\PrivilegedAccessGroupsHash.txt"

# Define privileged access groups
$privilegedGroups = @(
    "Domain Admins",
    "Enterprise Admins",
    "Schema Admins",
    "Administrators",
    "Account Operators",
    "Backup Operators",
    "Server Operators",
    "Print Operators"
)

# Define domains to check
$domains = @("domain1.com", "domain2.com")

# Recursive function to get group members
function Get-GroupMembers {
    param (
        [string]$GroupName,
        [string]$Domain
    )
    $members = Get-ADGroupMember -Identity $GroupName -Server $Domain -Recursive
    return $members
}

# Create HTML report
$report = New-PSHTML -Title "Privileged Access Groups Report" -Author "Your Name" -CSSUri "https://maxcdn.bootstrapcdn.com/bootstrap/4.0.0/css/bootstrap.min.css"

foreach ($domain in $domains) {
    $report += New-PSHTMLTab -Title $domain -Content {
        foreach ($group in $privilegedGroups) {
            $members = Get-GroupMembers -GroupName $group -Domain $domain
            New-PSHTMLSection -Title "$group Members" -Content {
                New-PSHTMLTable -DataTable $members -Properties Name, ObjectClass, DistinguishedName
            }
        }
    }
}

# Save the report
$report | Out-File -FilePath $reportPath

# Generate hash of the report
$hash = Get-FileHash -Path $reportPath -Algorithm SHA256
$hash.Hash | Out-File -FilePath $hashPath

# Output paths for verification
Write-Output "Report saved to: $reportPath"
Write-Output "Hash saved to: $hashPath"
