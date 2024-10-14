#Library to install the software

<#
    .SYNOPSIS
    Take a Azure Storage account, SAS token and container name and return a context object that can be used to access the repo

    .INPUTS
    storageRepoAccount - The name of the Azure Storage Account
    storageSASToken - The SAS token for the Azure Storage Account
    storageRepoContainer - The name of the Azure Storage Container
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    An Azure Storage Container object

    .EXAMPLE
    Get-RepoContext -storageRepoAccount "swrepo" -storageSASToken "<sasToken>" -storageRepoContainer "repository"
#>
function Get-RepoContext {
    param (
        [Parameter(Mandatory=$true)]
        [String]$storageRepoAccount,
        [Parameter(Mandatory=$true)]
        [String]$storageSASToken,
        [Parameter(Mandatory=$true)]
        [String]$storageRepoContainer,
        [String]$logtag = "CONTEXT"
    )

    #Check to see if the AZ module is already installed
    Write-Log "Checking for AZ Module (required)" -logtag $logtag
    if (-Not (Get-Module -Name Az.Storage -ListAvailable)) {
        Write-Log "AZ Module is not installed - Installing" -logtag $logtag
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Install-Module -name Az.Storage -Scope CurrentUser -Repository PSGallery -Force
    }

    Write-Log "Getting Repo Context" -logtag $logtag

    # Write-Log "DEBUG: Account name: $storageRepoAccount" -logtag $logtag
    # Write-Log "DEBUG: SAS token: $storageSASToken" -logtag $logtag
    # Write-Log "DEBUG: Container name: $storageRepoContainer" -logtag $logtag
    # Write-Log "DEBUG: Command: New-AzStorageContext -StorageAccountName $storageRepoAccount -SasToken $storageSASToken | Get-AzStorageBlob -Container $storageRepoContainer" -logtag $logtag

    #$stContext = New-AzStorageContext -StorageAccountName $storageRepoAccount -SasToken $storageSASToken | Get-AzStorageShare -Name $storageRepoShare
    $stContext = New-AzStorageContext -StorageAccountName $storageRepoAccount -SasToken $storageSASToken

    if (-Not $stContext) {
        Write-Log "Provided SAS token failed - Trying to generate a new SAS token" -logtag $logtag
        $StartTime = Get-Date
        $EndTime = $StartTime.AddHours(3.0)

        $storageContext = New-AzStorageContext -StorageAccountName $storageRepoAccount  #User context
        $storageSASToken = New-AzStorageContainerSASToken -Name $storageRepoContainer -Permission "rdl" -Context $storageContext -StartTime $StartTime -ExpiryTime $EndTime
        $stContext = New-AzStorageContext -StorageAccountName $storageRepoAccount -SasToken $storageSASToken
    }

    if (-Not $stContext) {
        Write-Log "Provided SAS token failed - trying user context" -logtag $logtag
        $stContext = New-AzStorageContext -StorageAccountName $storageRepoAccount  #User context
    }

    #Get-AzStorageBlob -Container $storageRepoContainer

    if (-Not $stContext) {
        Write-Log "FATAL: Could not get the storage account context for Repo share" -logtag $logtag -type "FATAL"
        exit 1
    }

    #Return the storage account context and the container for the software repo
    $repoContext = @{
        "stContext" = $stContext
        "stRepoContainer" = $storageRepoContainer
    }

    if ($stContext) {
        Write-Log "Successfully got the storage account context for Repo share: $storageRepoAccount/$storageRepoContainer" -logtag $logtag
        #Write-Log "Context: $(convertto-json $stContext)" -logtag $logtag -type "DEBUG"
    }

    return $repoContext
}

<#
    .SYNOPSIS
    Using a repo context object, download a file from the repo to the C:\BuildScripts\Software (default) folder#

    .INPUTS
    repoContext - The context object returned by Get-RepoContext
    blobPath - The "path" to the file in the container e.g. software\7zip\7z1900-x64.msi
    localPath - The local path to download the file to (default is C:\BuildScripts\Software)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    A object that contains various parameters about the downlaoded file including whether of not the file was successfully downloaded

    .EXAMPLE
    Get-FileFromRepo -repoContext $repoContext -blobPath "software\7zip\7z1900-x64.msi"
    Get-FileFromRepo -repoContext $repoContext -blobPath "software\7zip\7z1900-x64.msi" -localPath "C:\OtherLocation"
