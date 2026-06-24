# sandbox-bootstrap.ps1 - Windows AI Sandbox Logon Script
# Runs inside the sandbox at startup

[CmdletBinding()]
param(
    [switch]$NoStatusWindow
)

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

# Initialize the status-window JSON files immediately so the polling timer
# always finds a valid file from its very first tick. Without this, the
# progress bar would stay at 0 and the form would show "Initializing..."
# until the first Update-InstallProgress call inside the install chain.
try {
    $initProgress = @{
        currentStep   = 0
        totalSteps     = 0
        activeInstall = "Starting"
        status        = "Initializing"
    } | ConvertTo-Json -Compress
    $initCounters = @{
        ok      = 0
        failed  = 0
        skipped = 0
        total   = 0
    } | ConvertTo-Json -Compress
    $progressFile = "C:\ProgramData\WindowsAISandboxApps\Logs\install-progress.json"
    $countersFile = "C:\ProgramData\WindowsAISandboxApps\Logs\status-counters.json"
    $null = New-Item -ItemType Directory -Path (Split-Path $progressFile) -Force -ErrorAction SilentlyContinue
    $initProgress | Out-File -FilePath $progressFile -Encoding utf8 -Force -ErrorAction SilentlyContinue
    $initCounters | Out-File -FilePath $countersFile -Encoding utf8 -Force -ErrorAction SilentlyContinue
} catch {}

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

# ============================================================================
# Status Window (translucent bottom-right popup) - WinForms based
# ============================================================================
# Loaded early so the form is visible from the first install step onward.
# All cross-thread communication is via install-progress.json (no runspace
# marshaling needed). The form thread polls that file via a System.Windows.
# Forms.Timer. The install chain runs on a background runspace below.
$script:StatusWindow = $null
$script:StatusForm = $null
$script:StatusLabels = $null
$script:StatusProgress = $null
$script:StatusProgressOverlay = $null
$script:StatusTimer = $null
$script:StatusOpacityLabel = $null
$script:StatusTrackBar = $null
$script:StatusOkButton = $null
$script:StatusSummaryPanel = $null
$script:StatusMainPanel = $null
$script:StatusSummaryDone = $false
$script:StatusUpdateFromProgress = $null
$script:StatusWindowShown = $false

function Initialize-StatusWindow {
    if ($NoStatusWindow) { return $false }
    try {
        if (-not ([System.Management.Automation.PSTypeName]'System.Windows.Forms.Form').Type) {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        }
        if (-not ([System.Management.Automation.PSTypeName]'System.Drawing').Type) {
            Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        }
    } catch {
        Write-Log "Status window: failed to load WinForms/Drawing assemblies: $_" "WARN"
        return $false
    }
    return $true
}

