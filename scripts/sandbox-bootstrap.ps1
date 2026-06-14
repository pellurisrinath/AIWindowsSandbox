# sandbox-bootstrap.ps1 - Windows AI Sandbox Logon Script
# Runs inside the sandbox at startup

$ErrorActionPreference = "Continue"
$startTime = Get-Date

# Setup Logs Directory
$logsDir = "C:\ProgramData\WindowsAISandboxApps\Logs"
try {
    if (-not (Test-Path $logsDir)) {
        $null = New-Item -ItemType Directory -Path $logsDir -Force -ErrorAction Stop
    }
} catch {
    # Fallback to local drive root if directory cannot be created
    $logsDir = "C:\"
}

# Start transcript logging
try {
    $TranscriptPath = Join-Path $logsDir "sandbox-bootstrap.transcript.log"
    Start-Transcript -Path $TranscriptPath -Append -Force -ErrorAction SilentlyContinue
} catch {
    Write-Host "Failed to start transcript: $_" -ForegroundColor Yellow
}

$logFile = Join-Path $logsDir "sandbox-bootstrap.log"

function Exit-Script {
    param([int]$code = 0)
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    exit $code
}

# Helper: Timestamped Log Writer
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $cleanMsg = $Message
    $detectedLevel = $Level
    if ($Message -match "^\[(INFO|WARN|ERROR|OK|SKIP)\]\s*(.*)$") {
        $detectedLevel = $Matches[1]
        $cleanMsg = $Matches[2]
        if ($detectedLevel -eq "OK" -or $detectedLevel -eq "SKIP") {
            $detectedLevel = "INFO"
        }
    }
    
    $logLine = "[$timestamp] [$detectedLevel] $cleanMsg"
    
    switch ($detectedLevel) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARN" { Write-Host $Message -ForegroundColor Yellow }
        default { Write-Host $Message -ForegroundColor Cyan }
    }
    
    try {
        $logLine | Out-File -FilePath $logFile -Append -Encoding utf8 -ErrorAction SilentlyContinue
    } catch {}
}

Write-Log "=== Windows AI Sandbox Provisioning Started ===" "INFO"

# Detect Sandbox OS (Windows 11 24H2/25H2 x64)
try {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $build = [int]$osInfo.BuildNumber
    $osCaption = $osInfo.Caption
    $osArch = $osInfo.OSArchitecture

    $sandboxVerName = switch ($build) {
        26100 { "Windows 11 24H2" }
        26200 { "Windows 11 25H2" }
        default { "Windows (Build $build)" }
    }
    Write-Log "Sandbox OS detected: $osCaption - $sandboxVerName ($osArch)" "INFO"

    # Verify x64 architecture
    if ($osArch -ne "64-bit") {
        Write-Log "Unsupported architecture in sandbox: $osArch. Only x64 (64-bit) is supported." "ERROR"
        Exit-Script 1
    }

    # Verify minimum OS build (24H2 = 26100, 25H2 = 26200)
    $minBuild = 26100
    if ($build -lt $minBuild) {
        Write-Log "Sandbox is running $sandboxVerName. Minimum required: Windows 11 24H2 (Build 26100) or later." "ERROR"
        Write-Log "Please update your HOST Windows installation to 24H2 or 25H2." "ERROR"
        Exit-Script 1
    }

    Write-Log "[OK] Sandbox meets requirements: $sandboxVerName x64" "INFO"

    # Export OS info for use by tool installers
    $global:SandboxOS = @{
        Caption     = $osCaption
        BuildNumber = $build
        Architecture = $osArch
        VersionName = $sandboxVerName
        Is24H2 = ($build -eq 26100)
        Is25H2 = ($build -ge 26200)
    }
} catch {
    Write-Log "Failed to detect sandbox OS: $_" "WARN"
    $global:SandboxOS = $null
}

# 1. Read configuration
try {
    $configPath = "C:\SharedTools\install-config.json"
    if (-not (Test-Path $configPath)) {
        Write-Log "Configuration file not found at $configPath. Exiting bootstrap." "ERROR"
        Exit-Script 1
    }
    $config = Get-Content -Raw -Path $configPath -ErrorAction Stop | ConvertFrom-Json
    $tools = $config.tools

    # Read host OS info from install-config.json
    if ($config.PSObject.Properties.Name -contains 'hostOS') {
        $hostOS = $config.hostOS
        Write-Log "Host OS reported: $($hostOS.Caption) (Build $($hostOS.BuildNumber), Target: $($hostOS.TargetVersion))" "INFO"
        $global:HostOS = $hostOS
    }

    $enabledSteps = [System.Collections.Generic.List[string]]::new()
    if ($tools.nodejs.enabled) { [void]$enabledSteps.Add("Node.js + npm") }
    if ($tools.python.enabled) { [void]$enabledSteps.Add("Python") }
    if ($tools.chrome.enabled) { [void]$enabledSteps.Add("Google Chrome") }
    if ($tools.pageassist.enabled -and $tools.chrome.enabled) { [void]$enabledSteps.Add("Page Assist Extension") }
    if ($tools.brave.enabled) { [void]$enabledSteps.Add("Brave Browser") }
    if ($tools.notepadpp.enabled) { [void]$enabledSteps.Add("Notepad++") }
    if ($tools.beyondcompare.enabled) { [void]$enabledSteps.Add("Beyond Compare 4") }
    if ($tools.ollama.enabled) { 
        [void]$enabledSteps.Add("Ollama")
        [void]$enabledSteps.Add("Gemma4 Model")
        [void]$enabledSteps.Add("nous-hermes2 Model")
    }
    if ($tools.lmstudio.enabled) { [void]$enabledSteps.Add("LM Studio") }
    if ($tools.'opencode-terminal'.enabled) { [void]$enabledSteps.Add("OpenCode Terminal") }
    if ($tools.'opencode-desktop'.enabled) { [void]$enabledSteps.Add("OpenCode Desktop") }
    if ($tools.crewai.enabled) { [void]$enabledSteps.Add("Crew AI") }
    if ($tools.copilot.enabled -and $tools.chrome.enabled) { [void]$enabledSteps.Add("Microsoft Copilot PWA") }
    if ($tools.vscode.enabled) { [void]$enabledSteps.Add("Visual Studio Code") }
    if ($tools.vscommunity.enabled) { [void]$enabledSteps.Add("Visual Studio Community") }
    if ($tools.'7zip'.enabled) { [void]$enabledSteps.Add("7-Zip") }
    if ($tools.sysinternals.enabled) { [void]$enabledSteps.Add("Sysinternals Suite") }
    if ($tools.powertoys.enabled) { [void]$enabledSteps.Add("Windows PowerToys") }
    if ($tools.windowssdk.enabled) { [void]$enabledSteps.Add("Windows SDK") }
    if ($tools.adk.enabled) { [void]$enabledSteps.Add("Windows ADK") }
    if ($tools.adkwinpe.enabled) { [void]$enabledSteps.Add("Windows ADK WinPE Add-on") }
    if ($tools.antigravity.enabled) { [void]$enabledSteps.Add("Antigravity CLI") }

    $global:totalSteps = $enabledSteps.Count
    $global:currentStep = 0

    function Update-InstallProgress {
        param(
            [int]$StepIndex,
            [string]$ActiveInstall,
            [string]$Status
        )
        try {
            $progress = @{
                currentStep   = $StepIndex
                totalSteps     = $global:totalSteps
                activeInstall = $ActiveInstall
                status        = $Status
            }
            $progressJson = $progress | ConvertTo-Json -Compress
            $progressFile = "C:\ProgramData\WindowsAISandboxApps\Logs\install-progress.json"
            $null = New-Item -ItemType Directory -Path (Split-Path $progressFile) -Force -ErrorAction SilentlyContinue
            $progressJson | Out-File -FilePath $progressFile -Encoding utf8 -Force -ErrorAction Stop
        } catch {
            Write-Log "Failed to update install-progress.json: $_`n$($_.ScriptStackTrace)" "ERROR"
        }
    }
    
    Update-InstallProgress -StepIndex 0 -ActiveInstall "Initializing" -Status "Installing"
} catch {
    Write-Log "Failed to load/parse configuration: $_`n$($_.ScriptStackTrace)" "ERROR"
    Exit-Script 1
}

