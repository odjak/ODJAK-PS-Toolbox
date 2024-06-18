# Compress-7ZipFilesOlderThan -source "C:\Logs" -destination "D:\Archives" -olderThan "2018-01-01"
# Compress-ArchFilesOlderThan -source "C:\Logs" -destination "D:\Archives\Archive.zip" -olderThan "2018-01-01"
function main{
    begin{
        # Verify the powerhshell archive module is available
        if (-not (Get-Module -Name Microsoft.PowerShell.Archive -ListAvailable)) {
            Write-Host "The Microsoft.PowerShell.Archive module is not available. Attempting to install it..." -ForegroundColor Yellow
            Install-Module -Name Microsoft.PowerShell.Archive -Force -AllowClobber -Scope CurrentUser -ErrorAction SilentlyContinue
        }
        # Import the module
        Import-Module -Name Microsoft.PowerShell.Archive -ErrorAction SilentlyContinue
        # - Load the System.IO.Compression.FileSystem assembly if it is not already loaded
        if (-not ([System.Management.Automation.PSTypeName]'System.IO.Compression.FileSystem').Type) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
        }
        $source         = "C:\Logs"         # Accepts format: "C:\Logs"
        $destination    = "D:\Archives"     # Accepts format: "C:\Logs\Archive.zip" or "C:\Logs"
        $olderThan      = "2018-01-01"      # Accepts format: "yyyy-MM-dd HH:mm:ss" and "yyyy-MM-dd"
    }
    process{
        # - Process the script block for each input object
        # Example usage for reference:
        # Compress-ArchFilesOlderThan -source "C:\Logs" -destination "D:\Archives\Archive.zip" -olderThan "2018-01-01"
        # Compress-7ZipFilesOlderThan -source "C:\Logs" -destination "D:\Archives" -olderThan "2018-01-01"
        # Exammple usage for reference:
        # Compress-ArchFilesOlderThan -source "C:\Logs" -destination "D:\Archives\Archive.zip" -olderThan "2018-01-01"
        # Compress-7ZipFilesOlderThan -source "C:\Logs" -destination "D:\Archives" -olderThan "2018-01-01"
        Write-Host "Processing files..." -ForegroundColor Yellow -BackgroundColor Black
        Compress-7ZipFilesOlderThan -source $source -destination $destination -olderThan $olderThan
        Compress-ArchFilesOlderThan -source $source -destination "$destination\Archive.zip" -olderThan $olderThan
    }
    }
    end {
        # - Process the script block after all input objects have been processed
        Remove-Module -Name Microsoft.PowerShell.Archive -Force -ErrorAction SilentlyContinue

        Write-Host "Script completed." -ForegroundColor Green -BackgroundColor Black

    }
    # Uncomment main in bottom to run the script - Dont forgeet to change the source and destination paths as well as the olderThan date.

function Compress-7ZipFilesOlderThan {
    <#
    .SYNOPSIS
    Compresses files older than specified date.
    .DESCRIPTION
    Compresses files older than specified date. The function will create a zip file with the same directory structure as the source folder.
    .PARAMETER source
    The source folder to search for files.
    .PARAMETER destination
    The destination folder where the zip files will be created.
    .PARAMETER olderThan
    The date to compare the files' creation date to. Files older than this date will be compressed.
    .EXAMPLE
    Compress-FilesOlderThan -source "C:\Logs" -destination "D:\Archives" -olderThan "2018-01-01"
    Compresses files in "C:\Logs" folder that are older than "2018-01-01" and creates zip files in "D:\Archives" folder.
    .NOTES
    #>
    param(
        [string]$source,                # Accepts format: "C:\Logs"
        [string]$destination,           # Accepts format: "C:\Logs\Archive.zip" or "C:\Logs"
        [datetime]$olderThan            # Accepts format: "yyyy-MM-dd HH:mm:ss" and "yyyy-MM-dd"
    )
    $files = Get-ChildItem -Path $source -Recurse | Where-Object { $_.CreationTime -lt $olderThan }
    foreach($file in $files) {
        Write-Host "Processing file: $($file.FullName)" -ForegroundColor Yellow -BackgroundColor Black
        $relativePath   = $_.FullName.Substring($source.Length + 1)                     # - Get the relative path.
        $zipPath        = [System.IO.Path]::Combine($destination, $relativePath)        # - Combine the destination path with the relative path.
        $zipDir         = [System.IO.Path]::GetDirectoryName($zipPath)                  # - Get the directory name of the zip path.
        Write-Host "Relative path: $relativePath" -ForegroundColor Yellow -BackgroundColor Black
        Write-Host "Processed file: $($file.FullName)" -ForegroundColor Green -BackgroundColor Black
        

        # - Create directory if it doesn't exist
        if (-not (Test-Path $zipDir)) {
            try {
                Write-Host "Zip-File not found. Creating zip file: $zipPath" -ForegroundColor Yellow -BackgroundColor Black
                New-Item -ItemType Directory -Path $zipDir | Out-Null
                Write-Host "Zip-File created: $zipPath" -ForegroundColor Green -BackgroundColor Black
            } catch {
                Write-Host "Error creating directory: $zipDir $_.err "  -ForegroundColor Red -BackgroundColor Black
            }
        }

        # - Create the zip file - requires PowerShell 5.0 - Compress-Archive -Path $_.FullName -DestinationPath $zipPath -Force
        Compress-Archive -Path $_.FullName -DestinationPath $zipPath -Force
    }
}

function Compress-ArchFilesOlderThan{
    <#
    .SYNOPSIS
    Compresses files older than specified date.
    .DESCRIPTION
    Compresses files older than specified date. The function will create a zip file with the same directory structure as the source folder.
    .PARAMETER source
    The source folder to search for files.
    .PARAMETER destination
    The destination folder where the zip files will be created.
    .PARAMETER olderThan
    The date to compare the files creation date to. Files older than this date will be compressed.
    .EXAMPLE
    Compress-FilesOlderThan -source "C:\Logs" -destination "D:\Archives" -olderThan "2018-01-01"
    Compresses files in "C:\Logs" folder that are older than "2018-01-01" and creates zip files in "D:\Archives" folder.
    .NOTES
    #>
    param(
        [string]$source,                # Accepts format: "C:\Logs"
        [string]$destination,           # Accepts format: "C:\Logs\Archive.zip" or "C:\Logs"
        [datetime]$olderThan            # Accepts format: "yyyy-MM-dd HH:mm:ss" and "yyyy-MM-dd"
    )
    $arch = [System.IO.Compression.ZipFile]::Open($destination, [System.IO.Compression.ZipArchiveMode]::Update)
    $files = Get-ChildItem -Path $source -Recurse | Where-Object { $_.CreationTime -lt $olderThan }
    foreach($file in $files) {
        try{
            $relativePath = $_.FullName.Substring($source.Length + 1)
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($arch, $_.FullName, $relativePath)
        } catch {
            Write-Host "Error compressing file: $($_.FullName)"
        }
    }
    $arch.Dispose()
}
main
