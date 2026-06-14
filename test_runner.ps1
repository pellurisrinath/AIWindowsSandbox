# test_runner.ps1 - Automated Test Runner for Sandbox Security Checks

$scriptDir = $PSScriptRoot
$originalLauncher = Join-Path $scriptDir "Launch-AISandbox.ps1"
$testLauncher = Join-Path $scriptDir "Launch-AISandbox-Test.ps1"
$originalToolsConfig = Join-Path $scriptDir "config\tools.json"
$backupToolsConfig = Join-Path $scriptDir "config\tools.json.bak"
$testLogsDir = Join-Path $scriptDir "Logs-Test"

# Setup clean Logs-Test folder
if (Test-Path $testLogsDir) {
    Remove-Item -Path $testLogsDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $testLogsDir -Force | Out-Null

# Backup tools.json
Copy-Item -Path $originalToolsConfig -Destination $backupToolsConfig -Force

Write-Host "Creating patched test launcher..." -ForegroundColor Cyan

# Read original launcher and patch it
$content = Get-Content -Raw -Path $originalLauncher

# 1. Replace log dir setup exactly
$logSetupBlock = @'
# Initialize Logs Directory and File
$LogsDir = "C:\ProgramData\AIWindowsSandbox\Logs"
$FallbackUsed = $false
try {
    $null = New-Item -ItemType Directory -Path $LogsDir -Force -ErrorAction Stop
} catch {
    $FallbackUsed = $true
    $LogsDir = Join-Path $env:TEMP "AIWindowsSandbox\Logs"
    try {
        $null = New-Item -ItemType Directory -Path $LogsDir -Force -ErrorAction Stop
    } catch {
        # Fallback to current folder if TEMP logs fail
        $LogsDir = Join-Path $PSScriptRoot "Logs"
        $null = New-Item -ItemType Directory -Path $LogsDir -Force -ErrorAction SilentlyContinue
    }
}

# Start transcript logging
try {
    $TranscriptPath = Join-Path $LogsDir "Launch-AISandbox.transcript.log"
    Start-Transcript -Path $TranscriptPath -Append -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Failed to start transcript: $_" -ForegroundColor Yellow
}
'@

$logSetupReplacement = @"
# Initialize Logs Directory and File
`$LogsDir = `"$testLogsDir`"
`$FallbackUsed = `$false
`$null = New-Item -ItemType Directory -Path `$LogsDir -Force

# Start transcript logging
try {
    `$TranscriptPath = Join-Path `$LogsDir "Launch-AISandbox.transcript.log"
    Start-Transcript -Path `$TranscriptPath -Append -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Failed to start transcript: `$_" -ForegroundColor Yellow
}
"@

$content = $content.Replace($logSetupBlock, $logSetupReplacement)

# 2. Replace Admin check exactly
$adminCheckBlock = @'
# 1. Elevate to Administrator if not already elevated
try {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Not running as Administrator. Attempting to elevate..." "WARN"
        $arguments = @("-File", $PSCommandPath)
        if ($PSBoundParameters.Keys) {
            foreach ($key in $PSBoundParameters.Keys) {
                if ($PSBoundParameters[$key] -is [switch]) {
                    if ($PSBoundParameters[$key].ToBool()) {
                        $arguments += "-$key"
                    }
                } else {
                    $arguments += "-$key"
                    $arguments += $PSBoundParameters[$key]
                }
            }
        }
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs -ErrorAction Stop
        Exit-Script 0
    }
} catch {
    Write-Log "Error checking or elevating to Administrator: $_`n$($_.ScriptStackTrace)" "ERROR"
    Exit-Script 1
}
'@

$adminCheckReplacement = "Write-Log 'Skipped Administrator elevation check for testing.' 'WARN'"

$content = $content.Replace($adminCheckBlock, $adminCheckReplacement)

