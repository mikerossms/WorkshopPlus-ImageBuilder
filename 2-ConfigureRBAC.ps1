param (
    [String]$configFilePath = "./config.json",
    [Bool]$dologin = $false
)

$VerbosePreference = "Continue"

# Roles for the UMI to assume on resources created in 1-DeployBase.ps1
# $roleACG = "Contributor"
# $roleStorageScripts = "Storage Blob Data Contributor"  
# $roleStoragePackages = "Storage Blob Data Reader"

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

#Get the location
$location = $configJson.location

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
    $location = $location
    $rgParams = @{
        Name = $rgName
        Location = $location
    }
    New-AzResourceGroup @rgParams
    Write-Output "Resource group $rgName created successfully."
} else {
    Write-Verbose "Resource group $rgName already exists."
}

#Get the subscription ID
$subID = (Get-AzSubscription -SubscriptionName $subName).Id


###############################
# Do the deployment           # 
###############################

###########################
#Create the UMI if required
###########################

#check for and retrieve the UMI
$umiName = $configJson.umiName
Write-Output "Checking for User Assigned Managed Identity '$umiName' in '$rgName'"
$umiID = Get-AzUserAssignedIdentity -ResourceGroupName $rgName -Name $umiName -ErrorAction SilentlyContinue

if (-Not $umiID) {
    Write-Output " - Creating missing User Assigned Managed Identity '$umiName'"
    $umiID = New-AzUserAssignedIdentity -ResourceGroupName $rgName -Location $location -Name $umiName -SubscriptionID $subID  #-Tag $tags
    if ($umiID) {
        Write-Output " - Created '$umiName' ($($umiID.PrincipalId)) - pausing 60 seconds for Azure to catch up"
        Start-Sleep -s 60
    } else {
        Write-Output "FAILED to create '$umiName'"
        exit 1
    }
    
} else {
    Write-Output " - User Assigned Managed Identity '$umiName' already exists ($($umiID.PrincipalId))"
}

##################################
#Assign the Custom Role to the UMI
##################################

#check to make sure the custom role exists
$imageRole = Get-AzRoleDefinition $configJson.roleDefImagesName
if (-Not $imageRole) {
    Write-Error "ERROR - Custom Role not found ($configJson.roleDefImagesName) - please make sure the bicep file has been deployed successfully"
    exit 1
}
$vnetRole = Get-AzRoleDefinition $configJson.roleDefNetworkName
if (-Not $vnetRole) {
    Write-Error "ERROR - Custom Role not found ($configJson.roleDefNetworkName) - please make sure the bicep file has been deployed successfully"
    exit 1
}

# Assign the role to permit image creation to the UMI
# Note: As the custom role has specific scope embedded, it will only work in the specific RG
$parameters = @{
    ObjectId = $umiID.PrincipalId
    RoleDefinitionName = $configJson.roleDefImagesName
    Scope = '/subscriptions/' + $subID + '/resourceGroups/' + $rgName
}
New-AzRoleAssignment @parameters

# Assign the role to permit Vnet interaction to UMI
$parameters = @{
    ObjectId = $umiID.PrincipalId
    RoleDefinitionName = $configJson.roleDefNetworkName
    Scope = '/subscriptions/' + $subID + '/resourceGroups/' + $rgName
}
New-AzRoleAssignment @parameters

#https://learn.microsoft.com/en-us/azure/virtual-machines/linux/image-builder-permissions-powershell
#https://learn.microsoft.com/en-us/azure/role-based-access-control/custom-roles-bicep?tabs=CLI
#https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/virtual-network#Usage-examples

