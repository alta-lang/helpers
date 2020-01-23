#!/usr/bin/env pwsh
#requires -PSEdition Core

# MIT License
#
# Copyright (c) 2020 Alta Project Contributors
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

<#

.SYNOPSIS
Downloads the Alta compiler for a given platform

.DESCRIPTION
This function will download the Alta compiler for a given platform (i.e. system + architecture).
It requires internet access, since it needs to download the compiler from SourceForge.

.PARAMETER Version
The version of the compiler to download. Can be either a SemVer version (e.g. "1.0.0"), a short commit hash (e.g. "abc123d"), or "latest". Defaults to "latest".

.PARAMETER DestinationDirectory
The directory to extract the compiler to. Will be created if it does not exist. If it does already exist, a warning will be shown. Defaults to "altac" in the current working directory.

.PARAMETER TemporaryDirectory
The directory to download the compiler archive to. Will be created if it does not exist. Defaults to the system's temporary directory (e.g. `/tmp` on macOS/Linux, `C:\Users\<username>\AppData\Local\Temp` on Windows).

.PARAMETER Silent
If provided, Get-AltaCompiler will output nothing to the console, only returning the path of the downloaded compiler executable.

.PARAMETER Force
By default, Get-AltaCompiler will not overwrite existing files. This switch tells the function to overwrite any existing files.

.PARAMETER Always
By default, Get-AltaCompiler will check if `version.txt` already exists in the destination directory. If it does, it will check if the version listed in it matches the requested version and, if they match, it won't redownload the compiler. This switch tells Get-AltaCompiler to always redownload the compiler, regardless of the presence or contents of `version.txt`.

.PARAMETER SystemName
By default, Get-AltaCompiler will try to determine the current system name and download the compiler for it. This flag overrides that behavior and tells Get-AltaCompiler to download the compiler for the specified system. Valid values for this flag are "macos", "linux", and "windows".

.PARAMETER ArchitectureName
By default, Get-AltaCompiler will try to determine the current architecture name and download the compiler for it. This flag overrides that behavior and tells Get-AltaCompiler to download the compiler for the specified architecture. Valid values for this flag are "arch64" and "arch32".

.INPUTS
None.

.OUTPUTS
System.String. Returns the path to the downloaded Alta compiler executable

.EXAMPLE
Get-AltaCompiler # downloads the compiler for the current platform

.EXAMPLE
Get-AltaCompiler -SystemName linux # downloads the compiler for Linux

.EXAMPLE
Get-AltaCompiler -ArchitectureName arch64 # downloads the 64-bit version of the compiler for the current system

.EXAMPLE
Get-AltaCompiler -DestinationDirectory ../my-alta-compiler # extracts the compiler to a directory called "my-alta-compiler" in the parent directory

.EXAMPLE
Get-AltaCompiler -Force # overwrite any files already present

.LINK
https://github.com/alta-lang/alta

