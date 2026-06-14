# sandbox-bootstrap.ps1 - Windows AI Sandbox Logon Script
# Runs inside the sandbox at startup

$ErrorActionPreference = "Continue"
$startTime = Get-Date

# Setup Logs Directory
$logsDir = "C:\ProgramData\AIWindowsSandbox\Logs"
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

# 1. Read configuration
try {
    $configPath = "C:\SharedTools\install-config.json"
    if (-not (Test-Path $configPath)) {
        Write-Log "Configuration file not found at $configPath. Exiting bootstrap." "ERROR"
        Exit-Script 1
    }
    $config = Get-Content -Raw -Path $configPath -ErrorAction Stop | ConvertFrom-Json
    $tools = $config.tools

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
            $progressFile = "C:\ProgramData\AIWindowsSandbox\Logs\install-progress.json"
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
        [string]$SilentArgs
    )
    
    if (-not (Test-Path $InstallerPath)) {
        Write-Log "Installer for $ToolName not found at $InstallerPath" "ERROR"
        return "ERROR"
    }

    Write-Log "Installing $ToolName silently..." "INFO"
    try {
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList $SilentArgs -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($proc.ExitCode -eq 0) {
            Write-Log "[$ToolName] installed successfully." "INFO"
            return "OK"
        } else {
            Write-Log "[$ToolName] installer exited with code $($proc.ExitCode)" "WARN"
            return "WARN"
        }
    } catch {
        Write-Log "Failed to install $($ToolName): $_`n$($_.ScriptStackTrace)" "ERROR"
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
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
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
            $pythonInstaller = "C:\SharedTools\Installers\python-installer.exe"
            if (Test-Path $pythonInstaller) {
                Write-Log "Installing Python silently..." "INFO"
                try {
                    $proc = Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" -Wait -PassThru -NoNewWindow -ErrorAction Stop
                    if ($proc.ExitCode -eq 0) {
                        Write-Log "[OK] Python installed successfully." "INFO"
                        $results["python"] = "OK"
                        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Python" -Status "Completed"
                    } else {
                        Write-Log "[WARN] Python installer exited with code $($proc.ExitCode)" "WARN"
                        $results["python"] = "WARN"
                        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Python" -Status "Failed"
                    }
                } catch {
                    Write-Log "[ERROR] Python installation failed: $_`n$($_.ScriptStackTrace)" "ERROR"
                    $results["python"] = "ERROR"
                    Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Python" -Status "Failed"
                }
                Refresh-Path
            } else {
                Write-Log "[WARN] Python installer not found at $pythonInstaller. Cannot install CrewAI." "WARN"
                $results["python"] = "ERROR"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Python" -Status "Failed"
            }
        } else {
            Write-Log "[OK] Python already installed." "INFO"
            $results["python"] = "OK"
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Python" -Status "Completed"
        }
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
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
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
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
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
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
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
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
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
        $res = Install-SilentProcess -ToolId "ollama" -ToolName "Ollama" -InstallerPath $installer -SilentArgs $tools.ollama.silentArgs
        $results["ollama"] = $res

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
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
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

# Order 10: OpenCode Terminal
try {
    if ($tools.'opencode-terminal'.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "OpenCode Terminal" -Status "Installing"
        $installer = "C:\SharedTools\Installers\$($tools.'opencode-terminal'.fileName)"
        $res = Install-SilentProcess -ToolId "opencode-terminal" -ToolName "OpenCode Terminal" -InstallerPath $installer -SilentArgs $tools.'opencode-terminal'.silentArgs
        $results["opencode-terminal"] = $res
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
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
        $status = if ($res -eq "OK") { "Completed" } else { "Failed" }
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
        Write-Log "Installing Microsoft Copilot PWA..." "INFO"
        try {
            Start-Process -FilePath "C:\Program Files\Google\Chrome\Application\chrome.exe" -ArgumentList "--app=https://copilot.microsoft.com --install-webapp" -Wait -NoNewWindow -ErrorAction Stop
            Write-Log "[OK] Microsoft Copilot PWA deployed. (Note: Sign-in is required inside sandbox)" "INFO"
            $results["copilot"] = "OK"
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Microsoft Copilot PWA" -Status "Completed"
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

# 3. Print Summary
$endTime = Get-Date
$duration = $endTime - $startTime

try {
    Write-Log "=== Provisioning Summary ===" "INFO"
    $results.Keys | ForEach-Object {
        Write-Log "$_ : $($results[$_])" "INFO"
    }
    Write-Log "Total installation time: $($duration.TotalMinutes.ToString('F2')) minutes" "INFO"
    Write-Log "=== Provisioning Finished ===" "INFO"
} catch {
    Write-Host "Error printing summary: $_"
}

# 4. Completion Toast / Dialog
try {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show("AI Sandbox setup complete! Check C:\ProgramData\AIWindowsSandbox\Logs\sandbox-bootstrap.log for details.", "AI Sandbox Generator", 0, 64)
} catch {
    # Fallback to outputting in console
    Write-Log "Sandbox ready." "INFO"
}

Exit-Script 0

