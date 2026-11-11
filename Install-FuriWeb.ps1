<#
.SYNOPSIS
    Furi-Web Automated Portable Installer
.DESCRIPTION
    Installs the complete Furi-Web theme, engine rebranding, icons, and configuration
    into Floorp Browser on Windows.
#>

[CmdletBinding()]
param (
    [string]$FloorpDir,
    [string]$ProfilePath,
    [string]$ProfileName,
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
  ___ _   _ ____  ___     __        _______ ____  
 | __| | | |  _ \|_ _|    \ \      / / ____| __ ) 
 | _|| | | | |_) || | _____ \ \ /\ / /|  _| |  _ \ 
 |_| |_| |_|_| \_\___|_____| \ V  V / | |___| |_) |
                              \_/\_/  |_____|____/ 
       $FuriWebBrand - Beyond Journey's End Browser Distribution
=============================================================================
"@ -ForegroundColor Magenta

# Check admin elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    Write-Host "Elevating process to administrator to deploy system hooks..." -ForegroundColor Yellow
    $thisScript = $MyInvocation.MyCommand.Path
    $argsList = "-NoProfile -ExecutionPolicy Bypass -File `"$thisScript`""
    if ($FloorpDir) { $argsList += " -FloorpDir `"$FloorpDir`"" }
    if ($ProfilePath) { $argsList += " -ProfilePath `"$ProfilePath`"" }
    if ($ProfileName) { $argsList += " -ProfileName `"$ProfileName`"" }
    Start-Process powershell -Verb RunAs -ArgumentList $argsList
    exit
}

# -----------------------------------------------------------------------------
# 1. Locate Floorp Installation Directory
# -----------------------------------------------------------------------------
Write-Step "Detecting Floorp installation directory..."

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

# Also check registry
$regPaths = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\floorp.exe",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\floorp.exe"
)
foreach ($rp in $regPaths) {
    if (Test-Path $rp) {
        $regVal = (Get-ItemProperty -Path $rp -ErrorAction SilentlyContinue).'(default)'
        if ($regVal -and (Test-Path $regVal)) {
            $candidateDirs += (Split-Path -Parent $regVal)
        }
    }
}

$detectedFloorpDir = $null
foreach ($dir in $candidateDirs) {
    if ($dir -and (Test-Path (Join-Path $dir "floorp.exe"))) {
        $detectedFloorpDir = (Get-Item $dir).FullName
        break
    }
}

if (-not $detectedFloorpDir) {
    Write-ErrMsg "Floorp installation could not be automatically located."
    $detectedFloorpDir = Read-Host "Please enter the Floorp installation directory (e.g. C:\Program Files\Ablaze Floorp)"
    if (-not (Test-Path (Join-Path $detectedFloorpDir "floorp.exe"))) {
        Write-ErrMsg "Invalid Floorp directory: floorp.exe not found in '$detectedFloorpDir'."
        exit 1
    }
}

Write-Success "Found Floorp at: $detectedFloorpDir"

# -----------------------------------------------------------------------------
# 2. Locate Active Floorp Profile
# -----------------------------------------------------------------------------
Write-Step "Detecting Floorp user profile..."

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

        # 1. Match by parameter -ProfileName
        if ($ProfileName) {
            $matched = $profiles | Where-Object { $_.Name -eq $ProfileName }
            if ($matched) {
                $rawPath = $matched[0].Path
                $targetProfilePath = if ($matched[0].IsRelative -eq "1") { Join-Path $floorpAppData $rawPath } else { $rawPath }
            }
        }

        # 2. Prefer Frieren named profile if present
        if (-not $targetProfilePath) {
            $frierenProf = $profiles | Where-Object { $_.Name -like "*Frieren*" }
            if ($frierenProf) {
                $rawPath = $frierenProf[0].Path
                $targetProfilePath = if ($frierenProf[0].IsRelative -eq "1") { Join-Path $floorpAppData $rawPath } else { $rawPath }
            }
        }

        # 3. Match by Install Default
        if (-not $targetProfilePath -and $defaultInstallPath) {
            $targetProfilePath = Join-Path $floorpAppData $defaultInstallPath
        }

        # 4. Look for Default=1
        if (-not $targetProfilePath) {
            $defaultProf = $profiles | Where-Object { $_.Default -eq "1" }
            if ($defaultProf) {
                $rawPath = $defaultProf[0].Path
                $targetProfilePath = if ($defaultProf[0].IsRelative -eq "1") { Join-Path $floorpAppData $rawPath } else { $rawPath }
            }
        }

        # 5. Fallback to first profile
        if (-not $targetProfilePath -and $profiles.Count -gt 0) {
            $rawPath = $profiles[0].Path
            $targetProfilePath = if ($profiles[0].IsRelative -eq "1") { Join-Path $floorpAppData $rawPath } else { $rawPath }
        }
    }
}

