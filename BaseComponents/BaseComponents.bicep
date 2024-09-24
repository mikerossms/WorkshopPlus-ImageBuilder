//build out the base components - RG level deployment

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

@description('The IP address of the storage account firewall to allow the current client to access the storage account allow it to upload')
@maxLength(19)
param storageFWIPAddress string

@description('The name of the container to hold the scripts used to build the Image Builder')
param containerIBScripts string = 'buildscripts'

@description('The name of the container to hold the software to be installed by the Image Builder')
param containerIBPackages string = 'software'

@description('The Name of the compute gallery')
param computeGalName string  //Compute gallery names limited to alphanumeric, underscores and periods

@description('The address prefix for the ImageBuilder Vnet')
param vnetAddressPrefix string

@description('The Name of the custom role for ImageBuilder to add images to the gallery')
param roleDefImagesName string

@description('The Name of the custom role for ImageBuilder to join the Vnet')
param roleDefNetworkName string


//Variables
// Minimal roles required for image builder to add images to the gallery (assigned to the RG)
var ImagesDefGUID = guid(roleDefImagesName)
var roleDefImagesActions = [
  'Microsoft.Compute/galleries/read'
  'Microsoft.Compute/galleries/images/read'
  'Microsoft.Compute/galleries/images/versions/read'
  'Microsoft.Compute/galleries/images/versions/write'
  'Microsoft.Compute/images/write'
  'Microsoft.Compute/images/read'
  'Microsoft.Compute/images/delete'
]

// Minimal roles for image builder to join the Vnet (assigned to RG)
var VnetDefGUID = guid(roleDefNetworkName)
var roleDefNetworkActions = [
  'Microsoft.Network/virtualNetworks/read'
  'Microsoft.Network/virtualNetworks/subnets/join/action'
]

//Create the Vnet for ImageBuilder to join
module Vnet 'br/public:avm/res/network/virtual-network:0.4.0' = {
  name: 'Vnet'
  params: {
    name: 'ImageBuilderVnet'
    location: location
    tags: tags
    addressPrefixes: [
      vnetAddressPrefix
    ]
    subnets: [
      {
        name: 'ImageBuilderSubnet'
        addressPrefix: vnetAddressPrefix
        serviceEndpoints: [
          'Microsoft.Storage'
        ]
      }
    ]
  }
}

//Storage
module Storage 'br/public:avm/res/storage/storage-account:0.13.2' = {
  name: 'Storage'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    kind: 'StorageV2'
    skuName: 'Standard_LRS'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [
        {
          value: storageFWIPAddress
          action: 'Allow'
        }
      ]
      virtualNetworkRules: [
        {
          id: Vnet.outputs.subnetResourceIds[0]
          action: 'Allow'
        }
      ]
    }
    blobServices: {
      containers: [
        {
          name: containerIBScripts
          publicAccess: 'None'
        }
        {
          name: containerIBPackages
          publicAccess: 'None'
        }
      ]
    }
  }
}

//compute Gallery
module ComputeGallery 'br/public:avm/res/compute/gallery:0.7.0' = {
  name: 'ComputeGallery'
  params: {
    name: computeGalName
    location: location
    tags: tags
  }
}

//Create ImageBuilder Image management custom role
resource roleDefImages 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: ImagesDefGUID
  properties: {
    roleName: roleDefImagesName
    description: 'Role to allow ImageBuilder to add images to the gallery'
    type: 'customRole'
    permissions: [
      {
        actions: roleDefImagesActions
        notActions: []
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

//Create ImageBuilder VnetJoin custom role
resource roleDefNetwork 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: VnetDefGUID
  properties: {
    roleName: roleDefNetworkName
    description: 'Role to allow ImageBuilder to add images to the gallery'
    type: 'customRole'
    permissions: [
      {
        actions: roleDefNetworkActions
        notActions: []
      }
    ]
    assignableScopes: [
      resourceGroup().id
    ]
  }
}

output storageRepoID string = Storage.outputs.resourceId
output storageRepoName string = Storage.outputs.name
output storageRepoRG string = Storage.outputs.resourceGroupName
output storageContainerIBScripts string = containerIBScripts
output storageContainerIBPackages string = containerIBPackages
output galleryName string = ComputeGallery.outputs.name
output customImagesDefinitionID string = roleDefImages.properties.roleName
output customNetworkDefinitionID string = roleDefNetwork.properties.roleName
