<#
.SYNOPSIS
    Uploads example packages to a specified storage account.

.DESCRIPTION
    This script uploads example packages to a specified storage account. It reads configuration settings from a JSON file, 
    optionally performs a login, and uploads the packages to the designated container in the storage account.

.PARAMETER configFilePath
    The path to the configuration file. Default is "./config.json".

.PARAMETER dologin
    Flag to determine if login is required. Default is $false.

.PARAMETER examplePackageFolder
    The path to the folder containing the example packages. Default is "./ExamplePackages".

.EXAMPLE
    .\3-UploadExamplePackages.ps1 -configFilePath "./config.json" -dologin $true examplePackageFolder "./ExamplePackages"

.NOTES
    This is an example only.  It is not a production script.  Microsoft accepts no liability for the content or use of this script.

#>

param (
    [String]$configFilePath = "./config.json",
    [String]$examplePackageFolder = "./ExamplePackages",
    [Bool]$dologin = $false
)

$VerbosePreference = "Continue"

###############################
# Read in the configuration   #
###############################

#Check if the config.json file exists
Write-Verbose "Checking if the config.json file exists..."
if (-not (Test-Path $configFilePath)) {
    Write-Error "The config.json file does not exist ($configFilePath)."
    exit 1
}

#Read the contents of the config.json file
Write-Verbose "Reading the contents of the config.json file..."
try {
    $configJson = Get-Content $configFilePath -Raw | ConvertFrom-Json
} catch {
    Write-Error "The config.json file is invalid."
    exit 1
}

Write-Output "Config loaded successfully"

#Set the subscription variable
$subName = $configJson.subscription
Write-Verbose "Subscription: $subName"

#Get the RG name from the config file
$rgName = $configJson.rgDeployName

###########################################
# Do login and check correct subscription #
###########################################

#Login to azure (if required) - if you have already done this once, then it is unlikley you will need to do it again for the remainer of the session
if ($dologin) {
    Write-Verbose "Log in to Azure using an account with permission to create Resource Groups and Assign Permissions"
    Connect-AzAccount -SubscriptionName $subName
} else {
    Write-Warning "Login skipped"
}

#check that the subscription name we are connected to matches the one we want and change it to the right one if not
Write-Verbose "Checking we are connected to the correct subscription (context)"
if ((Get-AzContext).Subscription.Name -ne $subName) {
    #they dont match so try and change the context
    Write-Warning "Changing context to subscription: $subName"
    $context = Set-AzContext -SubscriptionName $subName

    if ($context.Subscription.Name -ne $subName) {
        Write-Error "ERROR: Cannot change to subscription: $subName"
        exit 1
    }

    Write-Verbose "Changed context to subscription: $subName"
}


#########################################################
#Upload to the Software container in the storage account#
#########################################################

#Get the storage account name from the config file
$storageAccountName = $configJson.storageName
$softwareContainer = $configJson.containerIBPackages

#Check that the storage account container exists
Write-Output "Checking for Storage Account '$storageAccountName' in '$rgName'"
$stContainerContext = Get-AzStorageAccount -ResourceGroupName $rgName -Name $storageAccountName | Get-AzStorageContainer -Name $softwareContainer -ErrorAction SilentlyContinue
if (-Not $stContainerContext) {
    Write-Error "ERROR - Repo Storage Account / Container not found ($storageAccountName / $softwareContainer)"
    exit 1
}

#Upload the example content
Write-Output "Uploading the Example Content to the Storage Account"

#Check to see if the example package folder exists locally
if (-not (Test-Path $examplePackageFolder)) {
    Write-Error "ERROR: Could not find example package folder.  Check path and try again ($examplePackageFolder)"
    exit 1
 }


# Get a list of all files in the example package folder
$files = Get-ChildItem -Path $examplePackageFolder -File

# Upload each file to the storage account container
foreach ($file in $files) {
    $filePath = $file.FullName
    $blobName = $file.Name

    Write-Verbose "Uploading $blobName to $softwareContainer in $storageAccountName"
    Set-AzStorageBlobContent -File $filePath -Container $softwareContainer -Blob $blobName -Context $stContainerContext.Context
}

Write-Output "All files uploaded successfully"