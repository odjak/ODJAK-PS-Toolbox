# Import the Lithnet MIIS Automation module
Import-Module LithnetMIISAutomation

# Connect to the MIM Synchronization Service
$syncServer = "localhost"  # Replace with your MIM Sync server name if different
Connect-MIISServer -Server $syncServer

# Function to update user attributes in the Metaverse
function Update-MetaverseUser {
    param (
        [string]$userId,
        [hashtable]$attributes
    )

    # Find the user in the Metaverse
    $user = Get-MVObject -ObjectType person -AttributeName accountName -AttributeValue $userId
    if ($null -eq $user) {
        Write-Output "User $userId not found in the Metaverse."
        return
    }

    # Update the user's attributes
    foreach ($key in $attributes.Keys) {
        Set-MVObjectAttribute -MVObjectID $user.ID -AttributeName $key -AttributeValue $attributes[$key]
    }

    # Commit the changes
    Commit-MVObject -MVObjectID $user.ID
    Write-Output "User $userId has been updated in the Metaverse."
}

# Example usage
$userId = "user-id-to-update"
$attributes = @{
    "displayName" = "New Display Name"
    "telephoneNumber" = "123-456-7890"
}

Update-MetaverseUser -userId $userId -attributes $attributes
