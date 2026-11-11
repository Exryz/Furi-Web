@echo off
setlocal
cd /d "%~dp0"
title Furi-Web Installer Launcher

:: Check for administrative rights
net session >nul 2>&1
if %errorlevel% == 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-FuriWeb.ps1"
) else (
    echo Requesting Administrator privileges to install Furi-Web engine hooks...
    powershell.exe -NoProfile -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"\"%~dp0Install-FuriWeb.ps1\"\"'"
)
