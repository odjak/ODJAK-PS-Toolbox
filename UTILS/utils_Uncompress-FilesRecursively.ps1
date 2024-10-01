function Uncompress-FilesRecursively {
    param (
        [string]$Directory = (Get-Location).Path
    )
    <#
    .SYNOPSIS
    Extracts all .zip and .rar files in a directory and its subdirectories.

    .DESCRIPTION
    This function extracts all .zip and .rar files in a specified directory and its subdirectories using 7-Zip.

    .PARAMETER Directory
    The directory in which to search for .zip and .rar files. Defaults to the current directory.

    .EXAMPLE
    Uncompress-FilesRecursively -Directory "C:\Path\To\Directory"

    Extracts all .zip and .rar files in the specified directory and its subdirectories.

    .NOTES

    
    #>

    # Define the default 7z executable path
    $sevenZipPath = "C:\Program Files\7-Zip\7z.exe"

    # Check if 7z executable exists
    if (-not (Test-Path $sevenZipPath)) {
        $sevenZipPath = "C:\Program Files (x86)\7-Zip\7z.exe"
        if (-not (Test-Path $sevenZipPath)) {
            Write-Host "7z.exe not found in default install paths. Please ensure 7-Zip is installed and the path is set correctly." -ForegroundColor Red
            return
        }
    }

    # Get all the .zip and .rar files in the directory and subdirectories
    $compressedFiles = Get-ChildItem -Path $Directory -Recurse -Include *.zip, *.rar

    foreach ($file in $compressedFiles) {
        try {
            # Determine the output directory (same as the archive file's directory)
            $outputDir = $file.DirectoryName

            # Extract the archive
            Write-Host "Extracting $($file.FullName) to $($outputDir)" -ForegroundColor Yellow
            & $sevenZipPath x $file.FullName -o$outputDir -y

            Write-Host "Successfully extracted $($file.FullName)" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to extract $($file.FullName). Error: $_" -ForegroundColor Red
        }
    }

    Write-Host "Extraction process complete." -ForegroundColor Cyan
}
