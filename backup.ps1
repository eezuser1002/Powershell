# Detect 7zip installation
Write-Host "Checking if 7zip is installed..."
$regPaths = @(
    "HKLM:\SOFTWARE\7-Zip",
    "HKLM:\SOFTWARE\WOW6432Node\7-Zip"
)
$installPath = $regPaths | ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } | Select-Object -ExpandProperty Path64
if ($installPath -and (Test-Path "$installPath\7z.exe")) { "7zip Installed at" $installPath }

# Create a backup folder in the users profile directory
Write-Host "Creating the your backup directory: C:\Users\YOURPROFILE\Backups..."
$backupPath = New-Item -Path $env:USERPROFILE\Backups -ItemType Directory

# Target directories and/or files 
$selectedPaths = @()
do {
    $path = Read-Host "Enter full path (or 'done' to finish)"
    if ($path -ne 'done' -and (Test-Path $path)) { $selectedPaths += $path }
} while ($path -ne 'done')




# Copy over and compress the provided files/directories
foreach ($path in $selectedPaths) {
    $leaf = Split-Path $path -Leaf
    $zip = "$backupPath\$leaf.zip"
    if (Test-Path $path -PathType Leaf) {  # Single file
        Compress-Archive -Path $path -DestinationPath $zip -Force
    } else {  # Directory
        Compress-Archive -Path "$path\*" -DestinationPath $zip -Force
    }
}

# Encrypt selected files and/or directories
$encryption = Read-Host "Do you want to encrypt your backups? (Y/N)"
if ($encryption -eq "Y" -or $encryption -eq "y") {
    if ($installPath -and (Test-Path "$installPath\7z.exe")) {
        $password = Read-Host "Enter encryption password" -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        
        foreach ($zipFile in Get-ChildItem "$backupPath\*.zip") {
            $newName = $zipFile.BaseName + ".7z"
            & "$installPath\7z.exe" a -p"$plainPassword" "$backupPath\$newName" "$zipFile.FullName" -t7z -m0=lzma2
            Remove-Item $zipFile.FullName -Force
        }
        Write-Host "Encryption completed"
    } else {
        Write-Host "7-Zip not found, skipping encryption"
    }
} else {
    Write-Host "Skipping encryption. Backup completed."
}
