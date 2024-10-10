param (
    [String]$configFilePath = "./config.json",
    [String]$buildScriptsFolder = "./ImageBuildScripts",
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
#Upload to Build scripts to the scripts container       #
#########################################################

#Get the storage account name from the config file
$storageAccountName = $configJson.storageName
$scriptContainer = $configJson.containerIBScripts

#Check that the storage account container exists
Write-Output "Checking for Storage Account '$storageAccountName' in '$rgName'"
$stContainerContext = Get-AzStorageAccount -ResourceGroupName $rgName -Name $storageAccountName | Get-AzStorageContainer -Name $scriptContainer -ErrorAction SilentlyContinue
if (-Not $stContainerContext) {
    Write-Error "ERROR - Repo Storage Account / Container not found ($storageAccountName / $scriptContainer)"
    exit 1
}

#Upload the example content
Write-Output "Uploading the Example Content to the Storage Account"

#Check to see if the scripts folder exists locally
if (-not (Test-Path $buildScriptsFolder)) {
    Write-Error "ERROR: Could not find example package folder.  Check path and try again ($buildScriptsFolder)"
    exit 1
 }

# Compress all of the Powershell PS1 files into a single zip file
$zipFileName = $configJson.zipFileName
$compressError = $null
$compress = @{
    Path = "$buildScriptsFolder\\*.ps1"
    CompressionLevel = 'Fastest'
    DestinationPath = "$($env:TEMP)\\$zipFileName"
    Force = $true
}
Compress-Archive @compress -ErrorVariable compressError
if ($compressError) {
    Write-Error "ERROR: There was an error compressing the build scripts.  Check the error"
    Write-Output " - Error: $($compressError[0].Exception.Message)"
    exit 1
}

#Upload the compressed scripts files to the script folder
Set-AzStorageBlobContent -File "$($env:TEMP)\\$zipFileName" -Container $scriptContainer -Blob $zipFileName -Context $stContainerContext.Context

Write-Output "All files uploaded successfully"