#>
function Get-AltaCompiler {
  [CmdletBinding(PositionalBinding=$False)]
  [OutputType([string])]
  param(
    [Parameter(Position = 0)]
    [string]
    $Version = "latest",
    [Parameter(Position = 1)]
    [string]
    $DestinationDirectory = "$(Get-Location)/altac",
    [string]
    $TemporaryDirectory = [IO.Path]::GetTempPath(),
    [switch]
    $Silent = [switch]$False,
    [switch]
    $Force = [switch]$False,
    [switch]
    $Always = [switch]$False,
    [string]
    $SystemName = "unknown",
    [string]
    $ArchitectureName = "unknown"
  )

  # parameter parsing
  $DestinationDirectory = [IO.Path]::GetFullPath($DestinationDirectory)
  $TemporaryDirectory = [IO.Path]::GetFullPath($TemporaryDirectory)
  $SystemName = $SystemName.ToLower()
  $ArchitectureName = $ArchitectureName.ToLower()

  if ($SystemName -match "^((mac *(os)?)|(os *x)|(apple))$") {
    $SystemName = "macos"
  } elseif ($SystemName -match "^((linux)|(ubuntu)|(fedora)|(debian))$") {
    $SystemName = "linux"
  } elseif ($SystemName -match "^(windows *(32|64|10)?|win *(32|64|10)?|nt|microsoft|ms)$") {
    $SystemName = "windows"
  } elseif ($SystemName -ne "unknown") {
    throw "Unrecognized system name: $SystemName. Expecting ""macos"", ""linux"", or ""windows"""
  }

  if ($ArchitectureName -match "^((arch|x|amd)?64( *\-? *bits?)?)$") {
    $ArchitectureName = "arch64"
  } elseif ($ArchitectureName -match "^((arch|x)?32( *\-? *bits?)?|i386|x86)$") {
    $ArchitectureName = "arch32"
  } elseif ($ArchitectureName -ne "unknown") {
    throw "Unrecognized architecture name: $ArchitectureName. Expecting ""arch64"" or ""arch32"""
  }

  # constants
  [string]$BaseURL = "https://sourceforge.net/projects/alta-builds/files"
  [string]$ReleaseListURL = "https://gist.github.com/facekapow/5f8290dae9b1971bf13cf1dbc0e87021/raw"

  # variables
  [string]$FriendlySystemName = "Unknown"
  [string]$FriendlyArchitectureName = "Unknown"
  [bool]$IsAutomated = $False
  [string]$DownloadURL = $BaseURL

  # determine os name (if necessary)
  if ($SystemName -eq "unknown") {
    if ($IsMacOS) {
      $SystemName = "macos"
    } elseif ($IsLinux) {
      $SystemName = "linux"
    } elseif ($IsWindows) {
      $SystemName = "windows"
    } else {
      throw "Unrecognized system!"
    }
  }

  if ($SystemName -eq "macos") {
    $FriendlySystemName = "macOS"
  } elseif ($SystemName -eq "linux") {
    $FriendlySystemName = "Linux"
  } elseif ($SystemName -eq "windows") {
    $FriendlySystemName = "Windows"
  } else {
    throw "Unrecognized system name!"
  }

  # determine architecture name
  if ($ArchitectureName -eq "unknown") {
    if ([System.IntPtr]::Size -eq 8) {
      $ArchitectureName = "arch64"
    } else {
      $ArchitectureName = "arch32"
    }
  }

  if ($ArchitectureName -eq "arch64") {
    $FriendlyArchitectureName = "64-bit"
  } elseif ($ArchitectureName -eq "arch32") {
    $FriendlyArchitectureName = "32-bit"
  } else {
    throw "Unrecognized architecture name!"
  }

  # validate directories and ensure they exist
  if (Test-Path $DestinationDirectory) {
    if (-not (Test-Path $DestinationDirectory -PathType Container)) {
      throw "Destination path is not a directory"
    }
    if ((-not $Silent) -and ((Get-ChildItem $DestinationDirectory -Force | Measure-Object).Count -ne 0)) {
      Write-Warning "Destination directory is not empty"
    }
  } else {
    $Null = New-Item -Path $DestinationDirectory -ItemType Container
  }
  if (-not (Test-Path $TemporaryDirectory)) {
    $Null = New-Item -Path $TemporaryDirectory -ItemType Container
  }

  # determine the correct version
  if ($Version -eq "latest") {
    $Releases = Invoke-WebRequest $ReleaseListURL | ConvertFrom-Json
    $IsAutomated = $False

    [System.Management.Automation.SemanticVersion]$GreatestVersion = $Null
    foreach ($Release in $Releases) {
      if ($Null -eq $GreatestVersion) {
        $GreatestVersion = $Release
      } elseif ($Release -gt $GreatestVersion) {
        $GreatestVersion = $Release
      }
    }

    if ($Null -eq $GreatestVersion) {
      throw "Latest version not found!"
    }

    $Version = $GreatestVersion
  } elseif (($Version -match "^v?[0-9]+\.[0-9]+.[0-9]+$") -or ($Version -match "^v?[0-9]+\.[0-9]+$") -or ($Version -match "^v?[0-9]+$")) {
    if ($Version[0] -eq "v") {
      $Version = $Version.Substring(1)
    }
    $Releases = Invoke-WebRequest $ReleaseListURL | ConvertFrom-Json
    $IsAutomated = $False

    [System.Management.Automation.SemanticVersion[]]$Candidates = @()
    foreach ($Release in $Releases) {
      if ($Release.Substring(0, $Version.Length) -eq $Version) {
        $Candidates += $Release
      }
    }

    [System.Management.Automation.SemanticVersion]$GreatestVersion = $Null
    foreach ($Candidate in $Candidates) {
      if ($Null -eq $GreatestVersion) {
        $GreatestVersion = $Candidate
      } elseif ($Candidate -gt $GreatestVersion) {
        $GreatestVersion = $Candidate
      }
    }

    if ($Null -eq $GreatestVersion) {
      throw "Version not found! (version provided was ""v$Version"")"
    }

    $Version = $GreatestVersion
  } elseif ($Version -match "^[a-z0-9]{7}$") {
    $IsAutomated = $True
  } else {
    throw "Invalid version! (version provided was ""$Version"")"
  }

  [string]$VersionTextFilePath = Join-Path -Path $DestinationDirectory -ChildPath "version.txt"

  if ((-not $Always) -and (Test-Path -LiteralPath $VersionTextFilePath -PathType Leaf)) {
    $Content = (Get-Content -LiteralPath $VersionTextFilePath).Trim()
    if ($Content -eq "$Version-$SystemName-$ArchitectureName") {
      if (-not $Silent) {
        Write-Host "Alta compiler in destination directory is already up to date (use the ""-Always"" switch to force it to be redownloaded)"
      }
      if ($SystemName -eq "windows") {
        return Join-Path -Path $DestinationDirectory -ChildPath "altac.exe"
      } elseif (($SystemName -eq "macos") -or ($SystemName -eq "linux")) {
        return Join-Path -Path $DestinationDirectory -ChildPath "bin/altac"
      } else {
        throw "Unrecognized system!"
      }
    }
  }

  # build the url
  $DownloadURL += "/"
  $DownloadURL += if ($IsAutomated) { "automated" } else { "release" }

  $DownloadURL += "/"
  $DownloadURL += $Version

  $DownloadURL += "/"
  $DownloadURL += "altac-$Version-$SystemName-$ArchitectureName.zip"

  $DownloadURL += "/"
  $DownloadURL += "download"

  if (-not $Silent) {
    Write-Host "Downloading the Alta compiler for $FriendlySystemName ($FriendlyArchitectureName)..."
  }

  # download it!
  [string]$ArchivePath = Join-Path -Path $TemporaryDirectory -ChildPath "altac-$Version-$SystemName-$ArchitectureName.zip"

  try {
    $OldProgressPreference = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"
    $Null = Invoke-WebRequest -Uri $DownloadURL -OutFile $ArchivePath -UserAgent "NativeHost"
    $ProgressPreference = $OldProgressPreference
  } catch [System.Net.WebException] {
    if ([int]$_.Exception.Response.BaseResponse.StatusCode -eq 404) {
      throw "Build archive not found for the desired version ($Version)"
    } else {
      throw "Encountered HTTP error while fetching build archive: $([int]$_.Exception.Response.BaseResponse.StatusCode) - $($_.Exception.Response)"
    }
  }

  if (-not $Silent) {
    Write-Host "Extracting the compiler from the archive..."
  }

  [string[]]$ExtractedFiles = @()

  if ($IsWindows) {
    $ExpandArchiveParameters = @{
      "DestinationPath" = $DestinationDirectory
    }
    if ($Force) {
      $ExpandArchiveParameters["Force"] = [switch]$True
    }
    [System.IO.FileSystemInfo[]]$EAFiles = Microsoft.PowerShell.Archive\Expand-Archive @ExpandArchiveParameters -LiteralPath $ArchivePath -PassThru
    foreach ($EAFile in $EAFiles) {
      $ExtractedFiles += $EAFile.FullName
    }
  } else {
    [string]$UFiles = unzip -Z1 $ArchivePath

    if ($UFiles.IndexOf("`n") -ne -1) {
      $ExtractedFiles = $UFiles.Trim() -split "`n"
    } else {
      $ExtractedFiles = $UFiles.Trim() -split " "
    }

    for ($i = 0; $i -lt $ExtractedFiles.Length; ++$i) {
      $ExtractedFiles[$i] = Join-Path -Path $DestinationDirectory -ChildPath $ExtractedFiles[$i]
    }

    if ($Force) {
      $Null = unzip -n $ArchivePath -d $DestinationDirectory
    } else {
      $Null = unzip -o $ArchivePath -d $DestinationDirectory
    }
  }

  if ($ExtractedFiles.Length -gt 0) {
    [string]$File = $ExtractedFiles[0]
    [string]$BaseName = $File.Substring($DestinationDirectory.Length + 1)
    [string]$RemovableDirectoryName = $Null
    if ($BaseName.IndexOf([IO.Path]::DirectorySeparatorChar) -lt 0) {
      $RemovableDirectoryName = $BaseName
    } else {
      if ($ExtractedFiles.Length -lt 2) {
        throw "Could not determine removable directory name!"
      }
      $File = $ExtractedFiles[1]
      $BaseName = $File.Substring($DestinationDirectory.Length + 1)
      $RemovableDirectoryName = $BaseName.Substring(0, $BaseName.IndexOf([IO.Path]::DirectorySeparatorChar))
    }
    [string]$RemovableDirectoryPath = Join-Path -Path $DestinationDirectory -ChildPath $RemovableDirectoryName

    $MoveItemParameters = @{
      "Destination" = $DestinationDirectory
    }
    if ($Force) {
      $MoveItemParameters["Force"] = [switch]$True
    }

    [string[]]$RemoveableDirectoryChildren = Get-ChildItem -LiteralPath $RemovableDirectoryPath -Name

    foreach ($Child in $RemoveableDirectoryChildren) {
      $Null = Move-Item -LiteralPath (Join-Path -Path $RemovableDirectoryPath -ChildPath $Child) @MoveItemParameters
    }

    $Null = Remove-Item -LiteralPath $RemovableDirectoryPath
  }

  "$Version-$SystemName-$ArchitectureName" > $VersionTextFilePath

  if ($SystemName -eq "windows") {
    return Join-Path -Path $DestinationDirectory -ChildPath "altac.exe"
  } elseif (($SystemName -eq "macos") -or ($SystemName -eq "linux")) {
    return Join-Path -Path $DestinationDirectory -ChildPath "bin/altac"
  } else {
    throw "Unrecognized system!"
  }
}