function New-StatusWindow {
    if ($NoStatusWindow) { return }
    if (-not (Initialize-StatusWindow)) { return }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Windows AI Sandbox - Installing..."
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.Opacity = 0.90
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $form.ClientSize = New-Object System.Drawing.Size(380, 170)
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.MinimumSize = New-Object System.Drawing.Size(380, 170)
    $form.MaximumSize = New-Object System.Drawing.Size(380, 170)
    $form.BackColor = [System.Drawing.Color]::White

    # Position at bottom-right of the primary working area (above the taskbar)
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $x = $wa.Right - $form.Width - 10
        $y = $wa.Bottom - $form.Height - 10
        $form.Location = New-Object System.Drawing.Point($x, $y)
    } catch {
        # Fallback to a sane default
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    }

    # Main panel (live progress)
    $mainPanel = New-Object System.Windows.Forms.Panel
    $mainPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $mainPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    $form.Controls.Add($mainPanel)

    # Step label
    $stepLabel = New-Object System.Windows.Forms.Label
    $stepLabel.AutoSize = $false
    $stepLabel.Location = New-Object System.Drawing.Point(12, 12)
    $stepLabel.Size = New-Object System.Drawing.Size(356, 20)
    $stepLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $stepLabel.Text = "Initializing..."
    $stepLabel.ForeColor = [System.Drawing.Color]::Black
    $mainPanel.Controls.Add($stepLabel)

    # Progress bar
    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Location = New-Object System.Drawing.Point(12, 38)
    $progress.Size = New-Object System.Drawing.Size(356, 22)
    $progress.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
    $progress.Minimum = 0
    $progress.Maximum = 100
    $progress.Value = 0
    $mainPanel.Controls.Add($progress)

    # Centered overlay label on the progress bar showing the "cur / total"
    # text. Placed at the same coordinates as the bar with a transparent
    # background. WinForms ProgressBar cannot render text natively, so we
    # use a Label on top.
    $progressOverlay = New-Object System.Windows.Forms.Label
    $progressOverlay.AutoSize = $false
    $progressOverlay.Location = $progress.Location
    $progressOverlay.Size = $progress.Size
    $progressOverlay.Text = "0 / 0"
    $progressOverlay.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $progressOverlay.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $progressOverlay.BackColor = [System.Drawing.Color]::Transparent
    $progressOverlay.ForeColor = [System.Drawing.Color]::Black
    $mainPanel.Controls.Add($progressOverlay)
    # Re-add the progress bar to ensure it sits beneath the overlay label.
    # (WinForms draws controls in the order they were added; the bar was
    # added first, so the overlay sits on top - which is what we want.)
    $mainPanel.Controls.SetChildIndex($progress, 0)
    $mainPanel.Controls.SetChildIndex($progressOverlay, 1)

    # Counters label
    $counters = New-Object System.Windows.Forms.Label
    $counters.AutoSize = $false
    $counters.Location = New-Object System.Drawing.Point(12, 66)
    $counters.Size = New-Object System.Drawing.Size(356, 20)
    $counters.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $counters.Text = "Installed: 0    Failed: 0    Skipped: 0"
    $counters.ForeColor = [System.Drawing.Color]::Black
    $mainPanel.Controls.Add($counters)

    # Opacity row label
    $opacityText = New-Object System.Windows.Forms.Label
    $opacityText.AutoSize = $true
    $opacityText.Location = New-Object System.Drawing.Point(12, 100)
    $opacityText.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $opacityText.Text = "Opacity:"
    $opacityText.ForeColor = [System.Drawing.Color]::DimGray
    $mainPanel.Controls.Add($opacityText)

    # Opacity TrackBar (slider)
    $track = New-Object System.Windows.Forms.TrackBar
    $track.Location = New-Object System.Drawing.Point(60, 94)
    $track.Size = New-Object System.Drawing.Size(220, 30)
    $track.Minimum = 30
    $track.Maximum = 100
    $track.Value = 90
    $track.TickFrequency = 10
    $track.TickStyle = [System.Windows.Forms.TickStyle]::None
    $mainPanel.Controls.Add($track)

    # Opacity value label
    $opacityValue = New-Object System.Windows.Forms.Label
    $opacityValue.AutoSize = $true
    $opacityValue.Location = New-Object System.Drawing.Point(290, 100)
    $opacityValue.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $opacityValue.Text = "90%"
    $opacityValue.ForeColor = [System.Drawing.Color]::DimGray
    $mainPanel.Controls.Add($opacityValue)

    # Wire opacity slider: changing it updates the form's Opacity
    $track.Add_ValueChanged({
        param($s, $e)
        try {
            $form.Opacity = [Math]::Max(0.30, [Math]::Min(1.0, $s.Value / 100.0))
            $opacityValue.Text = "$($s.Value)%"
        } catch {}
    })

    # Hidden summary panel (revealed on completion)
    $summaryPanel = New-Object System.Windows.Forms.Panel
    $summaryPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $summaryPanel.Padding = New-Object System.Windows.Forms.Padding(12)
    $summaryPanel.Visible = $false
    $form.Controls.Add($summaryPanel)

    $summaryTitle = New-Object System.Windows.Forms.Label
    $summaryTitle.AutoSize = $false
    $summaryTitle.Location = New-Object System.Drawing.Point(12, 10)
    $summaryTitle.Size = New-Object System.Drawing.Size(356, 24)
    $summaryTitle.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $summaryTitle.Text = "Installation Complete"
    $summaryTitle.ForeColor = [System.Drawing.Color]::Black
    $summaryPanel.Controls.Add($summaryTitle)

    $summaryText = New-Object System.Windows.Forms.Label
    $summaryText.AutoSize = $false
    $summaryText.Location = New-Object System.Drawing.Point(12, 42)
    $summaryText.Size = New-Object System.Drawing.Size(356, 70)
    $summaryText.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $summaryText.Text = "Installed: 0`r`nFailed: 0`r`nSkipped: 0`r`nSee sandbox-bootstrap.log for details."
    $summaryText.ForeColor = [System.Drawing.Color]::Black
    $summaryPanel.Controls.Add($summaryText)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Size = New-Object System.Drawing.Size(100, 32)
    $okButton.Location = New-Object System.Drawing.Point(140, 120)
    $okButton.Text = "OK"
    $okButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $okButton.UseCompatibleTextRendering = $false
    $summaryPanel.Controls.Add($okButton)

    # OK button closes the form
    $okButton.Add_Click({
        try { $script:StatusSummaryDone = $true; $form.Close() } catch {}
    })

    # Inner closure function: reads install-progress.json + status-counters.json
    # and pushes the values into the form's controls. This is the source of
    # truth for the popup's labels. Called directly from Update-InstallProgress
    # at every step boundary, and also from the safety-net Timer below.
    # Captures $progress, $progressOverlay, $stepLabel, $counters from the
    # enclosing New-StatusWindow scope via PowerShell closure semantics.
    $updateFromProgress = {
        try {
            $progressFile = "C:\ProgramData\WindowsAISandboxApps\Logs\install-progress.json"
            if (Test-Path $progressFile) {
                $raw = Get-Content -Raw -Path $progressFile -ErrorAction SilentlyContinue
                if ($raw) {
                    $data = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($data) {
                        $cur = [int]$data.currentStep
                        $tot = [int]$data.totalSteps
                        $active = [string]$data.activeInstall
                        $status = [string]$data.status

                        # Always update the bar, even when total is 0.
                        # If total is 0, percentage is 0. If current
                        # exceeds total, clamp to 100.
                        if ($tot -gt 0) {
                            $pct = [int]([Math]::Round(($cur / $tot) * 100))
                        } else {
                            $pct = 0
                        }
                        if ($pct -lt 0) { $pct = 0 }
                        if ($pct -gt 100) { $pct = 100 }
                        if ($progress.Value -ne $pct) { $progress.Value = $pct }

                        # Centered overlay label on the progress bar
                        if ($progressOverlay -and ($progressOverlay.Text -ne "$cur / $tot")) {
                            $progressOverlay.Text = "$cur / $tot"
                        }

                        if ($cur -gt 0 -or $tot -gt 0) {
                            $stepLabel.Text = "Step $cur / $tot - $active ($status)"
                        }

                        # Counters file
                        $countersFile = "C:\ProgramData\WindowsAISandboxApps\Logs\status-counters.json"
                        if (Test-Path $countersFile) {
                            try {
                                $crow = Get-Content -Raw -Path $countersFile -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
                                if ($crow) {
                                    $okC = [int]$crow.ok
                                    $failC = [int]$crow.failed
                                    $skipC = [int]$crow.skipped
                                    $counters.Text = "Installed: $okC    Failed: $failC    Skipped: $skipC"
                                }
                            } catch {}
                        }
                    }
                }
            }
        } catch {}
    }

    # Safety-net polling timer: kicks in during long Start-Process -Wait calls
    # where Update-InstallProgress isn't being called. Reads the JSON every 500ms
    # and pushes into the form. The direct call from Update-InstallProgress is
    # the primary refresh path; this timer is just a fallback.
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 500
    $timer.Add_Tick($updateFromProgress)

    # Wire FormClosing: allow only via OK button
    $form.Add_FormClosing({
        param($s, $e)
        if (-not $script:StatusSummaryDone -and -not $script:StatusWindowShown) {
            # Closing from outside (e.g. ALT+F4, X button) before summary -> cancel
            $e.Cancel = $true
        }
    })

    $script:StatusForm = $form
    $script:StatusLabels = @{
        Step = $stepLabel
        Counters = $counters
        OpacityValue = $opacityValue
    }
    $script:StatusProgress = $progress
    $script:StatusProgressOverlay = $progressOverlay
    $script:StatusTrackBar = $track
    $script:StatusOpacityLabel = $opacityValue
    $script:StatusOkButton = $okButton
    $script:StatusSummaryPanel = $summaryPanel
    $script:StatusMainPanel = $mainPanel
    $script:StatusUpdateFromProgress = $updateFromProgress
    $script:StatusTimer = $timer
    $script:StatusSummaryText = $summaryText
    $script:StatusSummaryTitle = $summaryTitle

    # Show the form non-modally and start the polling timer
    $form.Show()
    $script:StatusWindowShown = $true
    $timer.Start()
}

function Show-StatusSummary {
    param(
        [int]$InstalledCount,
        [int]$FailedCount,
        [int]$SkippedCount
    )
    if ($NoStatusWindow -or -not $script:StatusForm) { return }
    try {
        if ($script:StatusTimer) { $script:StatusTimer.Stop() }
        $script:StatusMainPanel.Visible = $false
        $script:StatusSummaryPanel.Visible = $true
        $script:StatusSummaryText.Text = "Installed: $InstalledCount`r`nFailed: $FailedCount`r`nSkipped: $SkippedCount`r`nSee sandbox-bootstrap.log for details."
        # Bring form to front
        $script:StatusForm.TopMost = $false
        $script:StatusForm.TopMost = $true
        $script:StatusForm.Activate()
    } catch {}
}

