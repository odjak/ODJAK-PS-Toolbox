function get-nestedgroups {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipelineByPropertyName, Mandatory = $True)]
        [String[]]$Group,
        [Parameter()]
        [String]$Server = (Get-ADReplicationsite | Get-ADDomainController -SiteName $_.name -Discover -ErrorAction SilentlyContinue).name
    )
 begin { }
 process {
    foreach ($item in $Group) {
        $ADGrp = Get-ADGroup -Identity $item -Server $Server
        $QueryResult = Get-ADGroup -LDAPFilter "(&(objectCategory=group)(memberof=$($ADGrp.DistinguishedName)))" -Properties canonicalname -Server $Server
        if ( $null -ne $QueryResult) {
            foreach ($grp in $QueryResult) {
                $GrpLookup = Get-ADGroup -Identity "$($Grp.DistinguishedName)" -Properties Members, CanonicalName -Server $Server
                $NestedGroupInfo = [PSCustomObject]@{
                    'ParentGroup' = $item
                    'NestedGroup' = $Grp.Name
                    'NestedGroupMemberCount' = $GrpLookup.Members.count
                    'ObjectClass' = $Grp.ObjectClass
                    'ObjectPath' = $GrpLookup.CanonicalName
                    'DistinguishedName' = $GrpLookup.DistinguishedName
                } #end PSCustomObject

                $NestedGroupInfo
            } #end of foreach inside if statement
        }
        else {
            Write-Information "There are no nested groups inside $item" -InformationAction Continue
        } #end if/else

        # checking for groups of nested groups
        foreach ($NestedGrp in $QueryResult) {
            $NestedADGrp = Get-ADGroup -Identity $NestedGrp -Server $Server
            $NestedQueryResult = Get-ADGroup -LDAPFilter "(&(objectCategory=group)(memberof=$($NestedADGrp.DistinguishedName)))" -Properties canonicalname -Server $Server

            If ($null -ne $NestedQueryResult) {
            foreach ($SubGrp in $NestedQueryResult) {
                $SubGrpLookup = Get-ADGroup -Identity "$($SubGrp.DistinguishedName)" -Properties Members, CanonicalName -Server $Server
            }
            $SubNestedGroupInfo = [PSCustomObject]@{
                'ParentGroup' = $NestedADGrp.Name
                'NestedGroup' = $SubGrp.Name
                'NestedGroupMemberCount' = $SubGrpLookup.Members.count
                'ObjectClass' = $SubGrp.ObjectClass
                'ObjectPath' = $SubGrpLookup.CanonicalName
                'DistinguishedName' = $SubGrpLookup.DistinguishedName
            } #end PSCustomObject
$SubNestedGroupInfo
            } #end of foreach inside if statement
        } #end parent foreach
    } #end process block

end {}
} #end function

}
 