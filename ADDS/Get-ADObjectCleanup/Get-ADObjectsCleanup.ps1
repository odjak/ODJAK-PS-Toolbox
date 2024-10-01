
function Get-ADGroupWithoutMembers{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SearchBase
    )
    <#
    .SYNOPSIS
    Get all empty groups in a specific OU.
    .DESCRIPTION
    This function will return all empty groups in a specific OU.
    .PARAMETER SearchBase
    The OU to search for empty groups.
    .EXAMPLE
    Get-ADGroupWithoutMembers -SearchBase 'OU=My Groups,DC=contoso,DC=com'
    This will return all empty groups in the 'My Groups' OU.
    .NOTES
    Part of a series of functions to govern and manage life cycle of groups, users and computers in Active Directory.
    #>

    $AllGroups = Get-ADGroup -Filter * -SearchBase $SearchBase
    $EmptyGroups = @()
    foreach($Group in $AllGroups){
        $Members = Get-ADGroupMember -Identity $Group -Recursive
        if($Members.Count -eq 0){
            $EmptyGroups += $Group
        }
    }
    return $EmptyGroups
}

Get-ADInactiveUsers{

}

Get-ADInactiveComputers{

}

Get-ADExpiredAccounts{


}

Get-ADSiteTombstones{
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SearchBase
    )
    <#
    .SYNOPSIS
    Get all tombstoned objects in a specific site.
    .DESCRIPTION
    This function will return all tombstoned objects in a specific site.
    .PARAMETER SearchBase
    The site to search for tombstoned objects.
    .EXAMPLE
    Get-ADSiteTombstones -SearchBase 'CN=My Site,CN=Sites,DC=contoso,DC=com'
    This will return all tombstoned objects in the 'My Site' site.
    .NOTES
    Part of a series of functions to govern and manage life cycle of groups, users and computers in Active Directory.
    #>
    
    # - First get all AD Sites - Then get all tombstoned objects in each site
    $ADSites = Get-ADObject -Filter {ObjectClass -eq 'site'} -SearchBase 'CN=Sites,DC=contoso,DC=com'
    $AllTombstones = @()
    foreach($Site in $ADSites){
        $SiteTombstones = Get-ADObject -Filter {isDeleted -eq $true} -SearchBase $Site.DistinguishedName
        $AllTombstones += $SiteTombstones
    }
    return $AllTombstones
}

function main{
    # - Where all the functions come together and ultimately is displayed in cool ASCII table.
    # - Intention is to put this together into something bigger auditing AD environment and Entra.
    # - This is just a sample code. You can customize it as per your requirements.
    # - You can also add more functions to this script to get more information about your AD environment.
    # - For example, you can add functions to get inactive users, inactive computers, expired accounts etc.

    # - Get all inactive users in a specific OU.
    $EmptyGroups = Get-ADGroupWithoutMembers -SearchBase 'OU=My Groups,DC=contoso,DC=com'
    $EmptyGroups | ForEach-Object {
        Write-Host $_.Name
    }

    # - Get all tombstoned objects in a specific site.
    $Tombstones = Get-ADSiteTombstones -SearchBase 'CN=My Site,CN=Sites,DC=contoso,DC=com'
    $Tombstones | ForEach-Object {
        Write-Host $_.Name
    }

    # - Create a nice summary report of all the above functions in a beautiful ascii table.
    $asciiTable = @("
+----------------------+----------------------+----------------------+
| Empty Groups         | Tombstoned Objects   | Inactive Users       |
+----------------------+----------------------+----------------------+ 
| $($EmptyGroups.Count)                     | $($Tombstones.Count)                   | $($InactiveUsers.Count)                   |
+----------------------+----------------------+----------------------+
")

$rownumber = 0
foreach($row in $asciiTable.Split("`n")) {
    Write-Host $asciitable[$rownumber] -ForegroundColor Black -BackgroundColor Green
        $rownumber++
    } | format-table -AutoSize
}