if (-not $targetProfilePath -or -not (Test-Path $targetProfilePath)) {
    Write-ErrMsg "Could not detect Floorp profile automatically."
    $targetProfilePath = Read-Host "Please enter the Floorp profile path"
    if (-not (Test-Path $targetProfilePath)) {
        Write-ErrMsg "Directory '$targetProfilePath' does not exist."
        exit 1
    }
}

Write-Success "Target Profile: $targetProfilePath"

# -----------------------------------------------------------------------------
# 3. Deploy Chrome Customizations (userChrome.css & Assets)
# -----------------------------------------------------------------------------
Write-Step "Deploying Chrome themes and assets..."

$profileChrome = Join-Path $targetProfilePath "chrome"
if (-not (Test-Path $profileChrome)) {
    New-Item -ItemType Directory -Force -Path $profileChrome | Out-Null
}

# Backup existing userChrome.css
$existingUserChrome = Join-Path $profileChrome "userChrome.css"
$backupUserChrome = Join-Path $profileChrome "userChrome.css.bak"
if ((Test-Path $existingUserChrome) -and (-not (Test-Path $backupUserChrome))) {
    Copy-Item $existingUserChrome $backupUserChrome -Force
    Write-Success "Backed up existing userChrome.css -> userChrome.css.bak"
}

# Copy theme files
Copy-Item (Join-Path $ScriptDir "chrome\userChrome.css") (Join-Path $profileChrome "userChrome.css") -Force
Copy-Item (Join-Path $ScriptDir "chrome\dark.png") (Join-Path $profileChrome "dark.png") -Force
Copy-Item (Join-Path $ScriptDir "chrome\light.png") (Join-Path $profileChrome "light.png") -Force

# Copy variants and frieren subfolders
Copy-Item (Join-Path $ScriptDir "chrome\variants") $profileChrome -Recurse -Force
Copy-Item (Join-Path $ScriptDir "chrome\frieren") $profileChrome -Recurse -Force

Write-Success "Installed userChrome.css, brand assets, and variants into $profileChrome"

# -----------------------------------------------------------------------------
# 4. Configure Gecko & Floorp Preferences (user.js)
# -----------------------------------------------------------------------------
Write-Step "Updating user.js preferences..."

$sourceUserJs = Join-Path $ScriptDir "chrome\user.js"
$targetUserJs = Join-Path $targetProfilePath "user.js"

$requiredPrefs = @(
    'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);',
    'user_pref("svg.context-properties.content.enabled", true);',
    'user_pref("layout.css.color-mix.enabled", true);',
    'user_pref("layout.css.has-selector.enabled", true);',
    'user_pref("sidebar.revamp", false);',
    'user_pref("sidebar.visibility", "Always");'
)

$existingContent = if (Test-Path $targetUserJs) { Get-Content $targetUserJs -Raw } else { "" }
$toAppend = @()

foreach ($pref in $requiredPrefs) {
    $prefName = ($pref -split '"')[1]
    if ($existingContent -notmatch [regex]::Escape($prefName)) {
        $toAppend += $pref
    }
}

if ($toAppend.Count -gt 0) {
    Add-Content -Path $targetUserJs -Value "`n// Furi-Web Configuration"
    foreach ($line in $toAppend) {
        Add-Content -Path $targetUserJs -Value $line
    }
    Write-Success "Appended $($toAppend.Count) required preference(s) to user.js"
} else {
    Write-Success "All required preferences already present in user.js"
}

# -----------------------------------------------------------------------------
# 5. Deploy AutoConfig Engine Rebranding & Window Icon Hooks
# -----------------------------------------------------------------------------
Write-Step "Deploying AutoConfig engine hooks and brand icons..."

$defaultsPrefDir = Join-Path $detectedFloorpDir "defaults\pref"
if (-not (Test-Path $defaultsPrefDir)) {
    New-Item -ItemType Directory -Force -Path $defaultsPrefDir | Out-Null
}

Copy-Item (Join-Path $ScriptDir "autoconfig\defaults\pref\autoconfig.js") (Join-Path $defaultsPrefDir "autoconfig.js") -Force
Write-Success "Installed autoconfig.js -> $defaultsPrefDir\autoconfig.js"

Copy-Item (Join-Path $ScriptDir "autoconfig\floorp.cfg") (Join-Path $detectedFloorpDir "floorp.cfg") -Force
Write-Success "Installed floorp.cfg -> $detectedFloorpDir\floorp.cfg"

$darkIcoSource = Join-Path $ScriptDir "autoconfig\icons\dark.ico"
$darkIcoTarget = Join-Path $detectedFloorpDir "dark.ico"
Copy-Item $darkIcoSource $darkIcoTarget -Force
Write-Success "Installed dark.ico -> $darkIcoTarget"