#>
function Get-FileFromRepo {
    param (
        [Parameter(Mandatory=$true)]
        [Object]$repoContext,
        [Parameter(Mandatory=$true)]
        [String]$blobPath,
        [String]$localPath = "C:\BuildScripts\Software",
        [String]$logtag = "DOWNLOAD"
    )

    $downloadSuccess = $false

    Write-Log "Setting up transfer of fime from repo: $blobPath" -logtag $logtag

    $stContext = $repoContext.stContext
    $stContainer = $repoContext.stRepoContainer

    #Check if the C:\BuildScripts\Software folder exists
    if (-not (Test-Path $localPath)) {
        Write-Log "Creating $localPath folder" -logtag $logtag
        New-Item -ItemType Directory -Path $localPath | Out-Null
        #Check if it has been created
        if (-not (Test-Path $localPath)) {
            Write-Log "Could not create $localPath folder" -logtag $logtag -type "FATAL"
            exit 1
        }
    }

    #Get the file name from a file path
    $filename = $blobPath.Split("\")[-1]

    $localFileName = "$($localPath)\$($filename)"

    Write-Log "Downloading file '$filename' from repo to folder '$localPath'" -logtag $logtag

    #Download file from the repo to the $localPath folder
    Get-AzStorageBlobContent -Context $stContext -Container $stContainer -Blob $blobPath -Destination $localFileName

    #TEst if the file was successfully downloaded
    $downloadSuccess = "none"
    if (-Not (Test-Path $localFileName)) {
        Write-Log "FATAL: Could not download file $blobPath from repo" -logtag $logtag -type "FATAL"
        $downloadSuccess =  $false

    } else {
        $checksum = (Get-FileHash -Path $localFileName -Algorithm MD5).Hash
        Write-Log "File downloaded successfully to: $localFileName" -logtag $logtag
        Write-Log " - From: $blobPath" -logtag $logtag
        Write-Log " - To: $localFileName" -logtag $logtag
        Write-Log " - Checksum: $checksum" -logtag $logtag  
        $downloadSuccess = $true
    }

    $filedata = @{
        filename = [string]$filename
        filePath = [string]$localFileName
        blobPath = [string]$blobPath
        downloadSuccess = [Bool]$downloadSuccess
        fileChecksum = $checksum
    }

    #Could expand this to check the above checksum against an unmutable file checksum stored in a secure location to validate the file if required

    return $filedata
}

<#
    .SYNOPSIS
    Downloads an MSI file from the repo (unless installFromRepo is set to false) and then installs the MSI file

    .INPUTS
    filePath - The "path" to the file in the container e.g. software\7zip\7z1900-x64.msi OR The path to the local file e.g. c:\software\7zip\7z1900-x64.msi
    repoContext - The context object returned by Get-RepoContext (required for downloading from the repo)
    installParams - The parameters to pass to the MSI e.g. "/S" (optional - silent install enabled by default)
    installFromRepo - Whether to download the file from the repo or install from a local file (default is true)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the MSI was successfully installed

    .EXAMPLE
    Download and install:  Install-MSI -repoPath "software\7zip\7z1900-x64.msi" -installParams "/S" -repoContext $repoContext
    Local install:  Install-MSI -repoPath "c:\software\7zip\7z1900-x64.msi" -installParams "/S" installFromRepo $false
#>
function Install-MSI {
    param (
        [Parameter(Mandatory=$true)]
        [String]$repoPath,
        [Object]$repoContext,
        [String]$installParams = "",
        [Bool]$installFromRepo = $true,
        [String]$logtag = "INSTALL-MSI"
    )

    $msiFile = ""
    if ($installFromRepo) {
        #Get the MSI file from the repo
        $filedata = Get-FileFromRepo -repoContext $repoContext -blobPath $repoPath
        $filename = $filedata.filename

        if (-Not $filedata.downloadSuccess) {
            Write-Log "Error getting MSI file from repo: $repoPath" -logtag $logtag -type "ERROR"
            return $false
        } else {
            Write-Log "Successfully retrieved $filename from Repo" -logtag $logtag
        }

        $msiFile = "C:\BuildScripts\Software\$($filename)"
    } else {
        Write-Log "Installing MSI file from local file: $repoPath" -logtag $logtag
        if (-Not (Test-Path $repoPath)) {
            Write-Log "EXE file does not exist: $repoPath" -logtag $logtag -type "ERROR"
            return $false
        }
        $msiFile = $repoPath
    }

    Write-Log "Installing MSI file $msiFile" -logtag $logtag

    #Add a couple of mandatory parameters if not already specified for silent install
    if ($installParams -notlike "*quiet*") {
        $installParams += " /quiet"
    }
    if ($installParams -notlike "*norestart*") {
        $installParams += " /norestart"
    }

    #Silently install an MSI file and wait for it to complete
    Write-Log "RUN: msiexec.exe /i $msiFile $installParams" -logtag $logtag

    $msiProcess = Start-Process "msiexec.exe" -ArgumentList "/I $msiFile $installParams" -PassThru -NoNewWindow -Wait
    if ($msiProcess.ExitCode -ne 0) {
        Write-Log "Error installing MSI file $msiFile" -logtag $logtag -type "ERROR"
        return $false
    }

    return $true
}

<#
    .SYNOPSIS
    Downloads an EXE file from the repo (unless installFromRepo is set to false) and then installs the EXE file

    .INPUTS
    filePath - The "path" to the file in the container e.g. software\7zip\7z1900-x64.exe OR The path to the local file e.g. c:\software\7zip\7z1900-x64.exe
    repoContext - The context object returned by Get-RepoContext (required for downloading from repo)
    installParams - The parameters to pass to the EXE e.g. "/S" (generally required for silent installs)
    installFromRepo - Whether to download the file from the repo or install from a local file (default is true)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the EXE was successfully installed

    .EXAMPLE
    Download and install:  Install-EXE -repoPath "software\7zip\7z1900-x64.exe" -installParams "/S" -repoContext $repoContext
    Local install:  Install-EXE -repoPath "c:\software\7zip\7z1900-x64.exe" -installParams "/S" installFromRepo $false
#>
function Install-EXE {
    param (
        [Parameter(Mandatory=$true)]
        [String]$repoPath,
        [Object]$repoContext,
        [String]$installParams = "",
        [Bool]$installFromRepo = $true,
        [String]$logtag = "INSTALL-EXE"
    )

    $exeFile = ""
    if ($installFRomRepo) {
        $filedata = Get-FileFromRepo -repoContext $repoContext -blobPath $repoPath
        $filename = $filedata.filename
        
        if (-Not $filedata.downloadSuccess) {
            Write-Log "Error getting EXE file from repo: $repoPath" -logtag $logtag -type "ERROR"
            return $false
        } else {
            Write-Log "Successfully retrieved $filename from Repo" -logtag $logtag
        }

        $exeFile = "C:\BuildScripts\Software\$($filename)"
    } else {
        Write-Log "Installing EXE file from local file: $repoPath" -logtag $logtag
        if (-Not (Test-Path $repoPath)) {
            Write-Log "EXE file does not exist: $repoPath" -logtag $logtag -type "ERROR"
            return $false
        }
        $exeFile = $repoPath
    }

    Write-Log "Installing EXE file $exeFile" -logtag $logtag

    #Silently install an EXE file and wait for it to complete
    Write-Log "RUN: $exeFile $installParams" -logtag $logtag

    $exeProcess = $null
    if ($installParams) {
        $exeProcess = Start-Process -FilePath $exeFile -ArgumentList $installParams -Wait -PassThru -NoNewWindow
    } else {
        $exeProcess = Start-Process -FilePath $exeFile -Wait -PassThru -NoNewWindow
    }
    if ($exeProcess.ExitCode -ne 0) {
        Write-Log "Error installing EXE file $exeFile" -logtag $logtag -type "ERROR"
        return $false
    }

    return $true
}

<#
    .SYNOPSIS
    Downloads an VSIX file from the repo (unless installFromRepo is set to false) installing it into Vistual Studio

    .NOTES
    Visual Studio must already be installed to enable this to work

    .INPUTS
    filePath - The "path" to the file in the container e.g. software\vsix\vsix.vsix OR The path to the local file e.g. c:\software\vsix\vsix.vsix
    repoContext - The context object returned by Get-RepoContext (required for downloading from repo)
    installParams - The parameters to pass to the VSIX installer (optional, installs silently by default)
    installFromRepo - Whether to download the file from the repo or install from a local file (default is true)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the EXE was successfully installed

    .EXAMPLE
    Download and install:  Install-VSIX -repoPath "software\vsix\vsix.vsix" -repoContext $repoContext -installParams "/quiet"
    Local install:  Install-VSIX -repoPath "c:\software\vsix\vsix.vsix" -installParams "/quiet" installFromRepo $false
#>
function Install-VSIX {
    param (
        [Parameter(Mandatory=$true)]
        [String]$repoPath,
        [Object]$repoContext,
        [String]$installParams = "",
        [Bool]$installFromRepo = $true,
        [String]$logtag = "INSTALL-VSIX"
    )

    $vsixFile = ""
    if ($installFromRepo) {
        $filedata = Get-FileFromRepo $repoContext $repoPath
        $filename = $filedata.filename

        if (-Not $filedata.downloadSuccess) {
            Write-Log "Error getting VSIX file from repo: $repoPath" -logtag $logtag -type "ERROR"
            return $false
        }

        $vsixFile = "C:\BuildScripts\Software\$($filename)"
    } else {
        Write-Log "Installing VSIX file from local file: $repoPath" -logtag $logtag
        if (-Not (Test-Path $repoPath)) {
            Write-Log "VSIX file does not exist: $repoPath" -logtag $logtag -type "ERROR"
            return $false
        }
        $vsixFile = $repoPath
    }
    

    Write-Log "Installing VSIX file $vsixFile" -logtag $logtag

    #Find the VSIXInstaller.exe
    $vsixInstaller = Get-ChildItem -Path "C:\Program Files (x86)\Microsoft Visual Studio\Installer\resources\app" -Filter "VSIXInstaller.exe" -Recurse | Select-Object -First 1

    #Install the VSIX file
    Write-Log "RUN: $vsixInstaller $vsixFile $installParams" -logtag $logtag

    #check to make sure the installParams has the quiet, admin and logfile params
    if ($installParams -notlike "*quiet*") {
        $installParams += " /quiet"
    }
    if ($installParams -notlike "*admin*") {
        $installParams += " /admin"
    }
    if ($installParams -notlike "*logfile*") {
        $installParams += " /logfile:vsixinstall.log"
    }

    $returnValue = $false
    $vsixProcess = Start-Process -FilePath $vsixInstaller -ArgumentList "$vsixFile $installParams" -Wait -PassThru -NoNewWindow
    if ($vsixProcess.ExitCode - 0) {
        Write-Log "Error installing VSIX file $vsixFile" -logtag $logtag -type "ERROR"
    } else {
        $returnValue = $true
    }

    Copy-Item -Path "$env:TEMP\vsixinstall.log" -Destination "C:\BuildLogs\vsixinstall_$filename.log" -Force

    return $returnValue
}

<#
    .SYNOPSIS
    Checks to see if Python is installed

    .NOTES
    This function is not exported

    .INPUTS
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns the path to the python.exe file if it is installed, otherwise returns an empty string

    .EXAMPLE
    $pythonpath = Get-PythonLocation
#>
function Get-PythonLocation {
    param (
        [String]$logtag = "CHECK-PYTHON"
    )

    #Check if python is installed
    $pythonpath = ""
    $location = Get-ChildItem -Path "c:\python*\python.exe" | Select-Object -First 1
    if ($location) {
        $pythonpath = $location.FullName
    } else {
        $location = Get-ChildItem -Path "C:\Program Files\Python*\python.exe" | Select-Object -First 1
        if ($location) {
            $pythonpath = $location.FullName
        } else {
            Write-Log "Python is not installed" -logtag $logtag -type "WARN"
            return ''
        }
    }

    Write-Log "Python is installed at $pythonpath" -logtag $logtag
    return $pythonpath
}


<#
    .SYNOPSIS
    Installs a Python PIP package

    .NOTES
    Requires that Python has already been installed

    .INPUTS
    package - The name of the PIP package or local file to install
    pythonPath - The path to the python.exe file (optional, will check if installed if not specified)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the PIP package was successfully installed

    .EXAMPLE
    Install-PythonPip -package "pandas"
#>
function Install-PythonPip {
    param (
        [Parameter(Mandatory=$true)]
        [String]$package,
        [String]$pythonPath = "",
        [String]$logtag = "INSTALL-PYTHONPIP"
    )

    #Check if python is installed
    if (-Not $pythonPath) {
        $pythonPath = Get-PythonLocation -logtag $logtag
        if (-not $pythonPath) {
            Write-Log "Python is not installed - not doing PIP install" -logtag $logtag -type "WARN"
            return $false
        }
    }
    
    #Check PIP installed and upgrade if required
    $pipInstallProcess = Start-Process -FilePath $pythonPath -ArgumentList "-m pip install --upgrade pip" -Wait -PassThru -NoNewWindow
    if ($pipInstallProcess.ExitCode -ne 0) {
        Write-Log "Error installing Python PIP: $pythonPath -m pip install --upgrade pip" -logtag $logtag -type "ERROR"
        return $false
    }

    #Get the PIP3 path
    $pythonRootPath = Split-Path -Path  $pythonPath
    $pipPath = Join-Path -Path $pythonRootPath -ChildPath "Scripts\pip3.exe"

    #Install the PIP package
    $pipPackageProcess = Start-Process -FilePath $pipPath -ArgumentList "install $package" -Wait -PassThru -NoNewWindow
    if ($pipPackageProcess.ExitCode -ne 0) {
        Write-Log "Error installing $package with Python PIP: $pipPath install $package" -logtag $logtag -type "ERROR"
        return $false
    }

    return $true

}

<#
    .SYNOPSIS
    Installs a list of Python PIP packages from a text file

    .NOTES
    Requires that Python has already been installed

    .INPUTS
    packageListPath - The path to the text file in the container OR the local file path
    repoContext - The repo context object (required for downloading from the repo)
    pythonPath - The path to the python.exe file (optional, will check if installed if not specified)
    installFromRepo - Whether to install from the repo (default is true)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the PIP packages were successfully installed

    .EXAMPLE
    Install-PythonPipList -packageListPath "c:\BuildScripts\pipPackageList.txt" -installFromRepo $false
    Install-PythonPipList -repoContext $repoContext -packageListPath "Packages\pipPackageList.txt" 
#>
function Install-PythonPipList {
    param (
        [Parameter(Mandatory=$true)]
        [string]$packageListPath,
        [Object]$repoContext,
        [String]$pythonPath,
        [Bool]$installFromRepo=$true,
        [String]$logtag = "INSTALL-PYTHONPIPLIST"
    )

    $pipListFile = ""

    #Check if we are installing from the repo or from a local file (e.g. downloaded as part of a set of build scripts)
    if ($installFromRepo) {
        #Download the pipPackageList file
        $filedata = Get-FileFromRepo $repoContext $packageListPath
        $filename = $filedata.filename

        if (-Not $filedata.downloadSuccess) {
            Write-Log "Error getting PIP Package List file file from repo: $packageListPath" -logtag $logtag -type "ERROR"
            return $false
        }

        $pipListFile = "C:\BuildScripts\Software\$($filename)"

    } else {
        Write-Log "Installing PIP List file from local file: $packageListPath" -logtag $logtag
        if (-Not (Test-Path $packageListPath)) {
            Write-Log "PIP List file does not exist: $packageListPath" -logtag $logtag -type "ERROR"
            return $false
        }
        $pipListFile = $packageListPath
    }

    
    #Call Install-PythonPip with the path to the downloaded package file
    Write-Log "Installing PIP List file $pipListFile" -logtag $logtag
    $result = Install-PythonPip -package "-r $pipListFile" -pythonPath $pythonPath -logtag $logtag

    if (-Not $result) {
        Write-Log "Error installing PIP List file $pipListFile" -logtag $logtag -type "ERROR"
        return $false
    }

    return $true

}


<#
    .SYNOPSIS
    Installs a Chocolatey package

    .NOTES
    Will automatically install Chocolatey if not found on the system

    .INPUTS
    package - The name of the Chocolatey package to install (see https://community.chocolatey.org/packages)
    parameters - Any parameters to pass to the Chocolatey install (optional)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the Chocolatey package was successfully installed

    .EXAMPLE
    Install-ChocoPackage -package "7zip"
#>
function Install-ChocoPackage {
    param (
        [Parameter(Mandatory=$true)]
        [String]$package,
        [String]$parameters = "",
        [String]$installArgs = "",
        [boolean]$ignoreChecksum = $false,
        [String]$logtag = "INSTALL-CHOCO"
    )

    #First check if Chocolately has been installed
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Chocolatey" -logtag $logtag
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString("https://chocolatey.org/install.ps1"))
    }

    Write-Log "Installing Chocolatey Package $package" -logtag $logtag

    #Install the package
    try {
        Write-Log "RUN: choco install $package -y -r --no-progress --ignore-package-exit-codes"  -logtag $logtag
        if ($ignoreChecksum) {
            Write-Log "Checksum Ignored for this package" -logtag $logtag -type "WARNING"
            choco install $package -y -r --no-progress --ignore-package-exit-codes --params="'$($parameters)'" --install-arguments="'$($installArgs)'" --ignore-checksums
        } else {
            choco install $package -y -r --no-progress --ignore-package-exit-codes --params="'$($parameters)'" --install-arguments="'$($installArgs)'"
        }
    }
    catch {
        Write-Log "Error installing Chocolatey Package $package" -logtag $logtag -type "ERROR"
        return $false
    }

    return $true
}

