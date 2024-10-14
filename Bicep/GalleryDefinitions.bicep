//build out the image builder components - RG level deployment

targetScope = 'resourceGroup'

//Parameters
@description('The local environment identifier.  Default: dev')
param localenv string = 'dev'

@description('Location of the Resources. Default: UK South')
param location string = 'uksouth'

@description('Tags to be applied to all resources')
param tags object = {
  Environment: localenv
  WorkloadName: 'WorkshopPlus-Imagebuilder'
  BusinessCriticality: 'low'
  CostCentre: 'Contoso'
  DataClassification: 'general'
}

@description('The name of the storage account to create as a software repo for the Image Builder and a place to host its common components')
@maxLength(24)
param storageAccountName string

@description('The name of the container to hold the scripts used to build the Image Builder')
param containerIBScripts string = 'buildscripts'

param ibBuildScriptZipName string = 'IBScripts.zip'

@description('The name of the container to hold the software to be installed by the Image Builder')
param containerIBPackages string = 'software'

@description('The Name of the compute gallery')
param computeGalName string  //Compute gallery names limited to alphanumeric, underscores and periods

@description('The name of the image definition to create')
param imageDefName1 string = 'vmi_Windows365Example'

@description('The actual definition of the image to create')
param imageDef1 object = {
  name: imageDefName1
  osType: 'Windows'
  osState: 'Generalized'
  hyperVGeneration: 'V2'

  identifier: {
    offer: 'office-365'
    publisher: 'MicrosoftWindowsDesktop'
    sku: 'win11-24h2-avd-m365'
  }
}

//UMI details
@description('Required - The name of the UMI to use with this build')
param umiName string

//Image Configuration parameters
@description('The maximum time allowed to build the image (in minutes)')
param ibTimeout int = 180

@description('The SAS token that will be passed to the Image Builder build script to allow it to access the Build Scripts')
param ibBuildScriptSasProperties object = {
  signedPermission: 'rl'
  signedResource: 'c'
  signedProtocol: 'https'
  signedExpiry: dateTimeAdd(utcNow('u'), 'PT${ibTimeout}M')
  canonicalizedResource: '/blob/${storageAccountName}/${containerIBScripts}'
}

@description('The SAS token that will be passed to the Image Builder build script to allow it to access the Software repository')
param ibBuildSoftwareSasProperties object = {
  signedPermission: 'rl'
  signedResource: 'c'
  signedProtocol: 'https'
  signedExpiry: dateTimeAdd(utcNow('u'), 'PT${ibTimeout}M')
  canonicalizedResource: '/blob/${storageAccountName}/${containerIBPackages}'
}

@description('The location on the Image Builder VM where the build scripts are uploaded an unpacked to.  Note backslash must be escaped')
param localBuildScriptFolder string = 'C:\\BuildScripts'

//VARIABLES
var storageAccountSASTokenScriptBlob = listServiceSas(storageRepo.id, '2021-04-01',ibBuildScriptSasProperties).serviceSasToken
var storageAccountSASTokenSWBlob = listServiceSas(storageRepo.id, '2021-04-01',ibBuildSoftwareSasProperties).serviceSasToken

//RESOURCES
//Pull in the storage account
resource storageRepo 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

//Pull in the VNET
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' existing = {
  name: 'ImageBuilderVnet'
}

//Pull in the UMI
resource umi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: umiName
}

//Create image gallery definition (the definition and placeholder in the image gallery to which actual images are attached - metadata/taxonomy)
//Creating the gallery is also used to create the image definitions used in the build process
//Once a Gallery is created, you can also add definitions using "resource" and the "Microsoft.Compute/galleries/images" resource type

//Note, best to try and use AVD images with Gen2.  AVD images provide multisession and Gen2 provides best performance.
// $locName = 'uksouth'
// Get-AzVMImagePublisher -Location $locName | Select PublisherName   #Typically MicrosoftWindowsDesktop
// Get-AzVMImageOffer -Location $locName -PublisherName 'MicrosoftWindowsDesktop' | Select Offer  #Typically Windows-10, Windows-11, office-365