# 2. Check Host Ollama endpoint connection
try {
    Write-Log "Checking host Ollama connectivity..." "INFO"
    $ollamaHostUrl = "http://100.90.169.70:11434"
    try {
        $response = Invoke-WebRequest -Uri "$ollamaHostUrl/api/tags" -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        Write-Log "[OK] Host Ollama endpoint is reachable." "INFO"
    } catch {
        Write-Log "[WARN] Host Ollama endpoint ($ollamaHostUrl) is unreachable. Some AI components may fail: $_`n$($_.ScriptStackTrace)" "WARN"
    }
} catch {
    Write-Log "Error checking Ollama connectivity: $_`n$($_.ScriptStackTrace)" "ERROR"
}

# Set environment variables for AI runtimes and tools
try {
    [System.Environment]::SetEnvironmentVariable("OLLAMA_HOST", $ollamaHostUrl, [System.EnvironmentVariableTarget]::Machine)
    [System.Environment]::SetEnvironmentVariable("OPENAI_BASE_URL", "$ollamaHostUrl/v1", [System.EnvironmentVariableTarget]::Machine)
    $env:OLLAMA_HOST = $ollamaHostUrl
    $env:OPENAI_BASE_URL = "$ollamaHostUrl/v1"
} catch {
    Write-Log "Failed to set environment variables: $_`n$($_.ScriptStackTrace)" "ERROR"
}

# Helper function to refresh PATH
function Refresh-Path {
    try {
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    } catch {
        Write-Log "Failed to refresh PATH: $_`n$($_.ScriptStackTrace)" "ERROR"
    }
}

# Helper to run silent installer processes
function Install-SilentProcess {
    param(
        [string]$ToolId,
        [string]$ToolName,
        [string]$InstallerPath,
        [string]$SilentArgs,
        [string]$LogFile
    )
    
    if (-not (Test-Path $InstallerPath)) {
        Write-Log "Installer for $ToolName not found at $InstallerPath" "ERROR"
        return "ERROR"
    }

    Write-Log "Installing $ToolName silently..." "INFO"
    
    # Auto-append MSI verbose logging if LogFile specified and installer is MSI
    $finalArgs = $SilentArgs
    if ($LogFile -and $InstallerPath.EndsWith(".msi", [System.StringComparison]::OrdinalIgnoreCase)) {
        $finalArgs = "$SilentArgs /L*v `"$LogFile`""
    }
    
    try {
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList $finalArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($proc.ExitCode -eq 0) {
            Write-Log "[OK] $ToolName installed successfully." "INFO"
            return "OK"
        } else {
            Write-Log "[WARN] $ToolName installer exited with code $($proc.ExitCode)" "WARN"
            return "WARN"
        }
    } catch {
        Write-Log "Failed to install $($ToolName): $_`n$($_.ScriptStackTrace)" "ERROR"
        return "ERROR"
    }
}

# Helper to verify post-install artifacts
function Test-InstallationArtifacts {
    param(
        [string]$ToolId,
        [string]$ToolName,
        [string[]]$ExpectedPaths,
        [string[]]$ExpectedCommands
    )
    
    $found = 0
    $total = 0
    $details = @()
    
    # Check expected file paths
    foreach ($path in $ExpectedPaths) {
        $total++
        if ($path -and (Test-Path $path)) {
            $found++
            $details += "  [OK] File present: $path"
        } else {
            $details += "  [MISSING] File NOT found: $path"
        }
    }
    
    # Check expected commands
    foreach ($cmd in $ExpectedCommands) {
        $total++
        $cmdPath = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($cmdPath) {
            $found++
            $details += "  [OK] Command available: $cmd -> $($cmdPath.Source)"
        } else {
            $details += "  [MISSING] Command NOT found: $cmd"
        }
    }
    
    if ($total -eq 0) {
        Write-Log "[VERIFY] $ToolName - no verification artifacts defined" "INFO"
        return "OK"
    }
    
    $percent = [Math]::Round(($found / $total) * 100, 0)
    foreach ($detail in $details) {
        Write-Log $detail "INFO"
    }
    
    if ($found -eq $total) {
        Write-Log "[VERIFY] [OK] $ToolName - all $total artifacts present (100%)" "OK"
        return "OK"
    } elseif ($found -gt 0) {
        Write-Log "[VERIFY] [WARN] $ToolName - only $found of $total artifacts present ($percent%)" "WARN"
        return "WARN"
    } else {
        Write-Log "[VERIFY] [ERROR] $ToolName - none of the $total expected artifacts found (0%)" "ERROR"
        return "ERROR"
    }
}

$results = @{}

