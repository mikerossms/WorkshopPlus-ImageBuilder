param (
    [String]$configFilePath = "./config.json",
    [Bool]$dologin = $false,
    [String]$bicepFolder = "./Bicep"
)

$VerbosePreference = "Continue"

# This script is for deploying the image specific components via Bicep - each image may have a different setup, different operating system etc. so this script is likely to be different for each image
# this script does not modify the base image in any way.  this is done in the next stage when you build the image - this only deploys the Azure infra required to enable the image to be built

#TODO: build the Bicep and update this script

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

# Check if the resource group exists
Write-Verbose "Checking if the resource group $rgName exists..."
if (-not (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue)) {
    Write-Verbose "Resource group $rgName does not exist. Creating..."
    $location = $configJson.location
    $rgParams = @{
        Name = $rgName
        Location = $location
    }
    New-AzResourceGroup @rgParams
    Write-Output "Resource group $rgName created successfully."
} else {
    Write-Verbose "Resource group $rgName already exists."
}

#Get the current time in hhmmss format
$currentTime = Get-Date -Format "HHmmss"

###############################################
#Deploy the image specific componetns via Bicep
###############################################
# deploy the image Components
Write-Verbose "Deploying main GalleryDefinitions.bicep ($PSScriptRoot)"
$deployOutput = New-AzResourceGroupDeployment -Name "$currentTime-Deployment" `
    -ResourceGroupName $rgName `
    -TemplateFile "$($PSScriptRoot)/$($bicepFolder)/GalleryDefinitions.bicep" `
    -Verbose `
    -TemplateParameterObject @{
        storageAccountName = $configJson.storageName
        computeGalName = $configJson.computeGalleryName
        location = $configJson.location
        containerIBScripts = $configJson.containerIBScripts
        containerIBPackages = $configJson.containerIBPackages
        umiName = $configJson.umiName
        ibBuildScriptZipName = $configJson.zipFileName
    }


if (-not $deployOutput) {
    Write-Error "ERROR: Failed to deploy $($PSScriptRoot)/$($bicepFolder)/GalleryDefinitions.bicep"
    exit 1
} else {
    #finished
    Write-Output "Finished GalleryDefinitions Bicep Deployment"
}

