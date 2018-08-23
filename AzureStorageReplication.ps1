


# Function to log verbose messages
function verboseMsg {

    param ($verboseMsg)
    $verboseMsg = ((Get-Date).ToString()) + (" - $verboseMsg")
    Write-Verbose $verboseMsg

}
# Set Variables 
# The following variables are required to be set in Azure Automation.
$AzureRMPrimaryResourceGroupName = Get-AutomationVariable -Name 'AzureRMPrimaryResourceGroupName'
$PrimarySite = Get-AutomationVariable -Name 'StoragePrimarySite'
$SecondarySites = Get-AutomationVariable -Name 'StorageSecondarySites' | ConvertFrom-Json

# Set Preferences
$ErrorActionPreference = "Stop"
$VerbosePreference = "SilentlyContinue"

# Create Connection
$Conn = Get-AutomationConnection -Name AzureRunAsConnection 
Add-AzureRMAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint

$VerbosePreference = "Continue"

#Get Access Key for Primary Site
$verboseMsg = "Getting Access Key for Primary Site: $PrimarySite"
verboseMsg $verboseMsg
$AzureRMPrimaryKey = Get-AzureRmStorageAccountKey -Name $PrimarySite -ResourceGroupName $AzureRMPrimaryResourceGroupName

# Create Storage Context Primary Site
$verboseMsg = "Creating Storage Context for Primary Site: $PrimarySite"
verboseMsg $verboseMsg
$AzureRMPrimaryCntx = New-AzureStorageContext -StorageAccountName $PrimarySite -StorageAccountKey $AzureRMPrimaryKey.Key1

# Get Source Storage Containers
$verboseMsg = "Getting Source Storage Containers in $PrimarySite"
verboseMsg $verboseMsg
$AzureRMPrimaryContainers = Get-AzureStorageContainer -Context $AzureRMPrimaryCntx

# Loop through Secondary Sites and replicate Blobs (if applicable)

foreach ($SecondarySite in $SecondarySites) {

    # Get Access Key for Secondary Site
    $verboseMsg = ("Getting Access Key for Secondary Site:") + ($SecondarySite.StorageName)
    verboseMsg $verboseMsg
    $AzureRMSecondaryKey = Get-AzureRmStorageAccountKey -Name $SecondarySite.StorageName -ResourceGroupName $SecondarySite.ResourceGroupName

    # Get Storage Context for Secondary Site
    $verboseMsg = ("Creating Storage Context for Secondary Site:") + ($SecondarySite.StorageName)
    verboseMsg $verboseMsg
    $AzureRMSecondaryCntx = New-AzureStorageContext -StorageAccountName $SecondarySite.StorageName -StorageAccountKey $AzureRMSecondaryKey.Key1

    # Get Secondary Site Storage Containers
    $verboseMsg = "Getting Source Storage Containers in $SecondarySite"
    verboseMsg $verboseMsg
    $AzureRMSecondaryContainers = Get-AzureStorageContainer -Context $AzureRMSecondaryCntx

    # Remove Containers in Secondary Site if they do not exist on Primary Site

    foreach ($secContainer in $AzureRMSecondaryContainers) {

        $primCont = Get-AzureStorageContainer -Name $SecContainer.Name -Context $AzureRMPrimaryCntx -ErrorAction SilentlyContinue

        If (!$primCont) {

            $verboseMsg = ("Deleting Container: ") + $SecContainer.Name + (" in ") + ($SecondarySite)
            verboseMsg $verboseMsg
            Remove-AzureStorageContainer -Name $SecContainer.Name -Context $AzureRMSecondaryCntx -Force

        }

    }

    foreach ($container in $AzureRMPrimaryContainers) {

        $secondaryCont = Get-AzureStorageContainer -Name $container.Name -Context $AzureRMSecondaryCntx -ErrorAction SilentlyContinue

        # Create container on secondary site if it does not exist

        if (!$secondaryCont) {

            $secondaryCont = New-AzureStorageContainer -Context $AzureRMSecondaryCntx -Name $container.name
            $verboseMsg = ("Creating container:") + ($container.name)
            verboseMsg -verboseMsg $verboseMsg

        }

        # Copy all blobs over to the other container(s) if newer
        $primaryblobs = Get-AzureStorageBlob -Context $AzureRMPrimaryCntx  -Container $container.Name
        foreach ($blob in $primaryblobs) {

            $verboseMsg = ("Checking ") + $blob.Name
            verboseMsg -verboseMsg $verboseMsg
            $copyblob = Get-AzureStorageBlob -Context $AzureRMSecondaryCntx -Container $container.Name -Blob $blob.Name -ErrorAction SilentlyContinue

            if (!$copyblob -or $blob.LastModified -gt $copyblob.LastModified) {

                $verboseMsg = ($blob.Name) + (" is newer! Copying over to secondary sites")
                verboseMsg -verboseMsg $verboseMsg

                $copyblob = Start-AzureStorageBlobCopy -SrcBlob $blob.Name -SrcContainer $container.Name `
                    -Context $AzureRMPrimaryCntx -DestContainer $secondaryCont.Name `
                    -DestBlob $blob.Name -DestContext $AzureRMSecondaryCntx -Force

                # Get status of copy
                $status = $copyblob | Get-AzureStorageBlobCopyState

                While ($status.Status -eq "Pending") {
                    $status = $copyblob | Get-AzureStorageBlobCopyState
                    Start-Sleep 10
                }

                $verboseMsg = ("Successfully copied blob") + ($copyblob.Name)

            }
            # If the secondary site has files that are not in the primary site. Delete it.
            $secondaryblobs = Get-AzureStorageBlob -Context $AzureRMSecondaryCntx -Container $container.Name
            foreach ($sblob in $secondaryblobs) {

                $verboseMsg = ("Checking to see if the following blob needs to be removed: ") + $sblob.Name
                verboseMsg -verboseMsg $verboseMsg

                $deleteblob = Get-AzureStorageBlob -Context $AzureRMPrimaryCntx -Container $container.Name -Blob $sblob.Name -ErrorAction SilentlyContinue
                if (!$deleteblob) {
                
                    $verboseMsg = ("Removing the following file as it is not in the primary site: ") + $sblob.Name
                    verboseMsg -verboseMsg $verboseMsg

                    $deleteblob = Remove-AzureStorageBlob -Blob $sblob.Name -Container $container.Name -Context $AzureRMSecondaryCntx -Force
                } 
                else {
                    $verboseMsg = ("The following file does not need to be removed: ") + $sblob.Name
                    verboseMsg -verboseMsg $verboseMsg                
                }


            }
        }
    }

}

