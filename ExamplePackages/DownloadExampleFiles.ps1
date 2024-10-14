
<#
.SYNOPSIS
    Downloads example files from specified URLs.

.DESCRIPTION
    This script downloads example files from specified URLs using the Invoke-WebRequest cmdlet. It saves the downloaded 
    files to the current directory with the specified output filenames.

.EXAMPLE
    .\DownloadExampleFiles.ps1

.NOTES
    This is an example only.  It is not a production script.  Microsoft accepts no liability for the content or use of this script.
#>

#Download 7Zip MSI
$Url = "https://www.7-zip.org/a/7z2408-x64.msi"
$Output = "7z2408-x64.msi"
Invoke-WebRequest -Uri $Url -OutFile $Output

#Download KDIFF EXE
$Url = "https://download.kde.org/stable/kdiff3/kdiff3-1.11.4-windows-64-cl.exe"
$Output = "kdiff3-1.11.4-windows-64-cl.exe"
Invoke-WebRequest -Uri $Url -OutFile $Output