// Get-AzVMImageSku -Location $locName -PublisherName 'MicrosoftWindowsDesktop' -Offer 'Windows-10' | Select Skus  #Example win10-22h2-avd-g2
// #OR
// Get-AzVMImageSku -Location $locName -PublisherName 'MicrosoftWindowsDesktop' -Offer 'office-365' | Select Skus  #Example win10-22h2-avd-m365 (includes office 365 apps)

//You can, of course, also use your own custom images by pointing to a gallery image.


module imageGallery 'br/public:avm/res/compute/gallery:0.7.1' = {
  name: 'ComputeGallery'
  params: {
    name: computeGalName
    location: location
    tags: tags
    images: [
      imageDef1
    ]
  }
}

//Create the first image template (the actual content of the template including build scripts and software packages)
//This template, once created in step 5, is build using "6-BuildImage-365Example.ps1"
module imageTemplate 'br/public:avm/res/virtual-machine-images/image-template:0.4.0' = {
  name: 'ImageTemplate'
  params: {
    name: '365ExampleTemplate'
    location: location
    tags: tags
    subnetResourceId: vnet.properties.subnets[0].id //Assumes the first subnet is the one to join - this joins the image builder service to the VNET created in BaseComponents.bicep
    distributions: [
      {
        sharedImageGalleryImageDefinitionResourceId: imageGallery.outputs.imageResourceIds[0]
        type: 'SharedImage'
      }
    ]
    imageSource: {
      type: 'PlatformImage'
      publisher: 'MicrosoftWindowsDesktop'
      offer: 'office-365'
      sku: 'win11-24h2-avd-m365'
      version: 'latest'
    }
    //vmSize: 'Standard_D2s_v3' - this is the default VM builder size.  Can be overridden at build stage
    managedIdentities: {
      userAssignedResourceIds: [
        umi.id
      ]
    }
    // customizationSteps: [
      // {
      //   type: 'PowerShell'
      //   name: 'DownloadExpandBuildScripts'
      //   runElevated: true
      //   inline: [
      //     '$storageAccount = "${storageAccountName}"'
      //     'Invoke-WebRequest -Uri "${storageRepo.properties.primaryEndpoints.blob}${containerIBScripts}/${ibBuildScriptZipName}?${storageAccountSASTokenScriptBlob}" -OutFile "${ibBuildScriptZipName}"'
      //     'New-Item -Path "C:\\BuildScripts" -ItemType Directory -Force'
      //     'Expand-Archive -Path "${ibBuildScriptZipName}" -DestinationPath "${localBuildScriptFolder}" -Force'
      //   ]
      // }

      // //Run the first software installer script
      // {
      //   type: 'PowerShell'
      //   name: 'DownloadAndRunInstallerScript1'
      //   runElevated: true
      //   inline: [
      //     'Set-ExecutionPolicy Bypass -Scope Process -Force'
      //     'C:\\BuildScripts\\BuildScript1.ps1 "${storageAccountName}" "${storageAccountSASTokenSWBlob}" "${containerIBPackages}" "${localBuildScriptFolder}"'
      //   ]
      // }

      // //Restart the VM
      // {
      //   type: 'WindowsRestart1'
      //   restartTimeout: '30m'
      // }

      // //Run the second software installer script
      // {
      //   type: 'PowerShell'
      //   name: 'DownloadAndRunInstallerScript2'
      //   runElevated: true
      //   inline: [
      //     'Set-ExecutionPolicy Bypass -Scope Process -Force'
      //     'C:\\BuildScripts\\BuildScript2.ps1 "${storageAccountName}" "${storageAccountSASTokenSWBlob}" "${containerIBPackages}" "${localBuildScriptFolder}"'
      //   ]
      // }

      // //Restart the VM
      // {
      //   type: 'WindowsRestart2'
      //   restartTimeout: '30m'
      // }

      // //Run windows updates
      // {
      //   type: 'WindowsUpdate'
      //   searchCriteria: 'IsInstalled=0'
      //   filters: [
      //     'exclude:$_.Title -like "*Preview*"'
      //     'include:$true'
      //   ]
      //   updateLimit: 500
      // }

      // //Restart the VM
      // {
      //   type: 'WindowsRestart3'
      //   restartTimeout: '30m'
      // }

    // ]
  }
}