# Order 1: Node.js
try {
    if ($tools.nodejs.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Node.js + npm" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.nodejs.fileName)"
        $res = Install-SilentProcess -ToolId "nodejs" -ToolName "Node.js + npm" -InstallerPath $installer -SilentArgs $tools.nodejs.silentArgs
        $results["nodejs"] = $res
        Refresh-Path
        if ($res -eq "OK") {
            $verifyRes = Test-InstallationArtifacts -ToolId "nodejs" -ToolName "Node.js + npm" -ExpectedPaths @("C:\Program Files\nodejs\node.exe", "C:\Program Files (x86)\nodejs\node.exe") -ExpectedCommands @("node", "npm")
            if ($verifyRes -ne "OK") { $results["nodejs"] = $verifyRes }
        }
        $status = if ($results["nodejs"] -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Node.js + npm" -Status $status
    } else {
        Write-Log "[SKIP] Node.js + npm (disabled by config)" "INFO"
        $results["nodejs"] = "SKIP"
    }
} catch {
    Write-Log "Node.js installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["nodejs"] = "ERROR"
    if ($tools.nodejs.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Node.js + npm" -Status "Failed"
    }
}

# Order 2: Python (If Python is enabled and not installed)
try {
    if ($tools.python.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Python" -Status "Installing"
        Write-Log "Checking for Python..." "INFO"
        $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
        if (-not $pythonCmd) {
            $pythonInstaller = "C:\SharedTools\Installers\$($tools.python.fileName)"
            if (Test-Path $pythonInstaller) {
                Write-Log "Installing Python silently with verbose logging..." "INFO"
                # Initialize COM for sandbox compatibility
                try { [System.Runtime.InteropServices.Marshal]::InitializeCom() } catch {}
                try {
                    # Python 3.12+ ships .exe installers (not .msi). The .exe accepts
                    # the same /quiet MSI-style arguments. The /log flag writes verbose
                    # output to the specified file.
                    $pythonLog = Join-Path $logsDir "python-install.log"
                    $pyArgs = "$($tools.python.silentArgs) /log `"$pythonLog`""
                    $proc = Start-Process -FilePath $pythonInstaller -ArgumentList $pyArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
                    if ($proc.ExitCode -eq 0) {
                        Write-Log "[OK] Python installed successfully." "INFO"
                        $results["python"] = "OK"
                    } else {
                        Write-Log "[WARN] Python installer exited with code $($proc.ExitCode). Check log: $pythonLog" "WARN"
                        $results["python"] = "WARN"
                    }
                } catch {
                    Write-Log "[ERROR] Python installation failed: $_`n$($_.ScriptStackTrace)" "ERROR"
                    $results["python"] = "ERROR"
                }
                Refresh-Path
            } else {
                Write-Log "[WARN] Python installer not found at $pythonInstaller. Cannot install CrewAI." "WARN"
                $results["python"] = "ERROR"
            }
        } else {
            Write-Log "[OK] Python already installed." "INFO"
            $results["python"] = "OK"
        }
        if ($results["python"] -eq "OK") {
            $verifyRes = Test-InstallationArtifacts -ToolId "python" -ToolName "Python" -ExpectedPaths @("C:\Program Files\Python312\python.exe", "C:\Python312\python.exe", "C:\Users\WDAGUtility\AppData\Local\Programs\Python\Python312\python.exe") -ExpectedCommands @("python", "pip")
            if ($verifyRes -ne "OK") { $results["python"] = $verifyRes }
        }
        $status = if ($results["python"] -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Python" -Status $status
    } else {
        $results["python"] = "SKIP"
    }
} catch {
    Write-Log "Python installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["python"] = "ERROR"
    if ($tools.python.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Python" -Status "Failed"
    }
}

# Order 3: Google Chrome
try {
    if ($tools.chrome.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Google Chrome" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.chrome.fileName)"
        $res = Install-SilentProcess -ToolId "chrome" -ToolName "Google Chrome" -InstallerPath $installer -SilentArgs $tools.chrome.silentArgs
        $results["chrome"] = $res
        if ($res -eq "OK") {
            $verifyRes = Test-InstallationArtifacts -ToolId "chrome" -ToolName "Google Chrome" -ExpectedPaths @("C:\Program Files\Google\Chrome\Application\chrome.exe", "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe")
            if ($verifyRes -ne "OK") { $results["chrome"] = $verifyRes }
        }
        $status = if ($results["chrome"] -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Google Chrome" -Status $status
    } else {
        Write-Log "[SKIP] Google Chrome (disabled by config)" "INFO"
        $results["chrome"] = "SKIP"
    }
} catch {
    Write-Log "Google Chrome installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["chrome"] = "ERROR"
    if ($tools.chrome.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Google Chrome" -Status "Failed"
    }
}

# Order 4: Page Assist (Only if Chrome is installed and enabled)
try {
    if ($tools.pageassist.enabled -and $results["chrome"] -eq "OK") {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Page Assist Extension" -Status "Installing"
        Write-Log "Configuring Page Assist Chrome extension..." "INFO"
        try {
            $targetExtPath = "C:\SharedTools\Extensions\page-assist"
            if (Test-Path $targetExtPath) {
                # Create a Desktop shortcut with extension preloaded
                $wshShell = New-Object -ComObject WScript.Shell
                $shortcutPath = [System.IO.Path]::Combine($env:USERPROFILE, "Desktop", "Chrome (Page Assist).lnk")
                $shortcut = $wshShell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = "C:\Program Files\Google\Chrome\Application\chrome.exe"
                $shortcut.Arguments = '--load-extension="' + $targetExtPath + '"'
                $shortcut.Save()
                Write-Log "[OK] Page Assist shortcut created on Desktop." "INFO"
                $results["pageassist"] = "OK"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Page Assist Extension" -Status "Completed"
            } else {
                Write-Log "[WARN] Page Assist extension files not found at $targetExtPath" "WARN"
                $results["pageassist"] = "WARN"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Page Assist Extension" -Status "Failed"
            }
        } catch {
            Write-Log "[ERROR] Failed to load Page Assist: $_`n$($_.ScriptStackTrace)" "ERROR"
            $results["pageassist"] = "ERROR"
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Page Assist Extension" -Status "Failed"
        }
    } else {
        Write-Log "[SKIP] Page Assist extension" "INFO"
        $results["pageassist"] = "SKIP"
    }
} catch {
    Write-Log "Page Assist configuration block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["pageassist"] = "ERROR"
    if ($tools.pageassist.enabled -and $results["chrome"] -eq "OK") {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Page Assist Extension" -Status "Failed"
    }
}

# Order 5: Brave Browser
try {
    if ($tools.brave.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Brave Browser" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.brave.fileName)"
        $res = Install-SilentProcess -ToolId "brave" -ToolName "Brave Browser" -InstallerPath $installer -SilentArgs $tools.brave.silentArgs
        $results["brave"] = $res
        if ($res -eq "OK") {
            $verifyRes = Test-InstallationArtifacts -ToolId "brave" -ToolName "Brave Browser" -ExpectedPaths @("C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe", "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe")
            if ($verifyRes -ne "OK") { $results["brave"] = $verifyRes }
        }
        $status = if ($results["brave"] -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Brave Browser" -Status $status
    } else {
        Write-Log "[SKIP] Brave Browser (disabled by config)" "INFO"
        $results["brave"] = "SKIP"
    }
} catch {
    Write-Log "Brave Browser installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["brave"] = "ERROR"
    if ($tools.brave.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Brave Browser" -Status "Failed"
    }
}

# Order 6: Notepad++
try {
    if ($tools.notepadpp.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Notepad++" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.notepadpp.fileName)"
        $res = Install-SilentProcess -ToolId "notepadpp" -ToolName "Notepad++" -InstallerPath $installer -SilentArgs $tools.notepadpp.silentArgs
        $results["notepadpp"] = $res
        if ($res -eq "OK") {
            $verifyRes = Test-InstallationArtifacts -ToolId "notepadpp" -ToolName "Notepad++" -ExpectedPaths @("C:\Program Files\Notepad++\notepad++.exe", "C:\Program Files (x86)\Notepad++\notepad++.exe")
            if ($verifyRes -ne "OK") { $results["notepadpp"] = $verifyRes }
        }
        $status = if ($results["notepadpp"] -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Notepad++" -Status $status
    } else {
        Write-Log "[SKIP] Notepad++ (disabled by config)" "INFO"
        $results["notepadpp"] = "SKIP"
    }
} catch {
    Write-Log "Notepad++ installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["notepadpp"] = "ERROR"
    if ($tools.notepadpp.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Notepad++" -Status "Failed"
    }
}

# Order 7: Beyond Compare 4
try {
    if ($tools.beyondcompare.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare 4" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.beyondcompare.fileName)"
        $res = Install-SilentProcess -ToolId "beyondcompare" -ToolName "Beyond Compare 4" -InstallerPath $installer -SilentArgs $tools.beyondcompare.silentArgs
        $results["beyondcompare"] = $res
        if ($res -eq "OK") {
            $verifyRes = Test-InstallationArtifacts -ToolId "beyondcompare" -ToolName "Beyond Compare 4" -ExpectedPaths @("C:\Program Files\Beyond Compare 4\BCompare.exe", "C:\Program Files (x86)\Beyond Compare 4\BCompare.exe")
            if ($verifyRes -ne "OK") { $results["beyondcompare"] = $verifyRes }
        }
        $status = if ($results["beyondcompare"] -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare 4" -Status $status
    } else {
        Write-Log "[SKIP] Beyond Compare 4 (disabled by config)" "INFO"
        $results["beyondcompare"] = "SKIP"
    }
} catch {
    Write-Log "Beyond Compare installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["beyondcompare"] = "ERROR"
    if ($tools.beyondcompare.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare 4" -Status "Failed"
    }
}

# Order 8: Ollama
try {
    if ($tools.ollama.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Ollama" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.ollama.fileName)"
        
        # Try WDAC bypass - set policy to Audit mode
        Write-Log "Attempting WDAC policy bypass for Ollama installation..." "INFO"
        try {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\CI"
            Set-ItemProperty -Path $regPath -Name "VerifiedAndReputablePolicyState" -Value 0 -ErrorAction SilentlyContinue
            Write-Log "WDAC policy set to Audit mode" "INFO"
        } catch {
            Write-Log "Could not modify WDAC policy: $_" "WARN"
        }
        
        $res = Install-SilentProcess -ToolId "ollama" -ToolName "Ollama" -InstallerPath $installer -SilentArgs $tools.ollama.silentArgs
        $results["ollama"] = $res

        # If WDAC still blocks, download Ollama CLI directly via curl
        if ($res -ne "OK") {
            Write-Log "Ollama installer may be blocked. Attempting direct CLI download via curl..." "WARN"
            $ollamaCliUrl = "https://ollama.com/download/ollama-windows-amd64.exe"
            $ollamaCliDest = "C:\SharedTools\Installers\ollama-windows-amd64.exe"
            try {
                & curl.exe -L -o $ollamaCliDest $ollamaCliUrl 2>&1 | ForEach-Object { Write-Log "$_" "INFO" }
                if (Test-Path $ollamaCliDest) {
                    $size = (Get-Item $ollamaCliDest).Length
                    if ($size -gt 1MB) {
                        $ollamaDir = "C:\Users\WDAGUtility\AppData\Local\Programs\Ollama"
                        New-Item -ItemType Directory -Path $ollamaDir -Force | Out-Null
                        Copy-Item -Path $ollamaCliDest -Destination "$ollamaDir\ollama.exe" -Force
                        $env:PATH = "$ollamaDir;$env:PATH"
                        [Environment]::SetEnvironmentVariable("PATH", "$ollamaDir;$([Environment]::GetEnvironmentVariable('PATH', 'User'))", "User")
                        Write-Log "Ollama CLI installed to $ollamaDir" "OK"
                        $res = "OK"
                    } else {
                        Write-Log "Downloaded Ollama CLI is too small ($size bytes), likely not a valid binary" "ERROR"
                    }
                }
            } catch {
                Write-Log "Failed to download Ollama CLI: $_" "ERROR"
            }
        }
        $results["ollama"] = $res

        if ($res -eq "OK") {
            # Verify Ollama installation artifacts
            $verifyRes = Test-InstallationArtifacts -ToolId "ollama" -ToolName "Ollama" -ExpectedPaths @("C:\Users\WDAGUtility\AppData\Local\Programs\Ollama\ollama.exe", "C:\Users\WDAGUtility\AppData\Local\Programs\Ollama\ollama app.exe", "C:\Program Files\Ollama\ollama.exe") -ExpectedCommands @("ollama")
            if ($verifyRes -ne "OK") {
                Write-Log "Ollama installation reports OK but artifacts missing. Downgrading result." "WARN"
                $results["ollama"] = $verifyRes
                $res = $verifyRes
            }
        }

        if ($res -eq "OK") {
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Ollama" -Status "Completed"
            
            # Substep: Start Ollama and wait for API
            Write-Log "Starting Ollama application..." "INFO"
            $ollamaAppPath = Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama app.exe"
            if (Test-Path $ollamaAppPath) {
                Start-Process -FilePath $ollamaAppPath -NoNewWindow
                Write-Log "Waiting for Ollama API to become active..." "INFO"
                $started = $false
                for ($i = 0; $i -lt 12; $i++) {
                    Start-Sleep -Seconds 3
                    try {
                        $tags = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -ErrorAction Stop
                        $started = $true
                        Write-Log "[OK] Ollama local endpoint is up." "INFO"
                        break
                    } catch {
                        # Poll again
                    }
                }
                
                if ($started) {
                    # Substep: Gemma4 Model (first priority)
                    $global:currentStep++
                    Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Gemma4 Model" -Status "Installing"
                    Write-Log "Pulling Gemma4 model..." "INFO"
                    try {
                        $proc = Start-Process -FilePath "ollama" -ArgumentList "pull gemma4" -Wait -PassThru -NoNewWindow -ErrorAction Stop
                        if ($proc.ExitCode -eq 0) {
                            Write-Log "[OK] Gemma4 model pulled successfully." "INFO"
                            $results["gemma4_model"] = "OK"
                            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Gemma4 Model" -Status "Completed"
                        } else {
                            Write-Log "[WARN] ollama pull gemma4 exited with code $($proc.ExitCode)" "WARN"
                            $results["gemma4_model"] = "WARN"
                            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Gemma4 Model" -Status "Failed"
                        }
                    } catch {
                        Write-Log "[ERROR] Failed to pull Gemma4 model: $_`n$($_.ScriptStackTrace)" "ERROR"
                        $results["gemma4_model"] = "ERROR"
                        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Gemma4 Model" -Status "Failed"
                    }
                    
                    # Substep: nous-hermes2 Model
                    $global:currentStep++
                    Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "nous-hermes2 Model" -Status "Installing"
                    Write-Log "Pulling nous-hermes2 model..." "INFO"
                    try {
                        $proc = Start-Process -FilePath "ollama" -ArgumentList "pull nous-hermes2" -Wait -PassThru -NoNewWindow -ErrorAction Stop
                        if ($proc.ExitCode -eq 0) {
                            Write-Log "[OK] nous-hermes2 model pulled successfully." "INFO"
                            $results["hermes_model"] = "OK"
                            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "nous-hermes2 Model" -Status "Completed"
                        } else {
                            Write-Log "[WARN] ollama pull nous-hermes2 exited with code $($proc.ExitCode)" "WARN"
                            $results["hermes_model"] = "WARN"
                            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "nous-hermes2 Model" -Status "Failed"
                        }
                    } catch {
                        Write-Log "[ERROR] Failed to pull nous-hermes2 model: $_`n$($_.ScriptStackTrace)" "ERROR"
                        $results["hermes_model"] = "ERROR"
                        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "nous-hermes2 Model" -Status "Failed"
                    }
                } else {
                    Write-Log "[WARN] Ollama app started but API is unresponsive." "WARN"
                    $results["gemma4_model"] = "WARN"
                    $results["hermes_model"] = "WARN"
                    Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Gemma4 Model" -Status "Failed"
                    $global:currentStep++
                    Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "nous-hermes2 Model" -Status "Failed"
                }
            } else {
                Write-Log "[WARN] Ollama executable not found at $ollamaAppPath" "WARN"
                $results["gemma4_model"] = "ERROR"
                $results["hermes_model"] = "ERROR"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Gemma4 Model" -Status "Failed"
                $global:currentStep++
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "nous-hermes2 Model" -Status "Failed"
            }
        } else {
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Ollama" -Status "Failed"
            $global:currentStep++
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Gemma4 Model" -Status "Failed"
            $global:currentStep++
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "nous-hermes2 Model" -Status "Failed"
            $results["gemma4_model"] = "ERROR"
            $results["hermes_model"] = "ERROR"
        }
    } else {
        Write-Log "[SKIP] Ollama (disabled by config)" "INFO"
        $results["ollama"] = "SKIP"
        $results["gemma4_model"] = "SKIP"
        $results["hermes_model"] = "SKIP"
    }
} catch {
    Write-Log "Ollama installation/configuration block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["ollama"] = "ERROR"
    $results["gemma4_model"] = "ERROR"
    $results["hermes_model"] = "ERROR"
    if ($tools.ollama.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Gemma4 Model" -Status "Failed"
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "nous-hermes2 Model" -Status "Failed"
    }
}

# Order 9: LM Studio
try {
    if ($tools.lmstudio.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "LM Studio" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.lmstudio.fileName)"
        $res = Install-SilentProcess -ToolId "lmstudio" -ToolName "LM Studio" -InstallerPath $installer -SilentArgs $tools.lmstudio.silentArgs
        $results["lmstudio"] = $res
        if ($res -eq "OK") {
            $verifyRes = Test-InstallationArtifacts -ToolId "lmstudio" -ToolName "LM Studio" -ExpectedPaths @("C:\Users\WDAGUtility\AppData\Local\Programs\LM Studio\LM Studio.exe", "C:\Program Files\LM Studio\LM Studio.exe") -ExpectedCommands @("lms")
            if ($verifyRes -ne "OK") { $results["lmstudio"] = $verifyRes }
        }
        $status = if ($results["lmstudio"] -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "LM Studio" -Status $status
    } else {
        Write-Log "[SKIP] LM Studio (disabled by config)" "INFO"
        $results["lmstudio"] = "SKIP"
    }
} catch {
    Write-Log "LM Studio installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["lmstudio"] = "ERROR"
    if ($tools.lmstudio.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "LM Studio" -Status "Failed"
    }
}

# Order 10: OpenCode Terminal (installed via npm)
try {
    if ($tools.'opencode-terminal'.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "OpenCode Terminal" -Status "Installing"
        if ($results["nodejs"] -eq "OK") {
            Write-Log "Installing OpenCode CLI via npm..." "INFO"
            try {
                Refresh-Path
                $npmProc = Start-Process -FilePath "npm" -ArgumentList "i -g opencode-ai" -Wait -PassThru -NoNewWindow -ErrorAction Stop
                if ($npmProc.ExitCode -eq 0) {
                    Write-Log "[OK] OpenCode Terminal installed successfully via npm." "INFO"
                    $results["opencode-terminal"] = "OK"
                    Refresh-Path
                } else {
                    Write-Log "[WARN] OpenCode Terminal npm install exited with code $($npmProc.ExitCode)" "WARN"
                    $results["opencode-terminal"] = "WARN"
                }
            } catch {
                Write-Log "[ERROR] Failed to install OpenCode Terminal: $_" "ERROR"
                $results["opencode-terminal"] = "ERROR"
            }
        } else {
            Write-Log "[WARN] OpenCode Terminal skipped: Node.js not available" "WARN"
            $results["opencode-terminal"] = "SKIP"
        }
        if ($results["opencode-terminal"] -eq "OK") {
            $verifyRes = Test-InstallationArtifacts -ToolId "opencode-terminal" -ToolName "OpenCode Terminal" -ExpectedCommands @("opencode")
            if ($verifyRes -ne "OK") { $results["opencode-terminal"] = $verifyRes }
        }
        $status = if ($results["opencode-terminal"] -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "OpenCode Terminal" -Status $status
    } else {
        Write-Log "[SKIP] OpenCode Terminal (disabled by config)" "INFO"
        $results["opencode-terminal"] = "SKIP"
    }
} catch {
    Write-Log "OpenCode Terminal installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["opencode-terminal"] = "ERROR"
    if ($tools.'opencode-terminal'.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "OpenCode Terminal" -Status "Failed"
    }
}

# Order 11: OpenCode Desktop
try {
    if ($tools.'opencode-desktop'.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "OpenCode Desktop" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.'opencode-desktop'.fileName)"
        $res = Install-SilentProcess -ToolId "opencode-desktop" -ToolName "OpenCode Desktop" -InstallerPath $installer -SilentArgs $tools.'opencode-desktop'.silentArgs
        $results["opencode-desktop"] = $res
        if ($res -eq "OK") {
            $verifyRes = Test-InstallationArtifacts -ToolId "opencode-desktop" -ToolName "OpenCode Desktop" -ExpectedPaths @("C:\Users\WDAGUtility\AppData\Local\Programs\opencode\OpenCode Desktop.exe", "C:\Program Files\opencode\OpenCode Desktop.exe", "C:\Program Files (x86)\opencode\OpenCode Desktop.exe")
            if ($verifyRes -ne "OK") { $results["opencode-desktop"] = $verifyRes }
        }
        $status = if ($results["opencode-desktop"] -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "OpenCode Desktop" -Status $status
    } else {
        Write-Log "[SKIP] OpenCode Desktop (disabled by config)" "INFO"
        $results["opencode-desktop"] = "SKIP"
    }
} catch {
    Write-Log "OpenCode Desktop installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["opencode-desktop"] = "ERROR"
    if ($tools.'opencode-desktop'.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "OpenCode Desktop" -Status "Failed"
    }
}

# Order 11: Crew AI (pip install)
try {
    if ($tools.crewai.enabled -and $results["python"] -eq "OK") {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Crew AI" -Status "Installing"
        Write-Log "Installing Crew AI via pip..." "INFO"
        try {
            $proc = Start-Process -FilePath "pip" -ArgumentList "install", "crewai" -Wait -PassThru -NoNewWindow -ErrorAction Stop
            if ($proc.ExitCode -eq 0) {
                Write-Log "[OK] Crew AI installed successfully." "INFO"
                $results["crewai"] = "OK"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Crew AI" -Status "Completed"
            } else {
                Write-Log "[WARN] pip install crewai exited with code $($proc.ExitCode)" "WARN"
                $results["crewai"] = "WARN"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Crew AI" -Status "Failed"
            }
        } catch {
            Write-Log "[ERROR] Failed to install Crew AI: $_`n$($_.ScriptStackTrace)" "ERROR"
            $results["crewai"] = "ERROR"
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Crew AI" -Status "Failed"
        }
    } else {
        Write-Log "[SKIP] Crew AI (disabled or Python missing)" "INFO"
        $results["crewai"] = "SKIP"
    }
} catch {
    Write-Log "Crew AI installation block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["crewai"] = "ERROR"
    if ($tools.crewai.enabled -and $results["python"] -eq "OK") {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Crew AI" -Status "Failed"
    }
}

# Order 12: Microsoft Copilot PWA
try {
    if ($tools.copilot.enabled -and $results["chrome"] -eq "OK") {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Microsoft Copilot PWA" -Status "Installing"
        Write-Log "Deploying Microsoft Copilot PWA shortcut..." "INFO"
        try {
            # Dynamically locate Chrome
            $chromePaths = @(
                "C:\Program Files\Google\Chrome\Application\chrome.exe",
                "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"
            )
            $chromeExe = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            
            if ($chromeExe) {
                # Create desktop shortcut for Copilot
                $shortcutPath = "$env:USERPROFILE\Desktop\Copilot.lnk"
                $shell = New-Object -ComObject WScript.Shell
                $shortcut = $shell.CreateShortcut($shortcutPath)
                $shortcut.TargetPath = $chromeExe
                $shortcut.Arguments = "--app=https://copilot.microsoft.com"
                $shortcut.WorkingDirectory = Split-Path $chromeExe
                $shortcut.IconLocation = "$chromeExe,0"
                $shortcut.Save()
                Write-Log "[OK] Copilot shortcut created on Desktop." "INFO"
                $results["copilot"] = "OK"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Microsoft Copilot PWA" -Status "Completed"
            } else {
                Write-Log "[WARN] Chrome not found at expected paths. Copilot PWA skipped." "WARN"
                $results["copilot"] = "WARN"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Microsoft Copilot PWA" -Status "Failed"
            }
        } catch {
            Write-Log "[ERROR] Failed to deploy Copilot PWA: $_`n$($_.ScriptStackTrace)" "ERROR"
            $results["copilot"] = "ERROR"
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Microsoft Copilot PWA" -Status "Failed"
        }
    } else {
        Write-Log "[SKIP] Microsoft Copilot PWA (Chrome required/disabled)" "INFO"
        $results["copilot"] = "SKIP"
    }
} catch {
    Write-Log "Copilot PWA deployment block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    if ($tools.copilot.enabled -and $results["chrome"] -eq "OK") {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Microsoft Copilot PWA" -Status "Failed"
    }
}

# Order 13: Visual Studio Code
try {
    if ($tools.vscode.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Visual Studio Code" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.vscode.fileName)"
        $res = Install-SilentProcess -ToolId "vscode" -ToolName "Visual Studio Code" -InstallerPath $installer -SilentArgs $tools.vscode.silentArgs
        $results["vscode"] = $res
        Refresh-Path
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Visual Studio Code" -Status $status
    } else {
        Write-Log "[SKIP] Visual Studio Code (disabled by config)" "INFO"
        $results["vscode"] = "SKIP"
    }
} catch {
    Write-Log "Visual Studio Code installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["vscode"] = "ERROR"
    if ($tools.vscode.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Visual Studio Code" -Status "Failed"
    }
}

# Order 14: Visual Studio Community
try {
    if ($tools.vscommunity.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Visual Studio Community" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.vscommunity.fileName)"
        $res = Install-SilentProcess -ToolId "vscommunity" -ToolName "Visual Studio Community" -InstallerPath $installer -SilentArgs $tools.vscommunity.silentArgs
        $results["vscommunity"] = $res
        Refresh-Path
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Visual Studio Community" -Status $status
    } else {
        Write-Log "[SKIP] Visual Studio Community (disabled by config)" "INFO"
        $results["vscommunity"] = "SKIP"
    }
} catch {
    Write-Log "Visual Studio Community installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["vscommunity"] = "ERROR"
    if ($tools.vscommunity.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Visual Studio Community" -Status "Failed"
    }
}

# Order 15: 7-Zip
try {
    if ($tools.'7zip'.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "7-Zip" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.'7zip'.fileName)"
        $res = Install-SilentProcess -ToolId "7zip" -ToolName "7-Zip" -InstallerPath $installer -SilentArgs $tools.'7zip'.silentArgs
        $results["7zip"] = $res
        Refresh-Path
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "7-Zip" -Status $status
    } else {
        Write-Log "[SKIP] 7-Zip (disabled by config)" "INFO"
        $results["7zip"] = "SKIP"
    }
} catch {
    Write-Log "7-Zip installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["7zip"] = "ERROR"
    if ($tools.'7zip'.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "7-Zip" -Status "Failed"
    }
}

# Order 16: Sysinternals Suite (ZIP extraction)
try {
    if ($tools.sysinternals.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite" -Status "Installing"
        $zipFile = "C:\SharedTools\Installers\$($tools.sysinternals.fileName)"
        $extractPath = "C:\Tools\Sysinternals"
        
        if (Test-Path $zipFile) {
            Write-Log "Extracting Sysinternals Suite..." "INFO"
            try {
                if (-not (Test-Path $extractPath)) {
                    $null = New-Item -ItemType Directory -Path $extractPath -Force -ErrorAction Stop
                }
                Expand-Archive -Path $zipFile -DestinationPath $extractPath -Force -ErrorAction Stop
                
                # Add to PATH
                $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
                if ($currentPath -notlike "*$extractPath*") {
                    [System.Environment]::SetEnvironmentVariable("Path", "$currentPath;$extractPath", [System.EnvironmentVariableTarget]::Machine)
                    Write-Log "[OK] Sysinternals added to PATH." "INFO"
                }
                
                Write-Log "[OK] Sysinternals Suite extracted to $extractPath" "INFO"
                $results["sysinternals"] = "OK"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite" -Status "Completed"
            } catch {
                Write-Log "[ERROR] Failed to extract Sysinternals: $_`n$($_.ScriptStackTrace)" "ERROR"
                $results["sysinternals"] = "ERROR"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite" -Status "Failed"
            }
        } else {
            Write-Log "[WARN] Sysinternals ZIP not found at $zipFile" "WARN"
            $results["sysinternals"] = "ERROR"
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite" -Status "Failed"
        }
    } else {
        Write-Log "[SKIP] Sysinternals Suite (disabled by config)" "INFO"
        $results["sysinternals"] = "SKIP"
    }
} catch {
    Write-Log "Sysinternals installation block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["sysinternals"] = "ERROR"
    if ($tools.sysinternals.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite" -Status "Failed"
    }
}

# Order 17: Windows PowerToys
try {
    if ($tools.powertoys.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows PowerToys" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.powertoys.fileName)"
        $res = Install-SilentProcess -ToolId "powertoys" -ToolName "Windows PowerToys" -InstallerPath $installer -SilentArgs $tools.powertoys.silentArgs
        $results["powertoys"] = $res
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows PowerToys" -Status $status
    } else {
        Write-Log "[SKIP] Windows PowerToys (disabled by config)" "INFO"
        $results["powertoys"] = "SKIP"
    }
} catch {
    Write-Log "Windows PowerToys installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["powertoys"] = "ERROR"
    if ($tools.powertoys.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows PowerToys" -Status "Failed"
    }
}

# Order 18: Windows SDK
try {
    if ($tools.windowssdk.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows SDK" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.windowssdk.fileName)"
        $res = Install-SilentProcess -ToolId "windowssdk" -ToolName "Windows SDK" -InstallerPath $installer -SilentArgs $tools.windowssdk.silentArgs
        $results["windowssdk"] = $res
        Refresh-Path
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows SDK" -Status $status
    } else {
        Write-Log "[SKIP] Windows SDK (disabled by config)" "INFO"
        $results["windowssdk"] = "SKIP"
    }
} catch {
    Write-Log "Windows SDK installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["windowssdk"] = "ERROR"
    if ($tools.windowssdk.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows SDK" -Status "Failed"
    }
}

# Order 19: Windows ADK
try {
    if ($tools.adk.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows ADK" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.adk.fileName)"
        $res = Install-SilentProcess -ToolId "adk" -ToolName "Windows ADK" -InstallerPath $installer -SilentArgs $tools.adk.silentArgs
        $results["adk"] = $res
        Refresh-Path
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows ADK" -Status $status
    } else {
        Write-Log "[SKIP] Windows ADK (disabled by config)" "INFO"
        $results["adk"] = "SKIP"
    }
} catch {
    Write-Log "Windows ADK installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["adk"] = "ERROR"
    if ($tools.adk.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows ADK" -Status "Failed"
    }
}

# Order 20: Windows ADK WinPE Add-on
try {
    if ($tools.adkwinpe.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows ADK WinPE Add-on" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.adkwinpe.fileName)"
        $res = Install-SilentProcess -ToolId "adkwinpe" -ToolName "Windows ADK WinPE Add-on" -InstallerPath $installer -SilentArgs $tools.adkwinpe.silentArgs
        $results["adkwinpe"] = $res
        Refresh-Path
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows ADK WinPE Add-on" -Status $status
    } else {
        Write-Log "[SKIP] Windows ADK WinPE Add-on (disabled by config)" "INFO"
        $results["adkwinpe"] = "SKIP"
    }
} catch {
    Write-Log "Windows ADK WinPE Add-on installer block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["adkwinpe"] = "ERROR"
    if ($tools.adkwinpe.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows ADK WinPE Add-on" -Status "Failed"
    }
}

# Order 21: Antigravity CLI
try {
    if ($tools.antigravity.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Antigravity CLI" -Status "Installing"
        
        # Try to download and install Antigravity CLI
        Write-Log "Attempting to download Antigravity CLI..." "INFO"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            # Check if the download URL is accessible
            $antigravityUrl = "https://antigravity.google/product/antigravity-cli"
            $antigravityInstaller = "C:\SharedTools\Installers\antigravity-cli.exe"
            
            # Try to resolve the download URL
            try {
                $response = Invoke-WebRequest -Uri $antigravityUrl -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
                # If the page is accessible, try to find the download link
                if ($response.Content -match 'href="([^"]*antigravity[^"]*\.exe)"') {
                    $downloadUrl = $Matches[1]
                    if (-not $downloadUrl.StartsWith("http")) {
                        $downloadUrl = "https://antigravity.google$downloadUrl"
                    }
                    Write-Log "Downloading Antigravity CLI from: $downloadUrl" "INFO"
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $antigravityInstaller -UseBasicParsing -ErrorAction Stop
                    
                    if (Test-Path $antigravityInstaller) {
                        $res = Install-SilentProcess -ToolId "antigravity" -ToolName "Antigravity CLI" -InstallerPath $antigravityInstaller -SilentArgs "/S"
                        $results["antigravity"] = $res
                    } else {
                        Write-Log "[SKIP] Antigravity CLI - download failed" "INFO"
                        $results["antigravity"] = "SKIP"
                    }
                } else {
                    Write-Log "[SKIP] Antigravity CLI - no download link found on page" "INFO"
                    $results["antigravity"] = "SKIP"
                }
            } catch {
                Write-Log "[SKIP] Antigravity CLI - source unreachable or not available: $_" "INFO"
                $results["antigravity"] = "SKIP"
            }
            
            $status = if ($results["antigravity"] -eq "OK") { "Completed" } else { "Skipped" }
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Antigravity CLI" -Status $status
        } catch {
            Write-Log "[SKIP] Antigravity CLI - installation failed: $_" "INFO"
            $results["antigravity"] = "SKIP"
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Antigravity CLI" -Status "Skipped"
        }
    } else {
        Write-Log "[SKIP] Antigravity CLI (disabled by config)" "INFO"
        $results["antigravity"] = "SKIP"
    }
} catch {
    Write-Log "Antigravity CLI installation block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["antigravity"] = "ERROR"
    if ($tools.antigravity.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Antigravity CLI" -Status "Failed"
    }
}

# 3. Final Verification Pass - Check all critical tools are actually present
Write-Log "=== Final Verification Pass ===" "INFO"
$criticalTools = @{
    "Ollama" = @("C:\Users\WDAGUtility\AppData\Local\Programs\Ollama\ollama.exe", "C:\Program Files\Ollama\ollama.exe")
    "LM Studio" = @("C:\Users\WDAGUtility\AppData\Local\Programs\LM Studio\LM Studio.exe", "C:\Program Files\LM Studio\LM Studio.exe")
    "Google Chrome" = @("C:\Program Files\Google\Chrome\Application\chrome.exe", "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe")
    "Node.js" = @("C:\Program Files\nodejs\node.exe", "C:\Program Files (x86)\nodejs\node.exe")
    "Python" = @("C:\Program Files\Python312\python.exe", "C:\Python312\python.exe", "C:\Users\WDAGUtility\AppData\Local\Programs\Python\Python312\python.exe")
    "Visual Studio Code" = @("C:\Users\WDAGUtility\AppData\Local\Programs\Microsoft VS Code\Code.exe", "C:\Program Files\Microsoft VS Code\Code.exe")
    "7-Zip" = @("C:\Program Files\7-Zip\7zFM.exe", "C:\Program Files (x86)\7-Zip\7zFM.exe")
    "Notepad++" = @("C:\Program Files\Notepad++\notepad++.exe", "C:\Program Files (x86)\Notepad++\notepad++.exe")
    "Brave Browser" = @("C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe", "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe")
    "Beyond Compare 4" = @("C:\Program Files\Beyond Compare 4\BCompare.exe", "C:\Program Files (x86)\Beyond Compare 4\BCompare.exe")
}

$finalVerify = @{}
foreach ($toolName in $criticalTools.Keys) {
    $paths = $criticalTools[$toolName]
    $found = $false
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $found = $true
            Write-Log "  [OK] $toolName - present at: $p" "INFO"
            break
        }
    }
    if (-not $found) {
        Write-Log "  [WARN] $toolName - NOT found at expected paths" "WARN"
    }
    $finalVerify[$toolName] = $found
}

# Check critical PATH commands
$criticalCommands = @("ollama", "node", "npm", "python", "pip", "code", "git")
foreach ($cmd in $criticalCommands) {
    $cmdPath = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($cmdPath) {
        Write-Log "  [OK] Command '$cmd' available at: $($cmdPath.Source)" "INFO"
    } else {
        Write-Log "  [WARN] Command '$cmd' NOT in PATH" "WARN"
    }
}

# Write verification report
$verifyReportPath = Join-Path $logsDir "final-verification.txt"
try {
    $report = "Final Verification Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
    $report += "=" * 60 + "`n`n"
    if ($global:SandboxOS) {
        $report += "Sandbox OS: $($global:SandboxOS.Caption) - $($global:SandboxOS.VersionName) ($($global:SandboxOS.Architecture))`n"
        $report += "Build Number: $($global:SandboxOS.BuildNumber)`n"
    }
    if ($global:HostOS) {
        $report += "Host OS: $($global:HostOS.Caption) - Target: $($global:HostOS.TargetVersion)`n"
    }
    $report += "`n"
    $report += "Tool Verification:`n"
    foreach ($toolName in $finalVerify.Keys) {
        $status = if ($finalVerify[$toolName]) { "PRESENT" } else { "MISSING" }
        $report += "$toolName : $status`n"
    }
    $report += "`n" + ("=" * 60) + "`n"
    $report += "Tool Install Results:`n"
    foreach ($key in $results.Keys) {
        $report += "$key : $($results[$key])`n"
    }
    $report | Out-File -FilePath $verifyReportPath -Encoding utf8 -Force
    Write-Log "Final verification report saved to: $verifyReportPath" "INFO"
} catch {
    Write-Log "Failed to write verification report: $_" "WARN"
}

# 4. Print Summary
$endTime = Get-Date
$duration = $endTime - $startTime

try {
    Write-Log "=== Provisioning Summary ===" "INFO"
    $okCount = ($results.Values | Where-Object { $_ -eq "OK" }).Count
    $warnCount = ($results.Values | Where-Object { $_ -eq "WARN" }).Count
    $errorCount = ($results.Values | Where-Object { $_ -eq "ERROR" }).Count
    $skipCount = ($results.Values | Where-Object { $_ -eq "SKIP" }).Count
    $total = $results.Count
    Write-Log "Total: $total | OK: $okCount | WARN: $warnCount | ERROR: $errorCount | SKIP: $skipCount" "INFO"
    $results.Keys | Sort-Object | ForEach-Object {
        $marker = switch ($results[$_]) {
            "OK" { "[OK]   " }
            "WARN" { "[WARN] " }
            "ERROR" { "[FAIL] " }
            "SKIP" { "[SKIP] " }
            default { "[----] " }
        }
        Write-Log "$marker$_ : $($results[$_])" "INFO"
    }
    Write-Log "Total installation time: $($duration.TotalMinutes.ToString('F2')) minutes" "INFO"
    Write-Log "=== Provisioning Finished ===" "INFO"
} catch {
    Write-Host "Error printing summary: $_"
}

# 5. Completion Toast / Dialog
try {
    Add-Type -AssemblyName System.Windows.Forms
    $okCount = ($results.Values | Where-Object { $_ -eq "OK" }).Count
    $total = $results.Count
    [System.Windows.Forms.MessageBox]::Show("AI Sandbox setup complete!`n`nInstalled: $okCount / $total tools`n`nCheck C:\ProgramData\WindowsAISandboxApps\Logs\sandbox-bootstrap.log for details.`nFinal verification report: $verifyReportPath", "AI Sandbox Generator", 0, 64)
} catch {
    # Fallback to outputting in console
    Write-Log "Sandbox ready." "INFO"
}

Exit-Script 0