function Close-StatusWindow {
    if ($NoStatusWindow -or -not $script:StatusForm) { return }
    try {
        $script:StatusSummaryDone = $true
        if ($script:StatusTimer) { $script:StatusTimer.Stop() }
        $script:StatusForm.Close()
        $script:StatusForm.Dispose()
    } catch {}
}

# Create and show the form after the initial progress JSON has been written
# (the form's polling timer reads that file). If we created the form here
# before the first Update-InstallProgress call, the timer would briefly
# find no JSON file and the bar would stick at 0. The form is created lazily
# in the catch block of the config read below.


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
    if ($tools.beyondcompare.enabled) { [void]$enabledSteps.Add("Beyond Compare 5 (Portable)") }
    if ($tools.'bcompare-vscode'.enabled) { [void]$enabledSteps.Add("Beyond Compare VSCode Extension") }
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
    if ($tools.sysinternals.enabled) { [void]$enabledSteps.Add("Sysinternals Suite + Sysmon") }
    if ($tools.powertoys.enabled) { [void]$enabledSteps.Add("Windows PowerToys") }
    if ($tools.windowssdk.enabled) { [void]$enabledSteps.Add("Windows SDK") }
    if ($tools.adk.enabled) { [void]$enabledSteps.Add("Windows ADK") }
    if ($tools.adkwinpe.enabled) { [void]$enabledSteps.Add("Windows ADK WinPE Add-on") }
    if ($tools.antigravity.enabled) { [void]$enabledSteps.Add("Antigravity CLI") }

    $global:totalSteps = $enabledSteps.Count
    $global:currentStep = 0

    # Brief settle delay: right after the sandbox boots, Windows Defender is
    # often still scanning the files in the mapped share. Without this delay
    # every copy fails on the first attempt with "being used by another
    # process". A 2-second wait dramatically reduces the retry count.
    Write-Log "Settling for 2 seconds to let Windows Defender finish initial scanning..." "INFO"
    Start-Sleep -Seconds 2

    # Copy installers from read-only C:\SharedTools\Installers to writable C:\ProgramData\WindowsAISandboxApps\Installers
    # Retries up to 5 times per file with 1s backoff. The mapped share is often
    # briefly locked by Windows Defender right after the sandbox boots, so the
    # first attempt frequently fails with "being used by another process".
    # If a file at the destination already exists with the same size as the
    # source, skip the copy (saves time on interrupted re-runs).
    try {
        $sandboxInstallersDir = "C:\ProgramData\WindowsAISandboxApps\Installers"
        $sharedInstallersDir = "C:\SharedTools\Installers"
        $null = New-Item -ItemType Directory -Path $sandboxInstallersDir -Force -ErrorAction Stop
        Write-Log "Copying installers from $sharedInstallersDir to $sandboxInstallersDir..." "INFO"
        if (Test-Path $sharedInstallersDir) {
            $copiedCount = 0
            $skippedCount = 0
            $failedCount = 0
            $maxRetries = 5
            $retryDelayMs = 1000
            Get-ChildItem -Path $sharedInstallersDir -File -ErrorAction SilentlyContinue | ForEach-Object {
                $destPath = Join-Path $sandboxInstallersDir $_.Name
                $sourceSize = $_.Length

                # Skip if destination already has the same-sized valid file
                if (Test-Path -LiteralPath $destPath) {
                    $destSize = (Get-Item -LiteralPath $destPath -ErrorAction SilentlyContinue).Length
                    if ($destSize -eq $sourceSize -and $destSize -gt 100KB) {
                        $skippedCount++
                        Write-Log "  Skipped (already present, $([math]::Round($destSize/1MB, 2)) MB): $($_.Name)" "INFO"
                        return
                    }
                }

                $success = $false
                for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
                    try {
                        Copy-Item -Path $_.FullName -Destination $destPath -Force -ErrorAction Stop
                        $copiedCount++
                        $success = $true
                        Write-Log "  Copied: $($_.Name) ($([math]::Round($sourceSize / 1MB, 2)) MB)" "INFO"
                        break
                    } catch {
                        if ($attempt -lt $maxRetries) {
                            Write-Log "  Copy attempt $attempt/$maxRetries for $($_.Name) failed (likely Defender lock): $_" "WARN"
                            Start-Sleep -Milliseconds $retryDelayMs
                        } else {
                            Write-Log "  [ERROR] Giving up on $($_.Name) after $maxRetries attempts: $_" "ERROR"
                        }
                    }
                }
                if (-not $success) { $failedCount++ }
            }
            Write-Log "Installer copy complete: $copiedCount copied, $skippedCount skipped, $failedCount failed" "INFO"

            # Fail fast: if not a single installer made it across, the install
            # chain will fail for every tool. Better to abort with a clear
            # error than silently run 22 install blocks that all fail.
            if (($copiedCount + $skippedCount) -eq 0) {
                Write-Log "[ERROR] No installers could be copied from the mapped share. The share may be inaccessible or fully locked by Windows Defender. Aborting." "ERROR"
                Exit-Script 1
            }
        } else {
            Write-Log "[WARN] Source installers directory not found: $sharedInstallersDir" "WARN"
        }
    } catch {
        Write-Log "Failed to copy installers: $_`n$($_.ScriptStackTrace)" "ERROR"
    }

    # Copy extensions from read-only C:\SharedTools\Extensions to writable C:\ProgramData\WindowsAISandboxApps\Extensions
    # This avoids Windows Defender blocking installations run from the mapped share
    try {
        $sandboxExtensionsDir = "C:\ProgramData\WindowsAISandboxApps\Extensions"
        $sharedExtensionsDir = "C:\SharedTools\Extensions"
        $null = New-Item -ItemType Directory -Path $sandboxExtensionsDir -Force -ErrorAction Stop
        Write-Log "Copying extensions from $sharedExtensionsDir to $sandboxExtensionsDir..." "INFO"
        if (Test-Path $sharedExtensionsDir) {
            $copiedCount = 0
            $skippedCount = 0
            Get-ChildItem -Path $sharedExtensionsDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $destPath = Join-Path $sandboxExtensionsDir $_.Name
                try {
                    if ($_.PSIsContainer) {
                        Copy-Item -Path $_.FullName -Destination $destPath -Recurse -Force -ErrorAction Stop
                    } else {
                        Copy-Item -Path $_.FullName -Destination $destPath -Force -ErrorAction Stop
                    }
                    $copiedCount++
                    $sizeStr = if ($_.PSIsContainer) { "(folder)" } else { "($([math]::Round($_.Length / 1MB, 2)) MB)" }
                    Write-Log "  Copied: $($_.Name) $sizeStr" "INFO"
                } catch {
                    $skippedCount++
                    Write-Log "  [WARN] Failed to copy $($_.Name): $_" "WARN"
                }
            }
            Write-Log "Extension copy complete: $copiedCount copied, $skippedCount skipped" "INFO"
        } else {
            Write-Log "[WARN] Source extensions directory not found: $sharedExtensionsDir" "WARN"
        }
    } catch {
        Write-Log "Failed to copy extensions: $_`n$($_.ScriptStackTrace)" "ERROR"
    }

    # Define $global:InstallersPath for use throughout the script
    $global:InstallersPath = "C:\ProgramData\WindowsAISandboxApps\Installers"
    $global:ExtensionsPath = "C:\ProgramData\WindowsAISandboxApps\Extensions"

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
        # Refresh the popup's counters file on every progress update so the
        # status window shows live "Installed: X / Failed: Y" as steps complete.
        try {
            if ($global:results -and $global:results.Count -gt 0) {
                Update-StatusCounters -Results $global:results
            }
        } catch {}
        # PRIMARY REFRESH PATH: directly push the latest values into the popup
        # form's controls. This bypasses the WinForms Timer entirely, which is
        # important because during long Start-Process -Wait calls the message
        # pump blocks and the Timer's Tick event won't fire reliably.
        try {
            if ($script:StatusUpdateFromProgress -and $script:StatusForm -and $script:StatusForm.Visible) {
                & $script:StatusUpdateFromProgress
            }
        } catch {}
        # Also pump the WinForms message loop so the form repaints and any
        # other pending messages (e.g. the OK button click handler) get
        # dispatched.
        try {
            [System.Windows.Forms.Application]::DoEvents()
        } catch {}
    }

    # Writes the live install counters (ok / failed / skipped) for the popup
    # window to read. The popup polls this file along with install-progress.json.
    function Update-StatusCounters {
        param(
            [hashtable]$Results
        )
        try {
            $okC = ($Results.Values | Where-Object { $_ -eq "OK" }).Count
            $failC = ($Results.Values | Where-Object { $_ -eq "ERROR" }).Count
            $warnC = ($Results.Values | Where-Object { $_ -eq "WARN" }).Count
            $skipC = ($Results.Values | Where-Object { $_ -eq "SKIP" }).Count
            # Tally non-SKIP successes including WARN as "installed" so the user
            # sees a friendly count; failures are ERRORs.
            $counters = @{
                ok       = $okC + $warnC
                failed   = $failC
                skipped  = $skipC
                total    = $Results.Count
            }
            $json = $counters | ConvertTo-Json -Compress
            $countersFile = "C:\ProgramData\WindowsAISandboxApps\Logs\status-counters.json"
            $null = New-Item -ItemType Directory -Path (Split-Path $countersFile) -Force -ErrorAction SilentlyContinue
            $json | Out-File -FilePath $countersFile -Encoding utf8 -Force -ErrorAction Stop
        } catch {
            Write-Log "Failed to update status-counters.json: $_" "WARN"
        }
    }
    
    Update-InstallProgress -StepIndex 0 -ActiveInstall "Initializing" -Status "Installing"
    # Initialize the counters file so the popup starts with zeros, not undefined values.
    $initialCounters = @{ ok = 0; failed = 0; skipped = 0; total = 0 }
    $initialCounters | ConvertTo-Json -Compress | Out-File -FilePath "C:\ProgramData\WindowsAISandboxApps\Logs\status-counters.json" -Encoding utf8 -Force -ErrorAction SilentlyContinue

    # NOW create and show the status window, after the initial progress JSON
    # has been written. The polling timer in the form will pick up the file
    # on its first tick and the bar will move from 0% upward as installs
    # progress.
    if (-not $NoStatusWindow) {
        New-StatusWindow
    }
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

