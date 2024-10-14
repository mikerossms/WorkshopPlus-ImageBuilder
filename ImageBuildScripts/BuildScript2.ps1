<#
.SYNOPSIS
    Installs the 7Zip package from the storage account

.DESCRIPTION


.NOTES
    This is an example only.  It is not a production script.  It is just to show how to install a package using chocolatey

.INPUTS
    storageAccount - The name of the storage account that contains the software repository
    sasToken - The SAS token used to access the software repository
    container - The name of the container in the storage account that contains the software repository
    buildScriptsFolder - The folder that contains the common library functions (defaults to C:\BuildScripts)
    runLocally - If set to true, the script will run locally using the library functions relative to the folder structure in the GitHub repo

#>

# Define parameters for the script
param (
    [Parameter(Mandatory=$true)]
    [string]$storageAccount,

    [Parameter(Mandatory=$true)]
    [string]$sasToken,

    [string]$container = 'software',

    [string]$buildScriptsFolder = 'C:\BuildScripts',

    [Bool]$runLocally = $false
)

$InformationPreference = 'continue'

<#
    .SYNOPSIS
    Take a Azure Storage account, SAS token and container name and return a context object that can be used to access the repo

    .INPUTS
    storageRepoAccount - The name of the Azure Storage Account
    storageSASToken - The SAS token for the Azure Storage Account
    storageRepoContainer - The name of the Azure Storage Container

    .OUTPUTS
    An Azure Storage Container object

    .EXAMPLE
    Get-RepoContext -storageRepoAccount "swrepo" -storageSASToken "<sasToken>" -storageRepoContainer "repository"
#>
function Get-RepoContext {
    param (
        [Parameter(Mandatory=$true)]
        [String]$storageRepoAccount,
        [Parameter(Mandatory=$true)]
        [String]$storageSASToken,
        [Parameter(Mandatory=$true)]
        [String]$storageRepoContainer
    )

    #Check to see if the AZ module is already installed
    Write-Output "Checking for AZ Module (required)" 
    if (-Not (Get-Module -Name Az.Storage -ListAvailable)) {
        Write-Output "AZ Module is not installed - Installing"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Install-Module -name Az.Storage -Scope CurrentUser -Repository PSGallery -Force
    }

    Write-Output "Getting Repo Context"

    $stContext = New-AzStorageContext -StorageAccountName $storageRepoAccount -SasToken $storageSASToken

    if (-Not $stContext) {
        Write-Warning "Provided SAS token failed - Trying to generate a new SAS token"
        $StartTime = Get-Date
        $EndTime = $StartTime.AddHours(3.0)

        $storageContext = New-AzStorageContext -StorageAccountName $storageRepoAccount  #User context
        $storageSASToken = New-AzStorageContainerSASToken -Name $storageRepoContainer -Permission "rdl" -Context $storageContext -StartTime $StartTime -ExpiryTime $EndTime
        $stContext = New-AzStorageContext -StorageAccountName $storageRepoAccount -SasToken $storageSASToken
    }

    if (-Not $stContext) {
        Write-Warning "Provided SAS token failed - trying user context"
        $stContext = New-AzStorageContext -StorageAccountName $storageRepoAccount  #User context
    }

    if (-Not $stContext) {
        Write-Error "FATAL: Could not get the storage account context for Repo share"
        exit 1
    }

    #Return the storage account context and the container for the software repo
    $repoContext = @{
        "stContext" = $stContext
        "stRepoContainer" = $storageRepoContainer
    }

    if ($stContext) {
        Write-Output "Successfully got the storage account context for Repo share: $storageRepoAccount/$storageRepoContainer"
    }

    return $repoContext
}

<#
    .SYNOPSIS
    Using a repo context object, download a file from the repo to the C:\BuildScripts\Software (default) folder#

    .INPUTS
    repoContext - The context object returned by Get-RepoContext
    blobPath - The "path" to the file in the container e.g. software\7zip\7z1900-x64.msi
    localPath - The local path to download the file to (default is C:\BuildScripts\Software)

    .OUTPUTS
    A object that contains various parameters about the downlaoded file including whether of not the file was successfully downloaded

    .EXAMPLE
    Get-FileFromRepo -repoContext $repoContext -blobPath "software\7zip\7z1900-x64.msi"
    Get-FileFromRepo -repoContext $repoContext -blobPath "software\7zip\7z1900-x64.msi" -localPath "C:\OtherLocation"
#>
function Get-FileFromRepo {
    param (
        [Parameter(Mandatory=$true)]
        [Object]$repoContext,
        [Parameter(Mandatory=$true)]
        [String]$blobPath,
        [String]$localPath = "C:\BuildScripts\Software"
    )

    $downloadSuccess = $false

    Write-Output "Setting up transfer of fime from repo: $blobPath"

    $stContext = $repoContext.stContext
    $stContainer = $repoContext.stRepoContainer

    #Check if the C:\BuildScripts\Software folder exists
    if (-not (Test-Path $localPath)) {
        Write-Output "Creating $localPath folder"
        New-Item -ItemType Directory -Path $localPath | Out-Null
        #Check if it has been created
        if (-not (Test-Path $localPath)) {
            Write-Error "Could not create $localPath folder"
            exit 1
        }
    }

    #Get the file name from a file path
    $filename = $blobPath.Split("\")[-1]

    $localFileName = "$($localPath)\$($filename)"

    Write-Output "Downloading file '$filename' from repo to folder '$localPath'"

    #Download file from the repo to the $localPath folder
    Get-AzStorageBlobContent -Context $stContext -Container $stContainer -Blob $blobPath -Destination $localFileName

    #TEst if the file was successfully downloaded
    $downloadSuccess = "none"
    if (-Not (Test-Path $localFileName)) {
        Write-Error "FATAL: Could not download file $blobPath from repo"
        $downloadSuccess =  $false

    } else {
        $checksum = (Get-FileHash -Path $localFileName -Algorithm MD5).Hash
        Write-Output "File downloaded successfully to: $localFileName"
        Write-Output " - From: $blobPath"
        Write-Output " - To: $localFileName"
        Write-Output " - Checksum: $checksum"
        $downloadSuccess = $true
    }

    $filedata = @{
        filename = [string]$filename
        filePath = [string]$localFileName
        blobPath = [string]$blobPath
        downloadSuccess = [Bool]$downloadSuccess
        fileChecksum = $checksum
    }

    #Could expand this to check the above checksum against an unmutable file checksum stored in a secure location to validate the file if required

    return $filedata
}

# DOWNLOAD and INSTALL
$repoContext = Get-RepoContext -storageRepoAccount $storageAccount -storageSASToken $sasToken -storageRepoContainer $container

##Download and install 7zip
$filedata = Get-FileFromRepo -repoContext $repoContext -blobPath '7z2408-x64.msi'
$filename = $filedata.filename

if (-Not $filedata.downloadSuccess) {
    Write-Error "Error getting MSI file from repo: $repoPath"
    return $false
} else {
    Write-Output "Successfully retrieved $filename from Repo"
}

$installParams = "/quiet /norestart"
$msiFile = "C:\BuildScripts\Software\$($filename)"
Write-Output "RUN: msiexec.exe /i $msiFile $installParams"

$msiProcess = Start-Process "msiexec.exe" -ArgumentList "/I $filename $installParams" -PassThru -NoNewWindow -Wait
if ($msiProcess.ExitCode -ne 0) {
    Write-Error "Error installing MSI file $msiFile"
    return $false
}

#Add more here