<#
.SYNOPSIS
    Deploys image-specific components via Bicep.

.DESCRIPTION
    This script is used to deploy the image-specific components via Bicep. Each image may have a different setup, different operating system, etc., so this script is likely to be different for each image.
    Note that this script DOES NOT start the build of the image. It only deploys the gallery, definitions, and build spec. To start the build, you must either do this in the next script (6-BuildImage-xx), via direct PowerShell/CLI, or via the portal.

.PARAMETER configFilePath
    The path to the configuration file. Default is "./config.json".

.PARAMETER dologin
    Flag to determine if login is required. Default is $false.

.PARAMETER bicepFolder
    The path to the Bicep folder. Default is "./Bicep".

.PARAMETER buildTimeout
    Timeout for the build process in minutes. Default is 180 minutes.

.EXAMPLE
    .\5-ImageBuilderDefinitions.ps1 -configFilePath "./config.json" -dologin $true -bicepFolder "./Bicep" -buildTimeout 180

.NOTES
    This is an example only.  It is not a production script.  Microsoft accepts no liability for the content or use of this script.
#>

param (
    [String]$configFilePath = "./config.json", # Path to the configuration file
    [Bool]$dologin = $false,                   # Flag to determine if login is required
    [String]$bicepFolder = "./Bicep",          # Path to the Bicep folder
    [Int]$buildTimeout = 180                   # Timeout for the build process in minutes
)


$VerbosePreference = "Continue"

# This script is for deploying the image specific components via Bicep - each image may have a different setup, different operating system etc. so this script is likely to be different for each image
# this script DOES NOT start the build of the image - this only deployed the gallery, definitions and build spec.  
# to start the build you must either do this in the next script (6-BuildImage-xx), via direct powershell/cli or via the portal

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

###CLEANUP OLD Templates###
#This is an optional step, but if you dont you will ned up with a new template each time you run the script
$templates = Get-AzImageBuilderTemplate -ResourceGroupName $rgName

#Loop through the templates and delete any that are not the current one - runs in the background
foreach ($template in $templates) {
    Write-Output " - Deleting old template $($template.Name)"
    Remove-AzImageBuilderTemplate -ResourceGroupName $rgName -Name $template.Name
}

# Check that the az.imagebuilder powershell module is installed
Write-Verbose "Checking if the Az.ImageBuilder module is installed..."
if (-not (Get-Module -Name Az.ImageBuilder -ListAvailable)) {
    Write-Output "Installing the Az.ImageBuilder module..."
    try {
        Install-Module -Name Az.ImageBuilder -Force -AllowClobber -ErrorAction Stop
    } catch {
        Write-Warning "Unable to install Az.ImageBuilder module.  Trying with CurrentUser scope"
        try {
            Install-Module -Name Az.ImageBuilder -Force -scope CurrentUser -AllowClobber -ErrorAction Stop
        } catch {
            Write-Error "ERROR: Failed to install Az.ImageBuilder module - cannot continue."
            exit 1
        }
    }
}


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