<#
    .SYNOPSIS
    Installs a list of Chocolatey packages from a text file

    .INPUTS
    packageListPath - The path to the text file in the container OR the local file path
    repoContext - The repo context object (required for downloading from the repo)
    installFromRepo - Whether to install from the repo (default is true)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the Chocolatey packages were successfully installed

    .EXAMPLE
    Install-ChocoPackageList -packageListPath "c:\BuildScripts\chocoPackageList.txt" -installFromRepo $false
    Install-ChocoPackageList -repoContext $repoContext -packageListPath "Packages\chocoPackageList.txt"
#>
function Install-ChocoPackageList {
    param (
        [Parameter(Mandatory=$true)]
        [String]$packageListPath,
        [Object]$repoContext,
        [Bool]$installFromRepo = $true,
        [String]$logtag = "INSTALL-CHOCO"
    )

    #First check if Chocolately has been installed
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Chocolatey" -logtag $logtag
        Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString("https://chocolatey.org/install.ps1"))
        
        #Check to see if choco is now installed
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Log "Error installing Chocolatey" -logtag $logtag -type "ERROR"
            return $false
        }
    }

    $packageFilePath = ""
    if ($installFromRepo) {
        #Get the package list from the repo
        $filedata = Get-FileFromRepo $repoContext $packageListPath
        $packageFile = $filedata.filename

        if (-Not $filedata.downloadSuccess) {
            Write-Log "Error getting Chocolatey XML file from repo: $packageListPath" -logtag $logtag -type "ERROR"
            return $false
        }

        $packageFilePath = "C:\BuildScripts\Software\$($packageFile)"

    } else {
        Write-Log "Getting Choco List file from local file: $packageListPath" -logtag $logtag

        if (-Not (Test-Path $packageListPath)) {
            Write-Log "Error getting Chocolatey XML file from local file: $packageListPath" -logtag $logtag -type "ERROR"
            return $false
        }
        
        $packageFilePath = $packageListPath
    }

    Write-Log "Installing Chocolatey Packages from XML file $packageFile" -logtag $logtag

    #Install the file
    try {
        Write-Log "RUN: choco install '$packageFilePath' -y -r --no-progress --ignore-package-exit-codes" -logtag $logtag
        choco install $packageFilePath -y -r --no-progress --ignore-package-exit-codes
    } catch {
        Write-Log "Error installing Chocolatey Packages from XML: $packageFilePath" -logtag $logtag -type "ERROR"
        return $false
    }

    return $true
}