# Deploy to browser\chrome\icons\default
$browserIconsDir = Join-Path $detectedFloorpDir "browser\chrome\icons\default"
if (-not (Test-Path $browserIconsDir)) {
    New-Item -ItemType Directory -Force -Path $browserIconsDir | Out-Null
}

$iconNames = @("main-window.ico", "default.ico", "default16.ico", "default32.ico", "default48.ico", "default64.ico", "default128.ico")
$copiedCount = 0
foreach ($ico in $iconNames) {
    try {
        Copy-Item $darkIcoSource (Join-Path $browserIconsDir $ico) -Force -ErrorAction Stop
        $copiedCount++
    } catch {}
}
if ($copiedCount -eq $iconNames.Count) {
    Write-Success "Updated $copiedCount binary default icons in $browserIconsDir"
} elseif ($copiedCount -gt 0) {
    Write-WarnMsg "Updated $copiedCount of $($iconNames.Count) binary default icons in $browserIconsDir"
} else {
    Write-WarnMsg "Could not overwrite binary default icons in $browserIconsDir (run as Administrator to update)"
}

# -----------------------------------------------------------------------------
# 6. Update Windows Start Menu & Taskbar Branding (Registry)
# -----------------------------------------------------------------------------
Write-Step "Applying Windows Start Menu & Taskbar branding in Registry..."

$startMenuRoot = "HKCU:\Software\Clients\StartMenuInternet"
if (Test-Path $startMenuRoot) {
    $browserKeys = Get-ChildItem -Path $startMenuRoot -ErrorAction SilentlyContinue | Where-Object {
        $_.PSChildName -match "^(Firefox|Floorp)"
    }

    foreach ($bKey in $browserKeys) {
        try {
            Set-ItemProperty -Path $bKey.PSPath -Name "(default)" -Value $FuriWebBrand -Force
            
            $defaultIconKey = Join-Path $bKey.PSPath "DefaultIcon"
            if (Test-Path $defaultIconKey) {
                Set-ItemProperty -Path $defaultIconKey -Name "(default)" -Value "$darkIcoTarget,0" -Force
            }

            $capKey = Join-Path $bKey.PSPath "Capabilities"
            if (Test-Path $capKey) {
                Set-ItemProperty -Path $capKey -Name "ApplicationName" -Value $FuriWebBrand -Force
                Set-ItemProperty -Path $capKey -Name "ApplicationIcon" -Value "$darkIcoTarget,0" -Force
            }
            Write-Success "Updated StartMenuInternet key: $($bKey.PSChildName)"
        } catch {
            Write-WarnMsg "Failed to update $($bKey.PSChildName): $($_.Exception.Message)"
        }
    }
}

# -----------------------------------------------------------------------------
# 7. Clear Floorp Startup Cache
# -----------------------------------------------------------------------------
Write-Step "Clearing Floorp startupCache to force immediate UI compilation..."

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

# -----------------------------------------------------------------------------
# Installation Summary & Next Steps
# -----------------------------------------------------------------------------
Write-Host @"

=============================================================================
  FURI-WEB ($FuriWebBrand) DEPLOYMENT COMPLETED SUCCESSFULLY!
=============================================================================

Installed Components:
  [OK] Native AutoConfig Engine Hook  : $detectedFloorpDir\floorp.cfg
  [OK] Native Win32 Window Icons      : $browserIconsDir
  [OK] StartMenuInternet Registry     : $FuriWebBrand
  [OK] userChrome.css & Floating Rail : $profileChrome\userChrome.css
  [OK] Gecko Engine Preferences       : $targetProfilePath\user.js
  [OK] Startup UI Cache Purged        : Clean state ready

NEXT STEPS TO COMPLETE SETUP:
1. Load the Furi-Web Startpage WebExtension:
   - Launch Floorp and navigate to: about:addons
   - Click the Gear icon at the top-right of the Add-ons Manager
   - Click 'Install Add-on From File...'
   - Select: '$ScriptDir\releases\frieren_startpage.xpi'

2. Import Sidebery v5 Floating Sidebar Styles:
   - Open the Sidebery sidebar panel in Floorp
   - Click the Sidebery Settings gear
   - Go to 'Styles editor'
   - Paste the contents of: '$ScriptDir\sidebery\sidebery.css'
   - Click Save!

3. Optional Tabliss / Banners Setup:
   - If using Tabliss extension, import '$ScriptDir\tabliss\tabliss_frieren_web_import.json'
   - Wallpapers and web banners are available in '$ScriptDir\wallpapers\'

Restart Floorp to experience $FuriWebBrand!
=============================================================================
"@ -ForegroundColor Green
