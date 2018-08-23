# Variables to parameterize 
$storSAS = 'storagekeyhere'
$StorageAccountName = 'storageaccountnamehere'
$ContainerName = 'containernamehere'
$ClientDestination = "C:\temp\blob"

$VerbosePreference = "Continue"


# Create Context
$clientContext = New-AzureStorageContext -SasToken $storSAS -StorageAccountName $StorageAccountName
$blobs = Get-AzureStorageBlob -Container $ContainerName -Context $clientContext


# Copy New Data

foreach ($blob in $blobs) {

    $blobpath = ($ClientDestination + "\") + ($blob.name.Replace('/', '\'))
    $existingblob = Test-Path -LiteralPath $blobpath

    if ($existingblob) {

        $existingfile = Get-ChildItem $blobpath | Where-Object {$_.Length -match $blob.Length}

        if ($existingfile) {

            Write-Verbose "$blobpath already exists and is same length as the source"

        }

        Else {

            Write-Verbose "Replacing File: $blobpath"
            Get-AzureStorageBlobContent -Blob $blob.Name -Container $containerName `
            -Context $clientContext -Destination $ClientDestination -Force

        }

    }

    Else {

        Write-Verbose "Copying New File: $blobpath"
        Get-AzureStorageBlobContent -Blob $blob.Name -Container $containerName `
        -Context $clientContext -Destination $ClientDestination -Force | Out-Null

    }

}


# Perform Cleanup on Files
Write-Verbose "Performing Cleanup on Files"

$allFiles = Get-ChildItem -LiteralPath $ClientDestination -Recurse -File

foreach ($clientfile in $allFiles) {

    $clientfilepath = ($clientfile.FullName.TrimStart($ClientDestination)).Replace('\', '/')

    If ($blobs.Name -notcontains $clientfilepath) {

        # Remove File

        Write-Verbose "$clientfile not on source. Deleting file."
        Remove-Item -Path $clientfile.FullName -Force | Out-Null

    }
}


# Perform Cleanup of empty Directories

Write-Verbose "Performing Cleanup of Empty Directories"

$allDirs = Get-ChildItem -Directory -Path $ClientDestination 

foreach ($alldir in $allDirs) {

    $contentcheck = Get-ChildItem -Path $alldir.FullName -File

    If (!$contentcheck) {

        $verboseMsg = ("Removing Directory: ") + ($alldir.FullName)
        Write-Verbose $verboseMsg
        Remove-Item -Path $alldir.FullName -Force -Confirm:$false -Recurse

    }


}