#based on the fginction by Jeff Hicks - https://github.com/jdhitsolutions/WingetTools
function Install-WinGet {
    param (
        [String]$logtag = "INSTALL-WINGET"
    )

    #Check for VCLibs
    $requirement = Get-AppPackage Microsoft.VCLibs.140.00.UWPDesktop

    #Install them if not found
    if (-Not $requirement) {
        Write-Log "Installing Desktop App requirement" -logtag $logTag
        Try {
            $vclib = Join-Path -Path $env:temp -ChildPath "Microsoft.VCLibs.x64.14.00.Desktop.appx"
            Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -UseBasicParsing -OutFile $vclib -ErrorAction stop
            if (Test-Path $vclib) {
                Add-AppxPackage -Path $vclib -ErrorAction Stop
            }
            else {
                Write-Log "Failed to find $vclib" -logtag $logTag -type "ERROR"
                Throw "Failed to find $vclib"
            }
        }
        Catch {
            Throw $_
        }
    }

    #Set the URI for getting the latest winget version
    $uri = "https://api.github.com/repos/microsoft/winget-cli/releases"

    Try {
        #Determine the latest version
        Write-Log "Getting information from $uri" -logtag $logTag
        $get = Invoke-RestMethod -Uri $uri -Method Get -ErrorAction stop
        $data = ($get | where-object {-Not $_.Prerelease} | Select-Object -first 1).Assets | Where-Object name -Match 'msixbundle'

        #Get the URL of the latest version
        $appx = $data.browser_download_url

        #Download the latest version of Winget
        If ($pscmdlet.ShouldProcess($appx, "Downloading asset")) {
            $file = Join-Path -Path $env:temp -ChildPath $data.name
            Invoke-WebRequest -Uri $appx -UseBasicParsing -DisableKeepAlive -OutFile $file
            Add-AppxPackage -Path $file -ErrorAction Stop

            Get-AppxPackage microsoft.desktopAppInstaller
        }
    } Catch {
        Write-Log "There was an error downloading or installing the WinGet Application" -logtag $logTag -type "ERROR"
        Throw $_
    }  
}

