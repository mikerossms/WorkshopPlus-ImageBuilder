<#
.SYNOPSIS
    Starts and monitors the build process for the image.

.DESCRIPTION
    This script starts and monitors the build process for the image. It defaults to the "365ExampleTemplate" image and performs a dry run of the 
    build process. To actually build the image, set the $doBuildImage parameter to $true.

.PARAMETER configFilePath
    The path to the configuration file. Default is "./config.json".

.PARAMETER dologin
    Flag to determine if login is required. Default is $false.

.PARAMETER imageToBuild
    The name of the image to build. Default is "365ExampleTemplate".

.PARAMETER doBuildImage
    Flag to determine if the image should actually be built. Default is $false (dry run).

.PARAMETER pollingTime
    The time interval (in seconds) for polling the build status. Default is 60 seconds.

.EXAMPLE
    .\6-BuildImage-365Example.ps1 -configFilePath "./config.json" -dologin $true -imageToBuild "CustomImageTemplate" -doBuildImage $true -pollingTime 30

.NOTES
    This is an example only.  It is not a production script.  Microsoft accepts no liability for the content or use of this script.
#>

param (
    [String]$configFilePath = "./config.json",
    [Bool]$dologin = $false,
    [String]$imageToBuild = "365ExampleTemplate",
    [Bool]$doBuildImage = $false,
    [int]$pollingTime = 60
)

$VerbosePreference = "Continue"

# This script starts and monitors the build process for the image.
# This script defaults to the "365ExampleTemplate" image.
# This script defaults to doing a dry run of the build process.  To actually build the image, set $doBuildImage to $true.

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

# Get the name of the template to build.  Search for the name provided to get a list of templates and choose the lastest one
Write-Verbose "Retrieving image builder templates in resource group $imageRG..."
$imageTemplates = Get-AzImageBuilderTemplate -ResourceGroupName $imageRG
$imageList = @()
if ($imageTemplates) {
    Write-Verbose "Found the following image builder templates matching: $imageToBuild"

    $imageTemplates | ForEach-Object {
        if ($_.Name -like "$imageToBuild*") {
            $imageList += $_.Name
        }
    }
} else {
    Write-Error "No image builder templates found in resource group $imageRG with image name like:$imageToBuild"
    exit 1
}

# Check if there is more than 1 image returned
$templateName = $imageList[0]
if ($imageList.Count -gt 1) {
    Write-Warning "More than one image builder template found.  Selecting the latest image definition"
    #Step through each name in the list and determine the latest one
    $latestDate = Get-Date -Year 1900 #Just to get a correctly formatted datetime object to compare with
    $imageList | ForEach-Object {
        $d = $_.Split('-')
        $templateImageDate = Get-Date -Day $d[3] -Month $d[2] -Year $d[1] -Hour $d[4] -Minute $d[5] -Second $d[6]
        if ($templateImageDate -gt $latestDate) {
            $latestDate = $templateImageDate
            $templateName = $_
        }
    }
}

Write-Output "Selected image builder template: $templateName"

###START BUILD###

#If all is good and doBuildImage is $true, then start building the image
if ($doBuildImage) {
    #Now start the process of building the image
    Write-Output ""
    Write-Output "The image is now building.  This might take a while."
    Write-Output " - This script will continue to poll the image to check on progress."
    Write-Output " - If you wish to check on the progress you can also use the following command (not if the pipeline fails, it will NOT stop the build):"
    Write-Output "    Get-AzImageBuilderTemplate -ImageTemplateName '$templateName' -ResourceGroupName '$imageRG' | Select-Object LastRunStatusRunState, LastRunStatusRunSubState, LastRunStatusMessage"
    Write-Output ""

    $start = Get-Date
    Write-Output "Build Started: $start"

    #Kick off the image builder
    Start-AzImageBuilderTemplate -ResourceGroupName $imageRG -Name $templateName -NoWait

    #while loop that will poll the get-azimagebuildertemplate command until ProvisioningState is Succeeded or Failed
    while ($true) {
        $count++
        $image = Get-AzImageBuilderTemplate -ImageTemplateName $templateName -ResourceGroupName $imageRG
        if ($image.LastRunStatusRunState -eq 'Succeeded') {
            Write-Output "Image build succeeded"
            break
        }
        elseif ($image.LastRunStatusRunState -eq 'PartiallySucceeded') {
            Write-Warning "The image built with issues.  Check the logs"
            break
        }
        elseif ($image.LastRunStatusRunState -eq 'Failed') {
            Write-Error "Image build failed"
            Write-Output " - Error Message: $($image.LastRunStatusMessage)"
            Write-Output " - Check the Storage account in the Staging RG for more information:"
            Write-Output "   - RG: $($image.ExactStagingResourceGroup)"
            break
        }
        else {
            $timespan = new-timespan -start $start -end (get-date)
            Write-Output "Image build is still running (Running for: $($timespan.Hours) hours, $($timespan.Minutes) minutes).  Polling again in $pollingTime seconds: $($image.LastRunStatusRunState) - $($image.LastRunStatusRunSubState)"
            Start-Sleep -Seconds $pollingTime
        }
    }
    $timespan = new-timespan -start $start -end (get-date)
    Write-Output "Image build ended after: $($timespan.Hours) hours, $($timespan.Minutes) minutes, $($timespan.Seconds) seconds"
} else {
    Write-Warning "The image template was created, but the build itself was skipped"
    Write-Output "If you wish to run the build, you can use the following command:"
    Write-Output "Start-AzImageBuilderTemplate -ResourceGroupName '$imageRG' -Name '$templateName' -NoWait"
    Write-Output "You can then monitor it using command:"
    Write-Output "Get-AzImageBuilderTemplate -ImageTemplateName '$templateName' -ResourceGroupName '$imageRG' | Select-Object LastRunStatusRunState, LastRunStatusRunSubState, LastRunStatusMessage"
}

Write-Output "Completed"