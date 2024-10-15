<#
.SYNOPSIS
    Deploys base components for the image builder using Bicep.

.DESCRIPTION
    This script deploys the base components required for the image builder using Bicep. It reads configuration settings 
    from a JSON file, optionally performs a login, and sets up the necessary environment for the deployment.

.PARAMETER configFilePath
    The path to the configuration file. Default is "./config.json".

.PARAMETER dologin
    Flag to determine if login is required. Default is $false.

.PARAMETER bicepFolder
    The path to the Bicep folder. Default is "./Bicep".

.PARAMETER myPublicIP
    The public IP address to be used. Default is an empty string which will attempt to get the current client IP address.

.EXAMPLE
    .\1-DeployBase.ps1 -configFilePath "./config.json" -dologin $true -bicepFolder "./Bicep" -myPublicIP "123.123.123.123"

.NOTES
    This is an example only.  It is not a production script.  Microsoft accepts no liability for the content or use of this script.

#>

param (
    [String]$configFilePath = "./config.json",
    [Bool]$dologin = $false,
    [String]$bicepFolder = "./Bicep",
    [String]$myPublicIP = ""
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

if (-not (Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue)) {
    Write-Error "ERROR: Failed to create resource group $rgName"
    exit 1
}

#Get the current time in hhmmss format
$currentTime = Get-Date -Format "HHmmss"

###############################
# Do the deployment           # 
###############################

#############################################
#Check we have the right providers registered
#############################################
$requiredProviders = @(
    "Microsoft.ManagedIdentity"
    "Microsoft.KeyVault"
    "Microsoft.VirtualMachineImages"
    "Microsoft.Storage"
)

$newProviders = @()

Write-Output "Checking for required Azure Resource Providers"
foreach ($provider in $requiredProviders) {
    Write-Output "Checking for Azure Resource Provider '$provider'"
    $pExist = (Get-AzResourceProvider -ProviderNamespace $provider).RegistrationState[0]
    if ($pExist -ne "Registered") {
        Write-Output "Registering Azure Resource Provider '$provider'"
        Register-AzResourceProvider -ProviderNamespace $provider
        $newProviders += $provider
    }
}

#Run around the new provider list and wait for them to register - limit this to 5 mins before timeout
if ($newProviders.Length -gt 0) {
    $startTime = Get-Date
    $endTime = $startTime.AddMinutes(5)
    while ($newProviders.Length -gt 0) {
        Write-Output "Waiting for the new providers to be registered..."
        Start-Sleep -Seconds 10

        $newProviders = $newProviders | Where-Object {
            $pExist = (Get-AzResourceProvider -ProviderNamespace $_).RegistrationState[0]
            if ($pExist -eq "Registered") {
                Write-Output "Azure Resource Provider '$_' is now registered"
                $false
            } else {
                Write-Output "Azure Resource Provider '$_' is still registering"
                $true
            }
        }

        if ((Get-Date) -gt $endTime) {
            Write-Error "ERROR: Timed out waiting for Azure Resource Providers to register"
            exit 1
        }
    }
}


Write-output "All required Azure Resource Providers are registered"

################################
#Deploy the components via Bicep
################################
Write-Verbose "Checking access for storage account from IP address"
if (-not $myPublicIP) {
    Write-Verbose "Getting current client IP address"
    $myPublicIP = (Invoke-WebRequest -Uri "http://ifconfig.me/ip").Content.Trim()
}

if (-not $myPublicIP) {
    Write-Error "ERROR: Failed to get the current client IP address"
    exit 1
}

if ($myPublicIP.Length -gt 16) {
    Write-Error "ERROR: Not an IPv4 address (ipv6 not currently supported by this script): $myPublicIP"
    exit 1
}

# deploy the Base Components
Write-Verbose "Deploying main BaseComponents.bicep ($PSScriptRoot)"
$deployOutput = New-AzResourceGroupDeployment -Name "$currentTime-Deployment" `
    -ResourceGroupName $rgName `
    -TemplateFile "$($PSScriptRoot)/$($bicepFolder)/BaseComponents.bicep" `
    -Verbose `
    -TemplateParameterObject @{
        storageAccountName = $configJson.storageName
        #computeGalName = $configJson.computeGalleryName
        location = $configJson.location
        containerIBScripts = $configJson.containerIBScripts
        containerIBPackages = $configJson.containerIBPackages
        vnetAddressPrefix = $configJson.vnetAddressPrefix
        roleDefImagesName = $configJson.roleDefImagesName
        roleDefNetworkName = $configJson.roleDefNetworkName
        storageFWIPAddress = $myPublicIP
    }


if (-not $deployOutput) {
    Write-Error "ERROR: Failed to deploy $($PSScriptRoot)/$($bicepFolder)/BaseComponents.bicep"
    exit 1
} else {
    #finished
    Write-Output "Finished Bicep Deployment"
}