<#
    .SYNOPSIS
    Installs a Winget package

    .NOTES
    Will try and install the Winget 3rd party module if not found on the system - this is not always reliable though

    .INPUTS
    package - The name of the Winget package to install (see https://winget.run/)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the Winget package was successfully installed

    .EXAMPLE
    Install-WingetPackage -package "Microsoft.VisualStudioCode"
#>

function Install-WingetPackage {
    param (
        [Parameter(Mandatory=$true)]
        [String]$package,
        [String]$logtag = "INSTALL-WINGET"
    )

    #First check if Winget has been installed
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Winget" -logtag $logtag
        # #This is a third party module, not a microsoft official one though it is part of PSGallery. https://www.powershellgallery.com/packages/WingetTools
        # Install-Module -Name WingetTools -Scope CurrentUser -Repository PSGallery -Force
        # Install-WinGet
        Install-WinGet
    }

    Write-Log "Installing Winget Package $package" -logtag $logtag

    #Install the package
    try {
        Write-Log "RUN: winget install $package" -logtag $logtag
        winget install $package
    }
    catch {
        Write-Log "Error installing Winget Package $package" -logtag $logtag -type "ERROR"
        return $false
    }

    return $true
}

<#
    .SYNOPSIS
    Installs a list of Winget packages from a JSON file

    .NOTES
    Will try and install the Winget 3rd party module if not found on the system - this is not always reliable though

    .INPUTS
    packageListPath - The path to the JSON file in the container OR the local file path
    repoContext - The repo context object (required for downloading from the repo)
    installFromRepo - Whether to install from the repo (default is true)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the Winget packages were successfully installed

    .EXAMPLE
    Install-WingetPackageList -packageListPath "c:\BuildScripts\wingetPackageList.json" -installFromRepo $false
    Install-WingetPackageList -packageListPath "Packages\wingetPackageList.json" -repoContext $repoContext
