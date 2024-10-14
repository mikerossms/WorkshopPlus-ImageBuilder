<#
.SYNOPSIS
    Installs a chocolatey package

.DESCRIPTION
    Chocolately is a package manage similar to winget.  it is run by a 3rd party but contains a large number of packages.
    This will run on both windows desktop and server
    This script just installs python in this case

.NOTES
    This is an example only.  It is not a production script.  It is just to show how to install a package using chocolatey

.INPUTS
    storageAccount - The name of the storage account that contains the software repository
    sasToken - The SAS token used to access the software repository
    container - The name of the container in the storage account that contains the software repository
    buildScriptsFolder - The folder that contains the common library functions (defaults to C:\BuildScripts)
    runLocally - If set to true, the script will run locally using the library functions relative to the folder structure in the GitHub repo

#>

# Define parameters for the script
param (
    [Parameter(Mandatory=$true)]
    [string]$storageAccount,

    [Parameter(Mandatory=$true)]
    [string]$sasToken,

    [string]$container = 'software',

    [string]$buildScriptsFolder = 'C:\BuildScripts',

    [Bool]$runLocally = $false
)

$InformationPreference = 'continue'

#Installs chocolately if not found
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Chocolatey" -logtag $logtag
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString("https://chocolatey.org/install.ps1"))
}

Write-Log "Installing Chocolatey Package $package" -logtag $logtag

#Install the python package
$package = "python"
try {
    Write-Output "RUN: choco install $package -y -r --no-progress --ignore-package-exit-codes"
    choco install $package -y -r --no-progress --ignore-package-exit-codes
}
catch {
    Write-Error "Error installing Chocolatey Package $package"
}