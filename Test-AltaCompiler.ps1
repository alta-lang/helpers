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
Tests the presence of the Alta compiler

.DESCRIPTION
This function checks if the Alta compiler is installed and, optionally, if it matches a specific version of the compiler.

.PARAMETER Version
An optional SemVer version to check the compiler version against. It must be in the format: "<major>.<minor>.<patch>", where <major>, <minor>, and <patch> are numbers.

.PARAMETER Commit
An optional 7-digit Git commit hash to check the compiler version against. If specified, it will take precedence over the `Version` parameter.

.PARAMETER Exact
This switch tells Test-AltaCompiler to make sure that the version exactly matches the input parameters. Commit checks are always exact (since commit builds can be drastically different), but by default, version checks follow the SemVer compatability check (i.e. must have same major version, but any minor or patch version greater than the input is accepted). With this switch, the compiler version and the input version must be exact matches.

.INPUTS
None.

.OUTPUTS
System.Boolean. Returns a boolean indicating if the compiler is present and matches the version parameters (if given).

.EXAMPLE
Test-AltaCompiler # checks if `altac` is installed and can be seen by the script (i.e. it is present on the PATH)

.EXAMPLE
Test-AltaCompiler -Commit 658edd9 # checks if build 658edd9 of the Alta compiler is installed

.EXAMPLE
Test-AltaCompiler -Version 0.6.3 # checks if version 0.6.3 of the compiler is installed (or a compatible version)

.EXAMPLE
Test-AltaCompiler -Verison 0.6.1 -Exact # checks if version 0.6.1 of the compiler is installed (and *only* version 0.6.1)

.LINK
https://github.com/alta-lang/helpers

#>

function Test-AltaCompiler {
  [OutputType([bool])]
  param(
    [string]
    $Version=$Null,
    [string]
    $Commit=$Null,
    [switch]
    $Exact=[switch]$False
  )

  # validate parameters
  if (-not ([string]::IsNullOrEmpty($Version))) {
    $Version = $Version.Trim()
    if ($Version -match "v?[0-9]+\.[0-9]+\.[0-9]+") {
      if ($Version[0] -eq "v") {
        $Version = $Version.Substring(1)
      }
    } else {
      throw "Invalid version! Expecting a valid SemVer version in the following form: ""<major>.<minor>.<patch>"", where <major>, <minor>, and <patch> are numbers"
    }
  }

  if (-not ([string]::IsNullOrEmpty($Commit))) {
    $Commit = $Commit.Trim()
    if ($Commit -cmatch "[A-Za-z0-9]{7}") {
      # do nothing
    } else {
      throw "Invalid commit! Expecting a short 7-digit Git commit hash (e.g. abc123d)"
    }
  }

  if ((-not ([string]::IsNullOrEmpty($Commit))) -and (-not ([string]::IsNullOrEmpty($Version)))) {
    Write-Warning "Both Commit and Version have been provided; only commit will be examined"
  }

  if (-not (Get-Command -Name altac -ErrorAction SilentlyContinue)) {
    return $False
  }

  if (([string]::IsNullOrEmpty($Commit)) -and ([string]::IsNullOrEmpty($Version))) {
    return $True
  }

  $AltaCompilerVersion = (altac --version).Trim()

  if (-not ($AltaCompilerVersion -cmatch "\((?<semver>[0-9]+\.[0-9]+\.[0-9]+)(?:-(?<commit>[A-Za-z0-9]+))?\)")) {
    throw "Internal compiler error (invalid version format)"
  }

  if ($Matches.commit) {
    if ([string]::IsNullOrEmpty($Commit)) {
      return $False
    }
    if ($Matches.commit -ne $Commit) {
      return $False
    }
    return $True
  }

  [System.Management.Automation.SemanticVersion]$CompilerSemVer = $Matches.semver
  [System.Management.Automation.SemanticVersion]$UserSemVer = $Version

  if ($Exact -and ($CompilerSemVer -ne $UserSemVer)) {
    return $False
  }

  if ($CompilerSemVer.Major -ne $UserSemVer.Major) {
    return $False
  }

  # major version 0 indicates an unstable API. therefore, the minor version must be treated more harshly
  if (($CompilerSemVer.Major -eq 0) -and ($CompilerSemVer.Minor -ne $UserSemVer.Minor)) {
    return $False
  }

  if ($CompilerSemVer.Minor -lt $UserSemVer.Minor) {
    return $False
  }

  if (($CompilerSemVer.Minor -eq $UserSemVer.Patch) -and ($CompilerSemVer.Patch -lt $UserSemVer.Patch)) {
    return $False
  }

  if ($CompilerSemVer -ne $UserSemVer) {
    Write-Warning "Compatible but not exact match found: v$($Matches.semver)"
  }

  return $True
}