#>
function Install-WingetPackageList {
    param (
        [Parameter(Mandatory=$true)]
        [String]$packageListPath,
        [Object]$repoContext,
        [Bool]$InstallFromRepo = $true,
        [String]$logtag = "INSTALL-WINGET"
    )

    #First check if Winget has been installed
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Winget" -logtag $logtag
        #This is a third party module, not a microsoft official one though it is part of PSGallery. https://www.powershellgallery.com/packages/WingetTools
        Install-Module -Name WingetTools -Scope CurrentUser -Repository PSGallery -Force
        Install-WinGet

        #Check again to see if winget is installed
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Log "Error installing Winget" -logtag $logtag -type "ERROR"
            return $false
        }
    }

    Write-Log "Installing Winget Packages from JSON file $packageListPath" -logtag $logtag
    
    $jsonFilePath = ""
    if ($installFromRepo) {
        #Get the file from the repo
        $filedata = Get-FileFromRepo $repoContext $packageListPath
        $jsonFile = $filedata.filename
        if (-Not $filedata.downloadSuccess) {
            Write-Log "Error getting Winget Package file from repo: $packageListPath" -logtag $logtag -type "ERROR"
            return $false
        }
        $jsonFilePath = "C:\BuildScripts\Software\$($jsonFile)"
    } else {

        Write-Log "Getting Winget Package file from local file: $packageListPath" -logtag $logtag

        if (-Not (Test-Path $packageListPath)) {
            Write-Log "Error getting Winget JSON file from local file: $packageListPath" -logtag $logtag -type "ERROR"
            return $false
        }
        
        $jsonFilePath = $packageListPath
    }

    #Install the file
    try {
        Write-Log "RUN: winget import '$jsonFilePath'" -logtag $logtag
        winget import $jsonFilePath
    } catch {
        Write-Log "Error installing Winget Packages from JSON: $jsonFilePath" -logtag $logtag -type "ERROR"
        return $false
    }

    return $true
}

