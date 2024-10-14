<#
    .SYNOPSIS
    This is an example script that is used by the Image Buidler (Packer) to install software into the image

    .DESCRIPTION
    This script provides a series of steps that calls on a set of common library functions to automate the
    building of a customised image.  This includes the installation of software of multiple types from
    multiple sources and direct configuration of the image as required

    It is called during the Image Builder build process, though it can also be called directly for testing.

    .INPUTS
    storageAccount - The name of the storage account that contains the software repository
    sasToken - The SAS token used to access the software repository
    container - The name of the container in the storage account that contains the software repository
    buildScriptsFolder - The folder that contains the common library functions (defaults to C:\BuildScripts)
    runLocally - If set to true, the script will run locally using the library functions relative to the folder structure in the GitHub repo
#>
param (
    [Parameter(Mandatory=$true)]
    [string]$storageAccount,
    [Parameter(Mandatory=$true)]
    [string]$sasToken,
    [string]$container='repository',
    [string]$buildScriptsFolder='C:\BuildScripts',
    [Bool]$runLocally = $false
)

$InformationPreference = 'continue'

#Pull in the local library of functions
if ($runLocally) {
    import-module -Force ".\InstallSoftwareLibrary"
} else {
    import-module -Force "$PSScriptRoot\InstallSoftwareLibrary.psm1"
}

Write-Log "Running the Installer Script" -logtag "INSTALLER"

##Get the Repo Context - used to connect to the repo storage account (mandatory)
$repoContext = Get-RepoContext -storageRepoAccount $storageAccount -storageSASToken $sasToken -storageRepoContainer $container

######
# Everything below this point references the library functions to install software.  Take care in the order in which these are run to
# ensure that dependencies are met. For example, if you are installing a python PIP package, make sure that Python is already installed
######

##Install Software from the Repo
#Install-EXE -repoContext $repoContext -repoPath "TestSoftware\kdiff3-1.9.5-windows-64-cl.exe" -installParams "/S"
#Install-MSI -repoContext $repoContext -repoPath "TestSoftware\7z2201-x64.msi" -installParams ""
#Install-MSI -repoContext $repoContext -repoPath "MMRHostInstaller\MsMMRHostInstaller_x64.msi" -installParams ""


##Install Software from Chocolatey
#Install core software and tools (choco repo package)
# $chocoCoreTools = "Common\ChocoCommonPackages.config"
# Install-ChocoPackageList -packageListPath $chocoCoreTools -repoContext $repoContext

#Install visual studio (single package)
#Install-ChocoPackage -package "visualstudio2022community" -parameters "--add Microsoft.VisualStudio.Workload.Data --add Microsoft.VisualStudio.Workload.Azure --add Microsoft.VisualStudio.Workload.DataScience --add Microsoft.VisualStudio.Workload.NetCoreTools --add Microsoft.VisualStudio.Workload.NetWeb --add Microsoft.VisualStudio.Workload.Python --add Microsoft.VisualStudio.Component.AzureDevOps.OfficeIntegration --includeRecommended --locale en-GB --no-update"
#Install-ChocoPackage -package "powerbi" -ignoreChecksum $true   #Note: ignoring checksums is not recommended but sometimes necessary
# Install-ChocoPackage -package "vscode"

#Install data tools (choco repo package)
#$chocoDevTools = "Image-Specific-Core\ChocoDevelopment.config"
#Install-ChocoPackageList -packageListPath $chocoDevTools -repoContext $repoContext


##Install Software from WinGet
#NOTE: This is not supported in Windows 10
#NOTE: This requires further work to pull and install from Github

# Install-WingetPackage -package "Microsoft.VisualStudioCode" 
# Install-WingetPackage -package "Google.Chrome"

##Install Python Modules from list
#Install-PythonPip -package "pandas"
#Install-PythonPipList -packageListPath "TestSoftware\PythonPackages.txt" -repoContext $repoContext

##Install Powershell Module
#Install the Microsoft Graph API Module
#Install-PowerShellModule -moduleName "Microsoft.Graph.Authentication"

##Deploy Files from the Software Repo
#Copy the user logoff batch file and icon to c:\scripts
#Import-FileFromRepo -repoContext $repoContext -repoPath "TestSoftware\localscripts.zip" -destinationPath "c:\LocalScripts" -unzip $true

##Install Windows Capability
#Install DNS RSAT Tool
#Install-WindowsCapability -capabilityName "Rsat.Dns"

#Install a VSIX file into Visual Studio
#Install-VSIX -repoContext $repoContext -filePath "TestSoftware\Open_VSIX_Gallery_v2.0.10.vsix"

##Copy the Sysprep Deprovisioning Script into place (this is required)
Write-Log "Copying Deprovisioning Script to C:\" -logtag $logtag
Copy-Item -Path "$buildScriptsFolder\DeprovisioningScript.ps1" -Destination "c:\DeprovisioningScript.ps1" -Force

Write-Log "Installation script finished" -logtag $logtag