# Helper: pump the WinForms message loop while waiting for a process to exit.
# Used by inline Start-Process -Wait calls that are outside Install-SilentProcess.
# Without this, the status window would freeze during a single long install.
function Wait-ProcessWithDoEvents {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$PollIntervalMs = 100
    )
    if (-not $Process) { return }
    # Track the JSON file's last-modified time so we only refresh the popup
    # when there's actually new data (avoids needless work every 100ms).
    $lastProgressMtime = $null
    $progressFileForWait = "C:\ProgramData\WindowsAISandboxApps\Logs\install-progress.json"
    while (-not $Process.HasExited) {
        try {
            [System.Windows.Forms.Application]::DoEvents()
            # If the progress JSON has been updated since the last refresh,
            # push the new values into the popup. This keeps the form
            # responsive during a single long Start-Process -Wait call
            # (e.g. ADK 5-minute download) where Update-InstallProgress
            # isn't being called.
            if (Test-Path $progressFileForWait) {
                $mtime = (Get-Item $progressFileForWait -ErrorAction SilentlyContinue).LastWriteTimeUtc.Ticks
                if ($mtime -ne $lastProgressMtime) {
                    $lastProgressMtime = $mtime
                    if ($script:StatusUpdateFromProgress -and $script:StatusForm -and $script:StatusForm.Visible) {
                        try { & $script:StatusUpdateFromProgress } catch {}
                    }
                }
            }
        } catch {}
        Start-Sleep -Milliseconds $PollIntervalMs
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
        $proc = Start-Process -FilePath $InstallerPath -ArgumentList $finalArgs -PassThru -NoNewWindow -ErrorAction Stop
        # Pump the WinForms message loop while the installer runs so the status
        # window can repaint, the opacity slider responds, and the polling
        # timer fires. This blocks until $proc.HasExited, so the install
        # still completes deterministically.
        while (-not $proc.HasExited) {
            try {
                [System.Windows.Forms.Application]::DoEvents()
            } catch {}
            Start-Sleep -Milliseconds 100
        }
        # Treat exit codes 0, 1641, 3010 as success.
        # 0    = success
        # 1641 = MSI: restart initiated (success, reboot in progress)
        # 3010 = MSI: restart required (success, reboot pending)
        # These are emitted by VS Community, PowerToys, ADK, SDK, etc. when /norestart is NOT honored.
        $exitCode = $proc.ExitCode
        if ($exitCode -eq 0 -or $exitCode -eq 1641 -or $exitCode -eq 3010) {
            if ($exitCode -eq 0) {
                Write-Log "[OK] $ToolName installed successfully." "INFO"
            } else {
                Write-Log "[OK] $ToolName installed successfully (exit $exitCode = reboot pending/required, treated as success in Windows Sandbox)." "INFO"
            }
            return "OK"
        } else {
            Write-Log "[WARN] $ToolName installer exited with code $exitCode" "WARN"
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
        $installer = "$global:InstallersPath\$($tools.nodejs.fileName)"
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
            $pythonInstaller = "$global:InstallersPath\$($tools.python.fileName)"
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
                    $proc = Start-Process -FilePath $pythonInstaller -ArgumentList $pyArgs -PassThru -NoNewWindow -ErrorAction Stop
                    Wait-ProcessWithDoEvents -Process $proc
                    # Refresh the process handle so ExitCode is reliable.
                    # PowerShell sometimes returns $null or empty for ExitCode
                    # if the process object is not refreshed after exit.
                    $proc.Refresh()
                    $realExitCode = $proc.ExitCode
                    $pythonExePath = "C:\Program Files\Python312\python.exe"
                    # Don't downgrade OK to WARN if the install actually
                    # succeeded (file is present). The installer sometimes
                    # returns empty/0 by reflection glitch but installs fine.
                    if ($realExitCode -eq 0 -or (Test-Path -LiteralPath $pythonExePath)) {
                        Write-Log "[OK] Python installed successfully (exit code: $realExitCode)." "INFO"
                        $results["python"] = "OK"
                    } else {
                        Write-Log "[WARN] Python installer exited with code '$realExitCode'. Check log: $pythonLog" "WARN"
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
        $installer = "$global:InstallersPath\$($tools.chrome.fileName)"
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
            $targetExtPath = Join-Path $global:ExtensionsPath "page-assist"
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
        $installer = "$global:InstallersPath\$($tools.brave.fileName)"
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
        $installer = "$global:InstallersPath\$($tools.notepadpp.fileName)"
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

# Order 7: Beyond Compare 5 (Portable Mode)
try {
    if ($tools.beyondcompare.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare 5 (Portable)" -Status "Installing"
        $installer = "$global:InstallersPath\$($tools.beyondcompare.fileName)"
        $portableDir = "C:\ProgramData\WindowsAISandboxApps\Installers\BeyondCompare"
        $shortcutPath = "$env:USERPROFILE\Desktop\Beyond Compare 5.lnk"

        if (Test-Path $installer) {
            Write-Log "Extracting Beyond Compare 5 in portable mode to $portableDir..." "INFO"
            try {
                if (-not (Test-Path $portableDir)) {
                    $null = New-Item -ItemType Directory -Path $portableDir -Force -ErrorAction SilentlyContinue
                }
                # /PORTABLE=1 + /DIR=<path> extracts to that path without registering
                $res = Install-SilentProcess -ToolId "beyondcompare" -ToolName "Beyond Compare 5 (Portable)" -InstallerPath $installer -SilentArgs $tools.beyondcompare.silentArgs
                $results["beyondcompare"] = $res
                try { [System.Windows.Forms.Application]::DoEvents() } catch {}

                # Find the main BCompare.exe (could be BCompare64.exe, BCompare.exe, etc.)
                $bcExe = $null
                foreach ($candidate in @("BCompare64.exe", "BCompare.exe", "BeyondCompare.exe")) {
                    $found = Get-ChildItem -Path $portableDir -Filter $candidate -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($found) { $bcExe = $found.FullName; break }
                }

                if ($bcExe) {
                    Write-Log "Found BC executable: $bcExe" "INFO"
                    # Create desktop shortcut
                    $wsh = New-Object -ComObject WScript.Shell
                    $shortcut = $wsh.CreateShortcut($shortcutPath)
                    $shortcut.TargetPath = $bcExe
                    $shortcut.WorkingDirectory = Split-Path $bcExe -Parent
                    $shortcut.IconLocation = "$bcExe,0"
                    $shortcut.Save()
                    Write-Log "[OK] Desktop shortcut created: $shortcutPath" "INFO"

                    # Add to user PATH so 'bcompare' is callable from any shell
                    $bcDir = Split-Path $bcExe -Parent
                    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
                    if ($currentPath -notlike "*$bcDir*") {
                        [System.Environment]::SetEnvironmentVariable("Path", "$currentPath;$bcDir", [System.EnvironmentVariableTarget]::User)
                        Write-Log "[OK] $bcDir added to user PATH." "INFO"
                    }

                    $verifyRes = Test-InstallationArtifacts -ToolId "beyondcompare" -ToolName "Beyond Compare 5 (Portable)" -ExpectedPaths @($bcExe)
                    if ($verifyRes -ne "OK") { $results["beyondcompare"] = $verifyRes }
                } else {
                    Write-Log "[WARN] BCompare.exe not found in $portableDir after extraction" "WARN"
                    if ($results["beyondcompare"] -eq "OK") { $results["beyondcompare"] = "WARN" }
                }
            } catch {
                Write-Log "[ERROR] Beyond Compare portable extraction failed: $_`n$($_.ScriptStackTrace)" "ERROR"
                $results["beyondcompare"] = "ERROR"
            }

            $status = if ($results["beyondcompare"] -eq "OK") { "Completed" } else { "Failed" }
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare 5 (Portable)" -Status $status
        } else {
            Write-Log "[WARN] Beyond Compare installer not found at $installer" "WARN"
            $results["beyondcompare"] = "ERROR"
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare 5 (Portable)" -Status "Failed"
        }
    } else {
        Write-Log "[SKIP] Beyond Compare 5 (Portable) (disabled by config)" "INFO"
        $results["beyondcompare"] = "SKIP"
    }
} catch {
    Write-Log "Beyond Compare block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["beyondcompare"] = "ERROR"
    if ($tools.beyondcompare.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare 5 (Portable)" -Status "Failed"
    }
}

# Order 8: Ollama
try {
    if ($tools.ollama.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Ollama" -Status "Installing"
        $installer = "$global:InstallersPath\$($tools.ollama.fileName)"
        
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

        # If WDAC still blocks, try alternatives in order:
        # 1) winget (handles retries, uses Microsoft's CDN)
        # 2) curl direct download from GitHub (extended timeout, larger min size, retry on size mismatch)
        if ($res -ne "OK") {
            Write-Log "Ollama installer may be blocked. Trying fallback methods..." "WARN"
            $ollamaCliUrl = "https://github.com/ollama/ollama/releases/latest/download/ollama-windows-amd64.zip"
            $ollamaZipDest = Join-Path $global:InstallersPath "ollama-windows-amd64.zip"
            $ollamaDir = Join-Path $env:LOCALAPPDATA "Programs\Ollama"

            # Method 1: winget (preferred if available)
            $wingetPath = Get-Command winget.exe -ErrorAction SilentlyContinue
            if ($wingetPath) {
                Write-Log "winget is available. Trying: winget install Ollama.Ollama --silent --accept-package-agreements --accept-source-agreements" "INFO"
                try {
                    $wgProc = Start-Process -FilePath $wingetPath.Path -ArgumentList "install", "Ollama.Ollama", "--silent", "--accept-package-agreements", "--accept-source-agreements" -PassThru -NoNewWindow -ErrorAction Stop
                    $wgExited = $wgProc.WaitForExit(600000)  # 10 min
                    if ($wgExited -and $wgProc.ExitCode -eq 0) {
                        Write-Log "[OK] Ollama installed via winget." "INFO"
                        $res = "OK"
                    } else {
                        Write-Log "winget install did not succeed (exit: $($wgProc.ExitCode)). Falling back to curl..." "WARN"
                    }
                } catch {
                    Write-Log "winget install failed: $_. Falling back to curl..." "WARN"
                }
            } else {
                Write-Log "winget not available in this sandbox VM. Falling back to direct curl download." "INFO"
            }

            # Method 2: curl direct download (with retry on size mismatch)
            if ($res -ne "OK") {
                $downloadAttempt = 0
                $maxDownloadAttempts = 2
                $minValidSize = 100MB  # Ollama zip is ~150-200MB; anything smaller is a partial download
                while ($downloadAttempt -lt $maxDownloadAttempts -and $res -ne "OK") {
                    $downloadAttempt++
                    try {
                        Write-Log "Downloading Ollama CLI from $ollamaCliUrl (attempt $downloadAttempt, up to 11 min)..." "INFO"
                        # -y 120 = curl's per-transfer speed-time limit (curl aborts if no progress for 120s)
                        # -Y 600 = curl's max time in seconds
                        $curlProc = Start-Process -FilePath "curl.exe" -ArgumentList "-L", "-o", "`"$ollamaZipDest`"", "`"$ollamaCliUrl`"", "--connect-timeout", "30", "-y", "120", "-Y", "600" -PassThru -NoNewWindow -ErrorAction Stop
                        $exited = $curlProc.WaitForExit(660000)  # 11 min overall
                        if (-not $exited) {
                            Write-Log "Curl did not finish within 11 min; killing process." "WARN"
                            try { Stop-Process -Id $curlProc.Id -Force -ErrorAction SilentlyContinue } catch {}
                        }
                        if (Test-Path $ollamaZipDest) {
                            $size = (Get-Item $ollamaZipDest).Length
                            if ($size -gt $minValidSize) {
                                # Zip contains ollama.exe; extract it
                                $extractDir = Join-Path $env:TEMP "ollama-extract"
                                $null = New-Item -ItemType Directory -Path $extractDir -Force -ErrorAction SilentlyContinue
                                try {
                                    Expand-Archive -Path $ollamaZipDest -DestinationPath $extractDir -Force -ErrorAction Stop
                                    $extractedExe = Join-Path $extractDir "ollama.exe"
                                    if (Test-Path $extractedExe) {
                                        $null = New-Item -ItemType Directory -Path $ollamaDir -Force -ErrorAction SilentlyContinue
                                        Copy-Item -Path $extractedExe -Destination (Join-Path $ollamaDir "ollama.exe") -Force -ErrorAction Stop
                                        $env:PATH = "$ollamaDir;$env:PATH"
                                        [Environment]::SetEnvironmentVariable("PATH", "$ollamaDir;$([Environment]::GetEnvironmentVariable('PATH', 'User'))", "User")
                                        Write-Log "[OK] Ollama CLI installed to $ollamaDir" "OK"
                                        $res = "OK"
                                    } else {
                                        Write-Log "Extracted zip does not contain ollama.exe" "ERROR"
                                    }
                                } catch {
                                    Write-Log "Failed to extract Ollama zip: $_" "ERROR"
                                }
                            } else {
                                Write-Log "Downloaded Ollama artifact is too small ($([math]::Round($size/1MB,1)) MB, minimum $minValidSize bytes); likely partial download. Will retry..." "WARN"
                                try { Remove-Item -Path $ollamaZipDest -Force -ErrorAction SilentlyContinue } catch {}
                            }
                        } else {
                            Write-Log "Ollama CLI download produced no file" "WARN"
                        }
                    } catch {
                        Write-Log "Failed to download Ollama CLI (attempt $downloadAttempt): $_" "WARN"
                    }
                }
                if ($res -ne "OK") {
                    Write-Log "[ERROR] All Ollama fallback methods failed. Ollama will be marked as failed." "ERROR"
                }
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
                    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
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
                        $proc = Start-Process -FilePath "ollama" -ArgumentList "pull gemma4" -PassThru -NoNewWindow -ErrorAction Stop
                        Wait-ProcessWithDoEvents -Process $proc
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
                        $proc = Start-Process -FilePath "ollama" -ArgumentList "pull nous-hermes2" -PassThru -NoNewWindow -ErrorAction Stop
                        Wait-ProcessWithDoEvents -Process $proc
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
        $installer = "$global:InstallersPath\$($tools.lmstudio.fileName)"
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
                $npmProc = Start-Process -FilePath "npm" -ArgumentList "i -g opencode-ai" -PassThru -NoNewWindow -ErrorAction Stop
                Wait-ProcessWithDoEvents -Process $npmProc
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
        $installer = "$global:InstallersPath\$($tools.'opencode-desktop'.fileName)"
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
            $proc = Start-Process -FilePath "pip" -ArgumentList "install", "crewai" -PassThru -NoNewWindow -ErrorAction Stop
            Wait-ProcessWithDoEvents -Process $proc
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
        $installer = "$global:InstallersPath\$($tools.vscode.fileName)"
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

# Order 13.5: Beyond Compare VSCode Extension (depends on VSCode and Beyond Compare)
try {
    if ($tools.'bcompare-vscode'.enabled) {
        # Skip if prerequisites are missing
        if ($results["vscode"] -ne "OK") {
            Write-Log "[SKIP] Beyond Compare VSCode Extension (VSCode not installed)" "WARN"
            $results["bcompare-vscode"] = "SKIP"
        } elseif ($results["beyondcompare"] -ne "OK") {
            Write-Log "[SKIP] Beyond Compare VSCode Extension (Beyond Compare not installed)" "WARN"
            $results["bcompare-vscode"] = "SKIP"
        } else {
            $global:currentStep++
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare VSCode Extension" -Status "Installing"
            $vsixPath = "$global:InstallersPath\$($tools.'bcompare-vscode'.fileName)"
            if (Test-Path $vsixPath) {
                try {
                    Refresh-Path
                    $codeCmd = Get-Command code -ErrorAction SilentlyContinue
                    if ($codeCmd) {
                        Write-Log "Installing Beyond Compare VSCode Extension via 'code --install-extension'..." "INFO"
                        $installProc = Start-Process -FilePath "code" -ArgumentList "--install-extension", $vsixPath, "--force" -PassThru -NoNewWindow -ErrorAction Stop
                        Wait-ProcessWithDoEvents -Process $installProc
                        if ($installProc.ExitCode -eq 0) {
                            Write-Log "[OK] Beyond Compare VSCode Extension installed successfully." "INFO"
                            $results["bcompare-vscode"] = "OK"
                        } else {
                            Write-Log "[WARN] Beyond Compare VSCode Extension install exited with code $($installProc.ExitCode)" "WARN"
                            $results["bcompare-vscode"] = "WARN"
                        }
                    } else {
                        Write-Log "[WARN] 'code' command not found in PATH. Cannot install extension." "WARN"
                        $results["bcompare-vscode"] = "WARN"
                    }
                } catch {
                    Write-Log "[ERROR] Failed to install Beyond Compare VSCode Extension: $_" "ERROR"
                    $results["bcompare-vscode"] = "ERROR"
                }
            } else {
                Write-Log "[WARN] Beyond Compare VSCode Extension .vsix not found at $vsixPath" "WARN"
                $results["bcompare-vscode"] = "WARN"
            }
            # Verify the extension is installed
            $extDir = Join-Path $env:USERPROFILE ".vscode\extensions"
            $bcompareExtFound = Get-ChildItem -Path $extDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "scootersoftware.bcompare-vscode*" }
            if ($bcompareExtFound) {
                Write-Log "[OK] Verified: Beyond Compare VSCode Extension is installed at $($bcompareExtFound.FullName)" "INFO"
            } else {
                Write-Log "[WARN] Beyond Compare VSCode Extension directory not found under $extDir" "WARN"
                if ($results["bcompare-vscode"] -eq "OK") { $results["bcompare-vscode"] = "WARN" }
            }
            $status = if ($results["bcompare-vscode"] -eq "OK") { "Completed" } else { "Failed" }
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare VSCode Extension" -Status $status
        }
    } else {
        Write-Log "[SKIP] Beyond Compare VSCode Extension (disabled by config)" "INFO"
        $results["bcompare-vscode"] = "SKIP"
    }
} catch {
    Write-Log "Beyond Compare VSCode Extension install block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["bcompare-vscode"] = "ERROR"
    if ($tools.'bcompare-vscode'.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Beyond Compare VSCode Extension" -Status "Failed"
    }
}

# Order 14: Visual Studio Community
try {
    if ($tools.vscommunity.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Visual Studio Community" -Status "Installing"
        $installer = "$global:InstallersPath\$($tools.vscommunity.fileName)"
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
        $installer = "$global:InstallersPath\$($tools.'7zip'.fileName)"
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

# Order 16: Sysinternals Suite (ZIP extraction to PATH) + Sysmon service install
try {
    if ($tools.sysinternals.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite + Sysmon" -Status "Installing"
        $zipFile = "$global:InstallersPath\$($tools.sysinternals.fileName)"
        $suitePath = "C:\Tools\Sysinternals"
        $sysmonConfigPath = Join-Path $suitePath "default-config.xml"
        
        if (-not (Test-Path $zipFile)) {
            Write-Log "[WARN] Sysinternals ZIP not found at $zipFile" "WARN"
            $results["sysinternals"] = "ERROR"
            Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite + Sysmon" -Status "Failed"
        } else {
            # Step A: Extract the full suite to C:\Tools\Sysinternals and add to Machine PATH
            try {
                if (-not (Test-Path $suitePath)) {
                    $null = New-Item -ItemType Directory -Path $suitePath -Force -ErrorAction Stop
                }
                Expand-Archive -Path $zipFile -DestinationPath $suitePath -Force -ErrorAction Stop
                Write-Log "[OK] Sysinternals Suite extracted to $suitePath (all 70+ tools)." "INFO"
                
                $currentPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
                if ($currentPath -notlike "*$suitePath*") {
                    [System.Environment]::SetEnvironmentVariable("Path", "$currentPath;$suitePath", [System.EnvironmentVariableTarget]::Machine)
                    Write-Log "[OK] $suitePath added to Machine PATH (visible to all users)." "INFO"
                }
            } catch {
                Write-Log "[ERROR] Failed to extract Sysinternals Suite: $_`n$($_.ScriptStackTrace)" "ERROR"
                $results["sysinternals"] = "ERROR"
                Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite + Sysmon" -Status "Failed"
            }
            
            # Step B: Write the conservative default Sysmon config XML
            if ($results["sysinternals"] -ne "ERROR") {
                $defaultSysmonConfig = @'
<Sysmon schemaversion="4.82">
  <HashAlgorithms>SHA256</HashAlgorithms>
  <EventFiltering>
    <ProcessCreate onmatch="include"/>
    <FileCreateTime onmatch="include"/>
    <NetworkConnect onmatch="exclude">
      <DestinationPort condition="is">53</DestinationPort>
    </NetworkConnect>
    <ProcessTerminate onmatch="exclude"/>
    <DriverLoad onmatch="exclude">
      <Signature condition="contains">microsoft</Signature>
      <Signature condition="contains">windows</Signature>
    </DriverLoad>
    <ImageLoad onmatch="exclude"/>
    <CreateRemoteThread onmatch="include"/>
    <RawAccessRead onmatch="include"/>
    <ProcessAccess onmatch="exclude"/>
    <FileCreate onmatch="include"/>
    <RegistryEvent onmatch="exclude"/>
    <FileCreateStreamHash onmatch="exclude"/>
    <PipeEvent onmatch="include"/>
    <WmiEvent onmatch="include"/>
    <DnsQuery onmatch="exclude"/>
    <FileDelete onmatch="exclude"/>
    <ClipboardChange onmatch="exclude"/>
    <ProcessTampering onmatch="include"/>
    <FileDeleteDetected onmatch="exclude"/>
    <FileBlockExecutable onmatch="include"/>
    <FileBlockShredding onmatch="include"/>
    <FileExecutableDetected onmatch="include"/>
  </EventFiltering>
</Sysmon>
'@
                try {
                    Set-Content -Path $sysmonConfigPath -Value $defaultSysmonConfig -Encoding utf8 -ErrorAction Stop
                    Write-Log "[OK] Wrote default Sysmon config to $sysmonConfigPath" "INFO"
                } catch {
                    Write-Log "[WARN] Failed to write default config XML: $_" "WARN"
                }
                
                # Step C: Install the Sysmon driver + service (machine-wide)
                # -accepteula is MANDATORY for unattended installs (otherwise EULA prompt hangs).
                $sysmonExe = $null
                $sysmon64Path = Join-Path $suitePath "Sysmon64.exe"
                $sysmon32Path = Join-Path $suitePath "Sysmon.exe"
                if (Test-Path $sysmon64Path) { $sysmonExe = $sysmon64Path }
                elseif (Test-Path $sysmon32Path) { $sysmonExe = $sysmon32Path }
                
                if ($sysmonExe) {
                    Write-Log "Installing Sysmon service via '$sysmonExe -accepteula -i <config>'..." "INFO"
                    try {
                        $configArg = if (Test-Path $sysmonConfigPath) { "`"$sysmonConfigPath`"" } else { "" }
                        $proc = Start-Process -FilePath $sysmonExe -ArgumentList "-accepteula", "-i", $configArg -PassThru -NoNewWindow -ErrorAction Stop
                        Wait-ProcessWithDoEvents -Process $proc
                        if ($proc.ExitCode -eq 0) {
                            Write-Log "[OK] Sysmon installed (driver + service)." "INFO"
                        } else {
                            Write-Log "[WARN] sysmon install exited with code $($proc.ExitCode)" "WARN"
                        }
                    } catch {
                        Write-Log "[ERROR] Sysmon install failed: $_`n$($_.ScriptStackTrace)" "ERROR"
                    }
                } else {
                    Write-Log "[WARN] Sysmon executable not found in $suitePath" "WARN"
                }
                
                # Step D: Verify Sysmon service status (don't fail the whole step if just the service check trips)
                try {
                    Start-Sleep -Seconds 2
                    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
                    $svc = Get-Service -Name "Sysmon" -ErrorAction SilentlyContinue
                    if ($svc -and $svc.Status -eq "Running") {
                        Write-Log "[VERIFY] [OK] Sysmon service is Running." "OK"
                        $results["sysinternals"] = "OK"
                        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite + Sysmon" -Status "Completed"
                    } elseif ($svc) {
                        Write-Log "[VERIFY] [WARN] Sysmon service found but not Running (status: $($svc.Status))." "WARN"
                        $results["sysinternals"] = "WARN"
                        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite + Sysmon" -Status "Failed"
                    } else {
                        Write-Log "[VERIFY] [WARN] Sysmon service not found. Suite extracted but service install may have failed." "WARN"
                        $results["sysinternals"] = "WARN"
                        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite + Sysmon" -Status "Failed"
                    }
                } catch {
                    Write-Log "[VERIFY] [ERROR] Could not query Sysmon service: $_" "ERROR"
                    $results["sysinternals"] = "ERROR"
                    Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite + Sysmon" -Status "Failed"
                }
            }
        }
    } else {
        Write-Log "[SKIP] Sysinternals Suite + Sysmon (disabled by config)" "INFO"
        $results["sysinternals"] = "SKIP"
    }
} catch {
    Write-Log "Sysinternals installation block failed: $_`n$($_.ScriptStackTrace)" "ERROR"
    $results["sysinternals"] = "ERROR"
    if ($tools.sysinternals.enabled) {
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Sysinternals Suite + Sysmon" -Status "Failed"
    }
}

# Order 17: Windows PowerToys
try {
    if ($tools.powertoys.enabled) {
        $global:currentStep++
        Update-InstallProgress -StepIndex $global:currentStep -ActiveInstall "Windows PowerToys" -Status "Installing"
        $installer = "$global:InstallersPath\$($tools.powertoys.fileName)"
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
        $installer = "$global:InstallersPath\$($tools.windowssdk.fileName)"
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
        $installer = "$global:InstallersPath\$($tools.adk.fileName)"
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
    "Beyond Compare 5" = @(
        "C:\ProgramData\WindowsAISandboxApps\Installers\BeyondCompare\BCompare.exe",
        "C:\ProgramData\WindowsAISandboxApps\Installers\BeyondCompare\BCompare64.exe",
        "C:\Program Files\Beyond Compare 5\BCompare.exe",
        "C:\Program Files (x86)\Beyond Compare 5\BCompare.exe"
    )
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
$criticalCommands = @("ollama", "node", "npm", "python", "pip", "code", "git", "bcompare")
foreach ($cmd in $criticalCommands) {
    $cmdPath = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($cmdPath) {
        Write-Log "  [OK] Command '$cmd' available at: $($cmdPath.Source)" "INFO"
    } else {
        Write-Log "  [WARN] Command '$cmd' NOT in PATH" "WARN"
    }
}

# Check for Beyond Compare VSCode Extension
$extDir = Join-Path $env:USERPROFILE ".vscode\extensions"
if (Test-Path $extDir) {
    $bcompareExt = Get-ChildItem -Path $extDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "scootersoftware.bcompare-vscode*" } | Select-Object -First 1
    if ($bcompareExt) {
        Write-Log "  [OK] Beyond Compare VSCode Extension installed: $($bcompareExt.Name)" "INFO"
    } else {
        Write-Log "  [WARN] Beyond Compare VSCode Extension NOT installed in $extDir" "WARN"
    }
} else {
    Write-Log "  [WARN] VSCode extensions directory not found at $extDir" "WARN"
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
    $okCount = ($results.Values | Where-Object { $_ -eq "OK" }).Count
    $warnCount = ($results.Values | Where-Object { $_ -eq "WARN" }).Count
    $errorCount = ($results.Values | Where-Object { $_ -eq "ERROR" }).Count
    $skipCount = ($results.Values | Where-Object { $_ -eq "SKIP" }).Count
    # Count "Installed" as OK + WARN (both indicate the tool is on the box;
    # WARN just means an exit code was non-zero but no outright failure).
    $installedCount = $okCount + $warnCount
    $total = $results.Count
    Write-Log "AI Sandbox setup complete. Installed: $installedCount / $total (Failed: $errorCount, Skipped: $skipCount)" "INFO"

    # Show the summary in the status window and wait for the user to click OK.
    if (-not $NoStatusWindow -and $script:StatusForm) {
        Show-StatusSummary -InstalledCount $installedCount -FailedCount $errorCount -SkippedCount $skipCount
        # Block here, pumping the form's message loop, until OK is clicked.
        # The OK button's click handler sets $script:StatusSummaryDone and
        # calls $form.Close(), which exits the Application.Run loop below.
        try {
            [System.Windows.Forms.Application]::Run($script:StatusForm)
        } catch {
            Write-Log "Status window Application.Run ended: $_" "WARN"
        }
    } else {
        # Fallback: plain text MessageBox (same as before)
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show("AI Sandbox setup complete!`n`nInstalled: $installedCount / $total tools`n`nCheck C:\ProgramData\WindowsAISandboxApps\Logs\sandbox-bootstrap.log for details.`nFinal verification report: $verifyReportPath", "AI Sandbox Generator", 0, 64) | Out-Null
    }
} catch {
    Write-Log "Completion dialog failed: $_" "WARN"
    Write-Log "Sandbox ready." "INFO"
} finally {
    Close-StatusWindow
}

Exit-Script 0


