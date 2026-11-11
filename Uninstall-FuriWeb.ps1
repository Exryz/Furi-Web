<#
.SYNOPSIS
    Furi-Web Automated Uninstaller
.DESCRIPTION
    Restores Floorp Browser to its default branding, removes AutoConfig hooks,
    and restores backed-up userChrome.css.
#>

[CmdletBinding()]
param (
    [string]$FloorpDir,
    [string]$ProfilePath,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FuriWebBrand = "$([char]0x30D5)$([char]0x30EA)$([char]0x30FC)$([char]0x30FB)$([char]0x30A6)$([char]0x30A7)$([char]0x30D6)"

function Write-Step {
    param([string]$Msg)
    Write-Host "`n[+] $Msg" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Msg)
    Write-Host "    [OK] $Msg" -ForegroundColor Green
}

function Write-WarnMsg {
    param([string]$Msg)
    Write-Host "    [!] $Msg" -ForegroundColor Yellow
}

function Write-ErrMsg {
    param([string]$Msg)
    Write-Host "    [X] $Msg" -ForegroundColor Red
}

Clear-Host
Write-Host @"
=============================================================================
             Furi-Web ($FuriWebBrand) Uninstaller / Restore
=============================================================================
"@ -ForegroundColor Yellow

# Check elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    Write-Host "Elevating process to administrator to remove system hooks..." -ForegroundColor Yellow
    $thisScript = $MyInvocation.MyCommand.Path
    $argsList = "-NoProfile -ExecutionPolicy Bypass -File `"$thisScript`""
    if ($FloorpDir) { $argsList += " -FloorpDir `"$FloorpDir`"" }
    if ($ProfilePath) { $argsList += " -ProfilePath `"$ProfilePath`"" }
    Start-Process powershell -Verb RunAs -ArgumentList $argsList
    exit
}

# -----------------------------------------------------------------------------
# 1. Locate Floorp Directory
# -----------------------------------------------------------------------------
Write-Step "Locating Floorp directory..."
$candidateDirs = @(
    $FloorpDir,
    "C:\Program Files\Ablaze Floorp",
    "C:\Program Files\Floorp",
    "$env:ProgramFiles\Ablaze Floorp",
    "$env:ProgramFiles\Floorp",
    "${env:ProgramFiles(x86)}\Ablaze Floorp",
    "${env:ProgramFiles(x86)}\Floorp",
    "$env:LOCALAPPDATA\Programs\Floorp",
    "$env:LOCALAPPDATA\Programs\Ablaze Floorp"
)

$detectedFloorpDir = $null
foreach ($dir in $candidateDirs) {
    if ($dir -and (Test-Path (Join-Path $dir "floorp.exe"))) {
        $detectedFloorpDir = (Get-Item $dir).FullName
        break
    }
}

if ($detectedFloorpDir) {
    Write-Success "Found Floorp at: $detectedFloorpDir"
} else {
    Write-WarnMsg "Floorp directory not found automatically; skipping engine hook removal."
}

# -----------------------------------------------------------------------------
# 2. Locate Profile Directory
# -----------------------------------------------------------------------------
Write-Step "Locating Floorp user profile..."
$targetProfilePath = $null

if ($ProfilePath -and (Test-Path $ProfilePath)) {
    $targetProfilePath = (Get-Item $ProfilePath).FullName
} else {
    $floorpAppData = Join-Path $env:APPDATA "Floorp"
    $profilesIni = Join-Path $floorpAppData "profiles.ini"

    if (Test-Path $profilesIni) {
        $iniLines = Get-Content $profilesIni
        $profiles = @()
        $currentSection = ""
        $currentProfile = @{}
        $defaultInstallPath = $null

        foreach ($line in $iniLines) {
            $line = $line.Trim()
            if ($line -match '^\[(.*)\]$') {
                if ($currentSection -match '^Profile' -and $currentProfile.Count -gt 0) {
                    $profiles += [PSCustomObject]$currentProfile
                }
                $currentSection = $matches[1]
                $currentProfile = @{ Section = $currentSection }
            } elseif ($line -match '^([^=]+)=(.*)$') {
                $key = $matches[1].Trim()
                $val = $matches[2].Trim()
                $currentProfile[$key] = $val
                if ($currentSection -like 'Install*' -and $key -eq 'Default') {
                    $defaultInstallPath = $val
                }
            }
        }
        if ($currentSection -match '^Profile' -and $currentProfile.Count -gt 0) {
            $profiles += [PSCustomObject]$currentProfile
        }

        # 1. Prefer Frieren named profile if present
        $frierenProf = $profiles | Where-Object { $_.Name -like "*Frieren*" }
        if ($frierenProf) {
            $rawPath = $frierenProf[0].Path
            $targetProfilePath = if ($frierenProf[0].IsRelative -eq "1") { Join-Path $floorpAppData $rawPath } else { $rawPath }
        }

        # 2. Match by Install Default
        if (-not $targetProfilePath -and $defaultInstallPath) {
            $targetProfilePath = Join-Path $floorpAppData $defaultInstallPath
        }

        # 3. Look for Default=1
        if (-not $targetProfilePath) {
            $defaultProf = $profiles | Where-Object { $_.Default -eq "1" }
            if ($defaultProf) {
                $rawPath = $defaultProf[0].Path
                $targetProfilePath = if ($defaultProf[0].IsRelative -eq "1") { Join-Path $floorpAppData $rawPath } else { $rawPath }
            }
        }

        # 4. Fallback to first profile
        if (-not $targetProfilePath -and $profiles.Count -gt 0) {
            $rawPath = $profiles[0].Path
            $targetProfilePath = if ($profiles[0].IsRelative -eq "1") { Join-Path $floorpAppData $rawPath } else { $rawPath }
        }
    }
}

if ($targetProfilePath -and (Test-Path $targetProfilePath)) {
    Write-Success "Target Profile: $targetProfilePath"
} else {
    Write-WarnMsg "Profile not found automatically."
}

# -----------------------------------------------------------------------------
# 3. Remove AutoConfig Hooks
# -----------------------------------------------------------------------------
if ($detectedFloorpDir) {
    Write-Step "Removing AutoConfig rebranding hooks..."
    $cfgFile = Join-Path $detectedFloorpDir "floorp.cfg"
    $prefFile = Join-Path $detectedFloorpDir "defaults\pref\autoconfig.js"
    $darkIco = Join-Path $detectedFloorpDir "dark.ico"

    if (Test-Path $cfgFile) {
        Remove-Item $cfgFile -Force
        Write-Success "Removed floorp.cfg"
    }
    if (Test-Path $prefFile) {
        Remove-Item $prefFile -Force
        Write-Success "Removed autoconfig.js"
    }
    if (Test-Path $darkIco) {
        Remove-Item $darkIco -Force
        Write-Success "Removed dark.ico"
    }
}

# -----------------------------------------------------------------------------
# 4. Restore Profile Chrome
# -----------------------------------------------------------------------------
if ($targetProfilePath) {
    Write-Step "Restoring Profile Chrome directory..."
    $profileChrome = Join-Path $targetProfilePath "chrome"
    $userChrome = Join-Path $profileChrome "userChrome.css"
    $userChromeBak = Join-Path $profileChrome "userChrome.css.bak"

    if (Test-Path $userChromeBak) {
        Move-Item $userChromeBak $userChrome -Force
        Write-Success "Restored original userChrome.css from backup"
    } else {
        Write-WarnMsg "No userChrome.css.bak found; leaving current userChrome.css in place"
    }

    # Clean up deployed extra assets
    $cleanupTargets = @("variants", "frieren", "dark.png", "light.png")
    foreach ($item in $cleanupTargets) {
        $p = Join-Path $profileChrome $item
        if (Test-Path $p) {
            Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Cleaned $item"
        }
    }
}

# -----------------------------------------------------------------------------
# 5. Restore Registry Branding
# -----------------------------------------------------------------------------
Write-Step "Restoring Windows Registry branding to default Floorp..."
$startMenuRoot = "HKCU:\Software\Clients\StartMenuInternet"
if (Test-Path $startMenuRoot -and $detectedFloorpDir) {
    $floorpExe = Join-Path $detectedFloorpDir "floorp.exe"
    $browserKeys = Get-ChildItem -Path $startMenuRoot -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match "^(Firefox|Floorp)"
    }

    foreach ($bKey in $browserKeys) {
        try {
            Set-ItemProperty -Path $bKey.PSPath -Name "(default)" -Value "Ablaze Floorp" -Force
            
            $defaultIconKey = Join-Path $bKey.PSPath "DefaultIcon"
            if (Test-Path $defaultIconKey) {
                Set-ItemProperty -Path $defaultIconKey -Name "(default)" -Value "$floorpExe,0" -Force
            }

            $capKey = Join-Path $bKey.PSPath "Capabilities"
            if (Test-Path $capKey) {
                Set-ItemProperty -Path $capKey -Name "ApplicationName" -Value "Floorp" -Force
                Set-ItemProperty -Path $capKey -Name "ApplicationIcon" -Value "$floorpExe,0" -Force
            }
            Write-Success "Restored StartMenuInternet key: $($bKey.PSChildName)"
        } catch {
            Write-WarnMsg "Failed to restore $($bKey.PSChildName): $($_.Exception.Message)"
        }
    }
}

# -----------------------------------------------------------------------------
# 6. Clear Startup Cache
# -----------------------------------------------------------------------------
Write-Step "Clearing Floorp startupCache..."
$localFloorpProfiles = "$env:LOCALAPPDATA\Floorp\Profiles"
if (Test-Path $localFloorpProfiles) {
    $cacheDirs = Get-ChildItem -Path $localFloorpProfiles -Recurse -Directory -Filter "startupCache" -ErrorAction SilentlyContinue
    foreach ($cDir in $cacheDirs) {
        try {
            Remove-Item (Join-Path $cDir.FullName "*") -Recurse -Force -ErrorAction SilentlyContinue
            Write-Success "Cleared: $($cDir.FullName)"
        } catch {}
    }
}

Write-Host @"

=============================================================================
  Furi-Web uninstallation complete! Floorp restored to defaults.
=============================================================================
"@ -ForegroundColor Green
