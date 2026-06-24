@echo off
:: Check for admin privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: Stop any running Windows Sandbox instance
echo Checking for running Windows Sandbox instances...


PowerShell -ExecutionPolicy Bypass -Command "& {Get-Process -name 'WindowsSandbox*' -IncludeUserName;Get-Process -name 'WindowsSandbox*' | Stop-process -force -Verbose}" 

taskkill /IM WindowsSandbox.exe /F >nul 2>&1
taskkill /IM WindowsSandboxClient.exe /F >nul 2>&1
timeout /t 5 /nobreak >nul



:: Run the launcher in GUI mode
powershell -ExecutionPolicy Bypass -File "%~dp0Launch-AISandbox.ps1" -GUI