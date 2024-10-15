# WorkshopPlus-ImageBuilder

1-day workshop focusing on Azure Image Builder, build automation, and use.

## Overview

This workshop provides a comprehensive guide to using Azure Image Builder for automating and management of custom images in Azure from the command line. The workshop is structured around six PowerShell scripts that guide you through the process of setting up your environment, configuring RBAC, uploading necessary files, and building your custom images.

## Prerequisites

Before you begin, ensure you have the following:

- An Azure subscription
- PowerShell installed
- Azure Powershell Module (AZ) - `Install-Module -Name Az -Repository PSGallery -Force`
- Azure Powershell Bicep installed - [Download](https://github.com/Azure/bicep/releases/latest/download/bicep-setup-win-x64.exe) - ([Reference](https://learn.microsoft.com/en-gb/azure/azure-resource-manager/bicep/install#install-manually))
- Install the Azure AZ ImageBuilder module - `Install-Module -Name Az.ImageBuilder -Force -AllowClobber`
- Required permissions to create resources in your Azure subscription
- A valid configuration file (`config.json`)

## Configuration File

The `config.json` file should contain the necessary configuration settings for the scripts. Here is an example structure:

```json
{
    "subscription": "ContosoSubscription",
    "rgDeployName": "RG-ImageBuilderDemo",
    "location": "uksouth",
    "storageName": "stimagebuildercomponents",
    "containerIBScripts": "buildscripts",
    "containerIBPackages": "software",
    "computeGalleryName": "acg_imagebuilderimages",
    "umiName": "umi-imagebuilder",
    "roleDefImagesName": "Custom Role - ImageBuilderImageAdd",
    "roleDefNetworkName": "Custom Role - ImageBuilderVnetJoin",
    "vnetAddressPrefix": "10.254.254.0/24",
    "zipFileName": "IBScripts.zip"
}
```

### JSON Configuration Elements Explained

- **subscription**: The name of your Azure subscription.
- **rgDeployName**: The name of the resource group where the image deployment will occur.
- **location**: The Azure region where resources will be deployed.
- **storageName**: The name of the storage account used for storing build scripts and packages.
- **containerIBScripts**: The name of the container within the storage account for storing build scripts.
- **containerIBPackages**: The name of the container within the storage account for storing software packages.
- **computeGalleryName**: The name of the compute gallery for storing custom images.
- **umiName**: The name of the user-managed identity used by Azure Image Builder.
- **roleDefImagesName**: The name of the custom role definition for adding images.
- **roleDefNetworkName**: The name of the custom role definition for joining virtual networks.
- **vnetAddressPrefix**: The address prefix for the virtual network used by Image Builder.
- **zipFileName**: The name of the zip file containing the build scripts.

**Note:** The `storageName` must be unique across Azure. If it is not, the deployment will fail.

**Note:** If you are deploying in the same subscription as someone else you must make sure that `rgDeployName` is also unique.

## PowerShell Scripts Overview

The workshop includes six PowerShell scripts that you need to run in sequence. Below is an explanation of each script and the order in which they should be executed:

1. **1-DeployBase.ps1**
    - This script sets up the necessary environment for Azure Image Builder. It creates the resource group, storage account, and containers as specified in the `config.json` file.
    
2. **2-ConfigureRBAC.ps1**
    - This script configures Role-Based Access Control (RBAC) by assigning the necessary roles to the user-managed identity and other resources. It ensures that the identity has the required permissions to build and manage images.
    
3. **3-UploadExamplePackages.ps1**
    - This script uploads the software packages to the specified container in the storage account.
    
4. **4-UploadImageBuildScripts.ps1**
    - This script uploads the build scripts to the specified container in the storage account.
    
5. **5-ImagebuilderDefinitions.ps1**
    - This script defines the image build process. It specifies the source image, customization steps, and output location for the custom image.
    
6. **6-BuildImage-365Example.ps1**
    - This script builds a custom image using an example configuration for Microsoft 365. It demonstrates how to integrate Microsoft 365 components into your custom image.

### Execution Order

Run the scripts in the following order:

1. `1-DeployBase.ps1`
2. `2-ConfigureRBAC.ps1`
3. `3-UploadExamplePackages.ps1`
4. `4-UploadImageBuildScripts.ps1`
5. `5-ImagebuilderDefinitions.ps1`
6. `6-BuildImage-365Example.ps1`

Ensure that each script completes successfully before proceeding to the next one.


## BaseComponents.bicep

The `BaseComponents.bicep` file is a Bicep template used to deploy the foundational components required for the Azure Image Builder process. This template simplifies the deployment by defining the necessary resources in a declarative manner.


## GalleryDefinitions.bicep

The `GalleryDefinitions.bicep` file is a Bicep template used to define and deploy the Azure Compute Gallery and its associated resources. This template ensures that the custom images built using Azure Image Builder are stored and managed efficiently.

### Key Elements

- **Compute Gallery**: Defines the Azure Compute Gallery where custom images will be stored.
- **Image Definition**: Specifies the properties of the custom image, including the publisher, offer, and SKU.
- **Image Version**: Defines the versioning of the custom image, allowing for multiple versions to be stored and managed within the gallery.

### What does it do?

The `GalleryDefinitions.bicep` is used to deploy the image definitions and customisation steps.

Deploy the template after setting up the base components and before building the custom images. This ensures that the gallery is ready to store the images created during the workshop.

It is used to define each image definition including its customisation steps.

### Customisation Steps

This is the section that modifies the image for your particular uses.  It can include:

- Powershell (or cli if using linux)
- File (typically used to move files around)
- Windows Restart
- Windows Update

The PowerShell or Shell scripts are typically stored in a storage account and downloaded to the VM to be run.

Example of a customisation step:

```bicep
customizationSteps: [
      //download the scripts from the storage account
      {
        type: 'PowerShell'
        name: 'DownloadExpandBuildScripts'
        runElevated: true
        inline: [
          '$storageAccount = "${storageAccountName}"'
          'Invoke-WebRequest -Uri "${storageRepo.properties.primaryEndpoints.blob}${containerIBScripts}/${ibBuildScriptZipName}?${storageAccountSASTokenScriptBlob}" -OutFile "${ibBuildScriptZipName}"'
          'New-Item -Path "C:\\BuildScripts" -ItemType Directory -Force'
          'Expand-Archive -Path "${ibBuildScriptZipName}" -DestinationPath "${localBuildScriptFolder}" -Force'
          'Copy-Item "${localBuildScriptFolder}\\DeprovisingScript.ps1" -Destination "C:\\" -Force'
        ]
      }

      //Run the first software installer script
      {
        type: 'PowerShell'
        name: 'DownloadAndRunInstallerScript1'
        runElevated: true
        inline: [
          'Set-ExecutionPolicy Bypass -Scope Process -Force'
          'C:\\BuildScripts\\BuildScript1.ps1 "${storageAccountName}" "${storageAccountSASTokenSWBlob}" "${containerIBPackages}" "${localBuildScriptFolder}"'
        ]
      }

      //Restart the VM
      {
        type: 'WindowsRestart'
        restartTimeout: '30m'
      }

      //Run windows updates
      {
        type: 'WindowsUpdate'
        searchCriteria: 'IsInstalled=0'
        filters: [
          'exclude:$_.Title -like "*Preview*"'
          'include:$true'
        ]
        updateLimit: 500
      }

      //Restart the VM
      {
        type: 'WindowsRestart'
        restartTimeout: '30m'
      }

      //Run a validation script to ensure the build was successful
      {
        type: 'PowerShell'
        name: 'RunValidationScript'
        runElevated: true
        inline: [
          'C:\\BuildScripts\\ValidateEnvironment.ps1'
        ]
      }

      //Remove the build scripts directory
      {
        type: 'PowerShell'
        name: 'RemoveBuildScriptsDirectory'
        runElevated: true
        inline: [
          'Remove-Item -Path C:\\BuildScripts -Recurse -Force'
        ]
      } 
```