<#
    .SYNOPSIS
    Installs a PowerShell module

    .NOTES
    Will try and install the PowerShellGet module if not found on the system
    Generally will use the PSGallery repository, but can be overridden

    .INPUTS
    moduleName - The name of the PowerShell module to install
    scope - The scope to install the module to (CurrentUser or AllUsers) (default is CurrentUser)
    repository - The repository to install the module from (default is PSGallery)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the PowerShell module was successfully installed

    .EXAMPLE
    Install-PowerShellModule -moduleName "Az" -scope "CurrentUser" -repository "PSGallery"
#>
function Install-PowerShellModule {
    param (
        [String]$moduleName,
        [String]$scope = "AllUsers",
        [String]$repository = "PSGallery",
        [String]$logtag = "INSTALL-MODULE"
    )

    if (Get-Module -Name $moduleName -ListAvailable) {
        Write-Log "Module is already installed -Skipping" -logtag $logtag
        return $true
    }

    #Some modules need NuGet, so lets make sure it is installed
    if (-Not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Log "NuGet not found - installing" -logtag $logtag
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
      }

    Write-Log "Installing PowerShell Module $moduleName" -logtag $logtag

    #Install the module
    Write-Log "RUN: Install-Module -Name $moduleName -Scope $scope -Repository $repository -AllowClobber -AcceptLicense -Force" -logtag $logtag
    
    $err = $null
    Install-Module -Name $moduleName -Scope $scope -Repository $repository -Force -ErrorVariable err

    if ($err) {
        Write-Log "Error installing PowerShell Module $moduleName" -logtag $logtag -type "ERROR"
        Write-Log " - Error Generated: $err" -logtag $logtag -type "ERROR"
        return $false

    } else {
        Write-Log "Successfully installed PowerShell Module $moduleName" -logtag $logtag
    }

    return $true
}

<#
    .SYNOPSIS
    Installs a Windows Capability e.g. DNS tools

    .NOTES
    Will try and install the Windows Capability if not found on the system
    Get a list of capabilities that can be installed use: Get-WindowsCapability -Online | Select-Object -Property Name

    .INPUTS
    capabilityName - The name of the Windows Capability to install (e.g. Rsat.Dns)

    .OUTPUTS
    Returns True or False depending on whether the Windows Capability was successfully installed

    .EXAMPLE
    Install-WindowsCapability -capabilityName "Rsat.Dns"
#>
function Install-WindowsCapability {
    param (
        [Parameter(Mandatory=$true)]
        [String]$capabilityName,
        [String]$logtag = "INSTALL-WINDOWS-CAPABILITY"
    )

    Write-Log "Installing Windows Capability $capabilityName" -logtag $logtag

    #Install the capability
    Write-Log "RUN: Add-WindowsCapability -Name $capabilityName -Online" -logtag $logtag
    $err = $null
    Add-WindowsCapability -Name $capabilityName -Online -ErrorVariable err
    
    if ($err) {
        Write-Log "Error installing Windows Capability $capabilityName" -logtag $logtag -type "ERROR"
        Write-Log " - Error Generated: $err" -logtag $logtag -type "ERROR"
        return $false

    } else {
        Write-Log "Windows Capability $capabilityName installed successfully" -logtag $logtag
    }

    return $true
}

<#
    .SYNOPSIS
    Downloads a file from the Repo and places it a destination path (unzipping if required)

    .NOTES
    This is a Repo Only function

    .INPUTS
    repoContext - The Repo Context object
    repoPath - The path to the file in the Repo container
    destinationPath - The path to place the file
    unzip - If the file is a zip file, unzip it to the destination path (default is false)
    logtag - The tag used to identify this function in the log (optional)

    .OUTPUTS
    Returns True or False depending on whether the file was successfully downloaded

    .EXAMPLE
    Import-FileFromRepo -repoContext $repoContext -repoPath "Software\Files\thing.zip" -destinationPath "C:\LocalFiles\thing.zip" -unzip $true
