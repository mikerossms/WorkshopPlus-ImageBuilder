
#Download 7Zip MSI
$Url = "https://www.7-zip.org/a/7z2408-x64.msi"
$Output = "7z2408-x64.msi"
Invoke-WebRequest -Uri $Url -OutFile $Output

#Download KDIFF EXE
$Url = "https://download.kde.org/stable/kdiff3/kdiff3-1.11.4-windows-64-cl.exe"
$Output = "kdiff3-1.11.4-windows-64-cl.exe"
Invoke-WebRequest -Uri $Url -OutFile $Output