# 3. Replace Sandbox check exactly
$sandboxCheckBlock = @'
# 2. Check Windows Sandbox feature
try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -ErrorAction Stop
    if ($null -eq $feature -or $feature.State -ne "Enabled") {
        Write-Log "Windows Sandbox feature (Containers-DisposableClientVM) is not enabled." "WARN"
        $response = Read-Host "Would you like to enable it now? (Y/N)"
        if ($response -match "^[yY]") {
            Write-Log "Enabling Windows Sandbox... A reboot will be required afterwards." "INFO"
            Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All -NoRestart -ErrorAction Stop
            Write-Log "Feature enabled. Please reboot your computer and run this script again." "INFO"
        } else {
            Write-Log "Windows Sandbox feature is required to run this project." "ERROR"
            Exit-Script 1
        }
        Exit-Script 0
    }
} catch {
    Write-Log "Error checking or enabling Windows Sandbox feature: $_`n$($_.ScriptStackTrace)" "ERROR"
    Exit-Script 1
}
'@

$sandboxCheckReplacement = "Write-Log 'Skipped Windows Sandbox feature check for testing.' 'WARN'"

$content = $content.Replace($sandboxCheckBlock, $sandboxCheckReplacement)

# Write out the test launcher
$content | Out-File -FilePath $testLauncher -Encoding utf8 -Force

# Helper function to restore config
function Restore-Config {
    if (Test-Path $backupToolsConfig) {
        Copy-Item -Path $backupToolsConfig -Destination $originalToolsConfig -Force
        Remove-Item -Path $backupToolsConfig -Force
    }
}

# Helper function to run the test launcher
function Run-TestLauncher {
    param(
        [string[]]$arguments
    )
    $p = Start-Process powershell.exe -ArgumentList @("-File", $testLauncher) -PassThru -NoNewWindow -Wait
    return $p.ExitCode
}

$success = $true