#>
function Import-FileFromRepo {
    param (
        [Parameter(Mandatory=$true)]
        [Object]$repoContext,
        [Parameter(Mandatory=$true)]
        [String]$repoPath,
        [Parameter(Mandatory=$true)]
        [String]$destinationPath,
        [String]$unzip = $false,
        [String]$logtag = "DEPLOY-FILE"
    )

    Write-Log "Downloading $repoPath to $destination" -logtag $logtag

    #Get the file from the repo
    $filedata = Get-FileFromRepo $repoContext $repoPath
    $file = $filedata.filename

    if (-Not $filedata.downloadSuccess) {
        Write-Log "Error getting file from repo: $repoPath" -logtag $logtag -type "ERROR"
        return $false
    }

    #Check if the destinationPath is a file and get just the directory part
    if (Test-Path $destinationPath -PathType Leaf) {
        $destinationPath = Split-Path $destinationPath
    }

    #Check if the destination path exists and create it if not
    if (-Not (Test-Path $destinationPath)) {
        Write-Log "Create destination directory: $destinationPath" -logtag $logtag
        New-Item -ItemType Directory -Path $destinationPath -Force
    }

    if ($unzip) {
        #Unzip the file to its required destination
        try {
            Write-Log "RUN: Expand-Archive -Path 'C:\BuildScripts\Software\$file' -DestinationPath $destinationPath" -logtag $logtag
            Expand-Archive -Path "C:\BuildScripts\Software\$file" -DestinationPath $destinationPath
        } catch {
            Write-Log "Error unzipping file: $file" -logtag $logtag -type "ERROR"
            return $false
        }
    } else {
        #Move the file to its required destination
        try {
            Write-Log "RUN: Copy-Item -Path 'C:\BuildScripts\Software\$file' -Destination $destinationPath" -logtag $logtag
            Move-Item -Path "C:\BuildScripts\Software\$file" -Destination $destinationPath
        } catch {
            Write-Log "Error moving file: $file" -logtag $logtag -type "ERROR"
            return $false
        }
    }

    return $true
}

<#
    .SYNOPSIS
    Creates a local registry entry

    .INPUTS
    key - The registry key to create
    valueName - The name of the value to create
    value - The value to set
    valueType - The type of the value (default is String)
    logtag - The tag used to identify this function in the log (optional)

    .EXAMPLE
    Add-RegistryEntry "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\MyApp" "DisplayName" "My App" "String"
#>
function Add-RegistryEntry {
    param (
        [String]$key,
        [String]$valueName,
        [String]$value,
        [String]$valueType = "String",
        [String]$logtag = "ADD-REGISTRY-ENTRY"
    )

    Write-Log "Adding Registry Entry $key\$valueName" -logtag $logtag

    #Check if the key exists
    if (-Not (Test-Path $key)) {
        Write-Log "RUN: New-Item -Path $key" -logtag $logtag
        New-Item -Path $key
    }

    #Add the value
    try {
        Write-Log "RUN: Set-ItemProperty -Path $key -Name $valueName -Value $value" -logtag $logtag
        Set-ItemProperty -Path $key -Name $valueName -Value $value
    } catch {
        Write-Log "Error adding Registry Entry $key\$valueName" -logtag $logtag -type "ERROR"
        return $false
    }

    return $true
}

<#
    .SYNOPSIS
    Writes a message to the local log file and output to Packer/Screen

    .INPUTS
    message - The message to write to the log
    type - The type of message (INFO, ERROR, WARNING) (default is INFO)
    logtag - The tag used to identify this function in the log (optional)
    writeLog - Write the message to the local log file (default is true)
    writeToPacker - Write the message to Packer/Screen (default is true)

    .EXAMPLE
    Write-Log "This is a message"
    Write-Log "This is a message" -type "WARN" -logtag "MYNOTE" -writeLog $true -writeToPacker $true
#>
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [String]$message,
        [String]$type = "INFO",
        [String]$logtag = "LOG",
        [String]$writeLog = $true,
        [String]$writeToPacker = $true
    )

    #Write to the Log File stored in the VM image
    if ($writeLog) {
        #Create a local Log folder on the C Drive
        $logFolder = "C:\BuildLogs"
        if (!(Test-Path $logFolder)) {
            New-Item -ItemType Directory -Force -Path $logFolder
        }

        #Open the log file for append
        $logFile = "$logFolder\InstallSoftware.log"

        #Write the message to the log file
        if (($type).ToUpper() -ne "INFO") {
            Add-Content $logFile "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss"): $logtag - $(($type).ToUpper()) - $message"
        } else {
            Add-Content $logFile "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss"): $logtag - $message"
        }
    }

    #Write to Packer log (capture of host output)
    if ($writeToPacker) {
        if (($type).ToUpper() -ne "INFO") {
            Write-Host "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss"): $logtag - $(($type).ToUpper()) - $message"
        } else {
            Write-Host "$(Get-Date -Format "yyyy-MM-dd HH:mm:ss"): $logtag - $message"
        }
    }
}

#Exports of the modules
Export-ModuleMember -Function Get-RepoContext
Export-ModuleMember -Function Install-MSI
Export-ModuleMember -Function Install-EXE
Export-ModuleMember -Function Install-VSIX

Export-ModuleMember -Function Install-ChocoPackage
Export-ModuleMember -Function Install-ChocoPackageList
Export-ModuleMember -Function Install-WingetPackage
Export-ModuleMember -Function Install-WingetPackageList

Export-ModuleMember -function Install-PythonPip
Export-ModuleMember -function Install-PythonPipList


Export-ModuleMember -Function Install-PowerShellModule
Export-ModuleMember -Function Install-WindowsCapability
Export-ModuleMember -Function Import-FileFromRepo
Export-ModuleMember -Function Add-RegistryEntry

Export-ModuleMember -Function Write-Log