try {
    # ----------------------------------------------------
    # TEST CASE 1: Mock-infected threat detection
    # ----------------------------------------------------
    Write-Host "`n=== Test Case 1: Mock-Infected Threat Detection ===" -ForegroundColor Cyan
    
    # 1. Modify tools.json: only Chrome enabled with a mock-infected filename
    $toolsData = Get-Content -Raw -Path $backupToolsConfig | ConvertFrom-Json
    foreach ($tName in $toolsData.tools.psobject.properties.name) {
        if ($tName -eq "chrome") {
            $toolsData.tools.$tName.enabled = $true
            $toolsData.tools.$tName.fileName = "chrome-mock-infected.exe"
        } else {
            $toolsData.tools.$tName.enabled = $false
        }
    }
    $toolsData | ConvertTo-Json -Depth 5 | Out-File -FilePath $originalToolsConfig -Encoding utf8 -Force

    # 2. Pre-create mock infected file in staging
    $stagingPath = Join-Path $env:TEMP "AISandboxStaging"
    $stagingFile = Join-Path $stagingPath "chrome-mock-infected.exe"
    $null = New-Item -ItemType Directory -Path $stagingPath -Force
    "EICAR-STANDARD-ANTIVIRUS-TEST-FILE! mock-infected" | Out-File -FilePath $stagingFile -Encoding utf8 -Force

    # 3. Run launcher
    Write-Host "Running launcher for Mock-Infected test..."
    $exitCode = Run-TestLauncher -arguments @("-PreCacheOnly")
    Write-Host "Launcher exited with code: $exitCode"

    # 4. Assertions
    $logFile = Join-Path $testLogsDir "Launch-AISandbox.log"
    $logContent = Get-Content -Raw -Path $logFile
    
    $threatDetected = $logContent -match "MOCK MALWARE TEST: Threat detected in chrome-mock-infected.exe!"
    $copyBlocked = $logContent -match "Security Check: Windows Defender scan failed or threat detected for Google Chrome"
    $stagingDeleted = -not (Test-Path $stagingFile)
    
    $destFile = Join-Path $env:TEMP "AISandboxShare\Installers\chrome-mock-infected.exe"
    $destNotExists = -not (Test-Path $destFile)

    # Check install-config.json to see if the tool was disabled
    $installConfigPath = Join-Path $env:TEMP "AISandboxShare\install-config.json"
    $disabledInConfig = $false
    if (Test-Path $installConfigPath) {
        $installConfig = Get-Content -Raw -Path $installConfigPath | ConvertFrom-Json
        if ($installConfig.tools.chrome.enabled -eq $false) {
            $disabledInConfig = $true
        }
    }

    Write-Host "Assertions:"
    Write-Host " - Threat detected logged: $threatDetected"
    Write-Host " - Copy blocked logged: $copyBlocked"
    Write-Host " - Staging file deleted: $stagingDeleted"
    Write-Host " - Destination file blocked: $destNotExists"
    Write-Host " - Disabled in install-config.json: $disabledInConfig"

    if ($threatDetected -and $copyBlocked -and $stagingDeleted -and $destNotExists -and $disabledInConfig) {
        Write-Host ">> Test Case 1: PASS" -ForegroundColor Green
    } else {
        Write-Host ">> Test Case 1: FAIL" -ForegroundColor Red
        $success = $false
    }

    # ----------------------------------------------------
    # TEST CASE 2: Checksum mismatch detection
    # ----------------------------------------------------
    Write-Host "`n=== Test Case 2: Checksum Mismatch Detection ===" -ForegroundColor Cyan

    # 1. Modify tools.json: only Python enabled with a mismatched hash value
    $toolsData = Get-Content -Raw -Path $backupToolsConfig | ConvertFrom-Json
    foreach ($tName in $toolsData.tools.psobject.properties.name) {
        if ($tName -eq "python") {
            $toolsData.tools.$tName.enabled = $true
            # Modify the expected hash to be invalid
            $toolsData.tools.$tName.hash = "1111111111111111111111111111111111111111111111111111111111111111"
        } else {
            $toolsData.tools.$tName.enabled = $false
        }
    }
    $toolsData | ConvertTo-Json -Depth 5 | Out-File -FilePath $originalToolsConfig -Encoding utf8 -Force

    # 2. Pre-create dummy file in staging
    $stagingFile2 = Join-Path $stagingPath "python-installer.exe"
    "Dummy python installer content" | Out-File -FilePath $stagingFile2 -Encoding utf8 -Force

    # 3. Run launcher
    Write-Host "Running launcher for Checksum Mismatch test..."
    $exitCode2 = Run-TestLauncher -arguments @("-PreCacheOnly")
    Write-Host "Launcher exited with code: $exitCode2"

    # 4. Assertions
    $logContent2 = Get-Content -Raw -Path $logFile
    
    $hashMismatchDetected = $logContent2 -match "Hash verification FAILED for python-installer.exe"
    $hashCopyBlocked = $logContent2 -match "Security Check: Hash verification failed for Python"
    $stagingDeleted2 = -not (Test-Path $stagingFile2)
    
    $destFile2 = Join-Path $env:TEMP "AISandboxShare\Installers\python-installer.exe"
    $destNotExists2 = -not (Test-Path $destFile2)

    # Check install-config.json
    $disabledInConfig2 = $false
    if (Test-Path $installConfigPath) {
        $installConfig2 = Get-Content -Raw -Path $installConfigPath | ConvertFrom-Json
        if ($installConfig2.tools.python.enabled -eq $false) {
            $disabledInConfig2 = $true
        }
    }

    Write-Host "Assertions:"
    Write-Host " - Hash mismatch logged: $hashMismatchDetected"
    Write-Host " - Hash copy blocked logged: $hashCopyBlocked"
    Write-Host " - Staging file deleted: $stagingDeleted2"
    Write-Host " - Destination file blocked: $destNotExists2"
    Write-Host " - Disabled in install-config.json: $disabledInConfig2"

    if ($hashMismatchDetected -and $hashCopyBlocked -and $stagingDeleted2 -and $destNotExists2 -and $disabledInConfig2) {
        Write-Host ">> Test Case 2: PASS" -ForegroundColor Green
    } else {
        Write-Host ">> Test Case 2: FAIL" -ForegroundColor Red
        $success = $false
    }

} finally {
    # Restore original tools.json config
    Restore-Config
    # Clean up test launcher
    if (Test-Path $testLauncher) {
        Remove-Item -Path $testLauncher -Force
    }
}

if ($success) {
    Write-Host "`nAll tests completed successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nSome tests failed!" -ForegroundColor Red
    exit 1
}
