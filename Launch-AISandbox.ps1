# Launch-AISandbox.ps1 - Windows AI Sandbox Launcher
# Requires Administrator privileges

[CmdletBinding()]
param(
    [switch]$GUI,
    [switch]$SkipOllama,
    [switch]$SkipLMStudio,
    [switch]$SkipOpenCodeTerminal,
    [switch]$SkipOpenCodeDesktop,
    [switch]$SkipChrome,
    [switch]$SkipBrave,
    [switch]$SkipNotepadPP,
    [switch]$SkipBeyondCompare,
    [switch]$SkipNpm,
    [switch]$SkipPython,
    [switch]$SkipCrewAI,
    [switch]$SkipCopilot,
    [switch]$SkipPageAssist,
    [switch]$SkipVSCode,
    [switch]$SkipVSCommunity,
    [switch]$Skip7Zip,
    [switch]$SkipSysinternals,
    [switch]$SkipPowerToys,
    [switch]$SkipWindowsSDK,
    [switch]$SkipADK,
    [switch]$SkipADKWinPE,
    [switch]$SkipAntigravity,
    [switch]$SkipBCompareVSCode,
    [int]$SandboxMemoryMB = 16384,
    [switch]$PreCacheOnly,
    [switch]$CleanCache,
    [switch]$SimulateMockThreat
)

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

$LogPath = Join-Path $LogsDir "Launch-AISandbox.log"

# Function to write log with timestamp and level
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logLine = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARN" { Write-Host $Message -ForegroundColor Yellow }
        default { Write-Host $Message -ForegroundColor Cyan }
    }
    
    try {
        $logLine | Out-File -FilePath $LogPath -Append -Encoding utf8 -ErrorAction SilentlyContinue
    } catch {}

    if ($Global:GuiLogTextBox -and $Global:GuiLogTextBox.IsHandleCreated) {
        try {
            $Global:GuiLogTextBox.Invoke([Action[string]]{
                param($text)
                $Global:GuiLogTextBox.AppendText($text + "`r`n")
            }, $logLine)
        } catch {
            try {
                $Global:GuiLogTextBox.AppendText($logLine + "`r`n")
            } catch {}
        }
    }
}

function Exit-Script {
    param([int]$code = 0)
    try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}
    if ($GUI) {
        throw "Script exited with code $code"
    } else {
        exit $code
    }
}

# Helper: Get host OS information
function Get-HostOSInfo {
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $arch = (Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue).Architecture
        # Architecture: 0=x86, 9=x64, 12=ARM64
        $archName = switch ($arch) {
            9 { "x64" }
            12 { "ARM64" }
            0 { "x86" }
            default { "Unknown" }
        }
        return [PSCustomObject]@{
            Caption       = $osInfo.Caption
            Version       = $osInfo.Version
            BuildNumber   = [int]$osInfo.BuildNumber
            OSArchitecture = $osInfo.OSArchitecture
            ProcessorArch = $archName
            ProductType   = $osInfo.ProductType  # 1=Workstation, 2=DC, 3=Server
        }
    } catch {
        Write-Log "Failed to detect host OS: $_" "WARN"
        return $null
    }
}

# Helper: Check if host meets Windows 11 24H2/25H2 x64 requirements
function Test-HostOSRequirements {
    $osInfo = Get-HostOSInfo
    if ($null -eq $osInfo) {
        Write-Log "Cannot determine host OS. Proceeding at your own risk." "WARN"
        return $true
    }

    Write-Log "Host OS detected: $($osInfo.Caption) (Build $($osInfo.BuildNumber), $($osInfo.OSArchitecture))" "INFO"

    # Check architecture - must be x64
    if ($osInfo.ProcessorArch -ne "x64") {
        Write-Log "Unsupported architecture: $($osInfo.ProcessorArch). Only x64 (64-bit) is supported." "ERROR"
        return $false
    }

    # Check Windows version - must be 24H2 (Build 26100) or 25H2 (Build 26200)
    $minBuild = 26100  # Windows 11 24H2
    if ($osInfo.BuildNumber -lt $minBuild) {
        $verName = switch ($osInfo.BuildNumber) {
            22000 { "Windows 11 21H2" }
            22621 { "Windows 11 22H2" }
            22631 { "Windows 11 23H2" }
            default { "Windows (Build $($osInfo.BuildNumber))" }
        }
        Write-Log "Host OS is $verName. Minimum required: Windows 11 24H2 (Build 26100) or later." "ERROR"
        Write-Log "Please update Windows to version 24H2 or 25H2 via Settings > Windows Update." "ERROR"
        return $false
    }

    # Check Windows edition - Home is not supported for Windows Sandbox
    $edition = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name EditionID -ErrorAction SilentlyContinue).EditionID
    if ($edition -match "Home") {
        Write-Log "Windows 11 Home edition detected. Windows Sandbox is NOT supported on Home edition." "ERROR"
        Write-Log "Required: Windows 11 Pro, Enterprise, or Education." "ERROR"
        return $false
    }

    # All checks passed
    $verName = switch ($osInfo.BuildNumber) {
        26100 { "Windows 11 24H2" }
        26200 { "Windows 11 25H2" }
        default { "Windows (Build $($osInfo.BuildNumber))" }
    }
    Write-Log "[OK] Host meets requirements: $verName x64 ($edition)" "INFO"
    return $true
}

if ($FallbackUsed) {
    Write-Log "Failed to create log directory at C:\ProgramData\AIWindowsSandbox\Logs. Falling back to $LogsDir." "WARN"
}

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

# 2.5 Check Host OS Requirements (Windows 11 24H2/25H2 x64)
if (-not (Test-HostOSRequirements)) {
    Exit-Script 1
}

# 3. Setup Temp Shared Folder and Download Staging
try {
    $sharePath = Join-Path $env:TEMP "AISandboxShare"
    $installerPath = Join-Path $sharePath "Installers"
    $extensionPath = Join-Path $sharePath "Extensions"
    $configPath = Join-Path $sharePath "config"
    $stagingPath = Join-Path $env:TEMP "AISandboxStaging"

    $null = New-Item -ItemType Directory -Path $installerPath -Force -ErrorAction Stop
    $null = New-Item -ItemType Directory -Path $extensionPath -Force -ErrorAction Stop
    $null = New-Item -ItemType Directory -Path $configPath -Force -ErrorAction Stop
    $null = New-Item -ItemType Directory -Path $stagingPath -Force -ErrorAction Stop
} catch {
    Write-Log "Error setting up temp shared folders or staging directory: $_`n$($_.ScriptStackTrace)" "ERROR"
    Exit-Script 1
}

# 4. Load Central Tool Registry
try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $toolsJsonFile = Join-Path $scriptDir "config\tools.json"
    if (-not (Test-Path $toolsJsonFile)) {
        Write-Log "Could not find tools.json at $toolsJsonFile" "ERROR"
        Exit-Script 1
    }
    $toolsJson = Get-Content -Raw -Path $toolsJsonFile -ErrorAction Stop | ConvertFrom-Json
} catch {
    Write-Log "Error loading tools.json: $_`n$($_.ScriptStackTrace)" "ERROR"
    Exit-Script 1
}

# Helper: Download file with Progress
function Download-FileWithProgress {
    param(
        [string]$Uri,
        [string]$OutFile
    )
    Write-Log "Downloading $Uri -> $OutFile" "INFO"
    $response = $null
    $responseStream = $null
    $fileStream = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $request = [System.Net.HttpWebRequest]::Create($Uri)
        $request.Method = "GET"
        $request.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
        $request.Timeout = 1200000 # 20 minutes (large files)
        
        $response = $request.GetResponse()
        $contentLength = $response.ContentLength
        $responseStream = $response.GetResponseStream()
        
        $buffer = New-Object byte[] 65536
        $fileStream = [System.IO.File]::Create($OutFile)
        
        $totalBytesRead = 0
        $bytesRead = 0
        $lastReport = [DateTime]::MinValue
        $fileName = Split-Path $OutFile -Leaf
        
        do {
            $bytesRead = $responseStream.Read($buffer, 0, $buffer.Length)
            if ($bytesRead -gt 0) {
                $fileStream.Write($buffer, 0, $bytesRead)
                $totalBytesRead += $bytesRead
                
                $now = [DateTime]::UtcNow
                if (($now - $lastReport).TotalMilliseconds -gt 200 -or $totalBytesRead -eq $contentLength) {
                    $lastReport = $now
                    if ($contentLength -gt 0) {
                        $percent = [Math]::Round(($totalBytesRead / $contentLength) * 100)
                        $status = "$($percent)% complete ($([Math]::Round($totalBytesRead / 1MB, 2)) MB / $([Math]::Round($contentLength / 1MB, 2)) MB)"
                        Write-Progress -Activity "Downloading $fileName" -Status $status -PercentComplete $percent
                        if ($GUI -and $Global:GuiProgressBar -and $Global:GuiStatusLabel) {
                            $Global:GuiProgressBar.Value = $percent
                            $Global:GuiStatusLabel.Text = "Downloading ${fileName}: $status"
                            [System.Windows.Forms.Application]::DoEvents()
                        }
                    } else {
                        $status = "$([Math]::Round($totalBytesRead / 1MB, 2)) MB downloaded"
                        Write-Progress -Activity "Downloading $fileName" -Status $status
                        if ($GUI -and $Global:GuiStatusLabel) {
                            $Global:GuiStatusLabel.Text = "Downloading ${fileName}: $status"
                            [System.Windows.Forms.Application]::DoEvents()
                        }
                    }
                }
            }
        } while ($bytesRead -gt 0)
        
        $fileStream.Close()
        $responseStream.Close()
        $response.Close()
        
        Write-Progress -Activity "Downloading $fileName" -Completed
        if ($GUI -and $Global:GuiProgressBar) {
            $Global:GuiProgressBar.Value = 100
        }
        Write-Log "Download complete: $fileName" "INFO"
    } catch {
        if ($fileStream) { try { $fileStream.Close() } catch {} }
        if ($responseStream) { try { $responseStream.Close() } catch {} }
        if ($response) { try { $response.Close() } catch {} }
        Write-Log "Failed to download $($Uri): $_`n$($_.ScriptStackTrace)" "ERROR"
        throw $_
    }
}

# Helper: Resolve latest GitHub release asset
function Get-GitHubReleaseAssetUrl {
    param(
        [string]$ApiUrl,
        [string]$RegexPattern
    )
    Write-Log "Resolving latest GitHub release asset from $ApiUrl..." "INFO"
    try {
        $response = Invoke-WebRequest -Uri $ApiUrl -UseBasicParsing -ErrorAction Stop
        $release = $response.Content | ConvertFrom-Json
        $asset = $release.assets | Where-Object { $_.name -match $RegexPattern } | Select-Object -First 1
        if ($asset) {
            return $asset.browser_download_url
        } else {
            Write-Log "Could not find asset matching regex '$RegexPattern' in GitHub release." "WARN"
        }
    } catch {
        Write-Log "Failed to query GitHub API: $_`n$($_.ScriptStackTrace)" "WARN"
    }
    return $null
}

# Helper: Resolve Node.js LTS msi
function Get-NodeLtsUrl {
    param(
        [string]$BaseUrl
    )
    Write-Log "Resolving latest Node.js LTS from $BaseUrl..." "INFO"
    try {
        $response = Invoke-WebRequest -Uri $BaseUrl -UseBasicParsing -ErrorAction Stop
        $match = [regex]::Match($response.Content, 'href="(node-v20\.[0-9]+\.[0-9]+-x64\.msi)"')
        if ($match.Success) {
            return "${BaseUrl}$($match.Groups[1].Value)"
        }
    } catch {
        Write-Log "Failed to query Node.js downloads page: $_`n$($_.ScriptStackTrace)" "WARN"
    }
    return "https://nodejs.org/dist/v20.18.0/node-v20.18.0-x64.msi" # fallback
}

# Helper: Resolve Scooter Software Beyond Compare
function Get-BeyondCompareUrl {
    param(
        [string]$Url
    )
    Write-Log "Resolving Beyond Compare latest installer..." "INFO"
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
        $match = [regex]::Match($response.Content, 'href="([^"]+BCompare-4\.[0-9]+\.[0-9]+\.[0-9]+\.exe)"')
        if ($match.Success) {
            $matchedUrl = $match.Groups[1].Value
            if ($matchedUrl.StartsWith("http")) {
                return $matchedUrl
            } else {
                return "https://www.scootersoftware.com/$($matchedUrl.TrimStart('/'))"
            }
        }
    } catch {
        Write-Log "Failed to query Beyond Compare download page: $_`n$($_.ScriptStackTrace)" "WARN"
    }
    return "https://www.scootersoftware.com/files/BCompare-4.4.8.29710.exe" # fallback
}

# Helper: Verify file checksum hash
function Verify-FileHash {
    param(
        [string]$FilePath,
        [string]$ExpectedHash
    )
    if ([string]::IsNullOrEmpty($ExpectedHash)) {
        Write-Log "No expected hash defined for $(Split-Path $FilePath -Leaf). Skipping checksum verification." "WARN"
        return $true
    }
    if (-not (Test-Path $FilePath)) {
        Write-Log "File not found for hash verification: $FilePath" "ERROR"
        return $false
    }
    try {
        Write-Log "Verifying hash for $(Split-Path $FilePath -Leaf)..." "INFO"
        $fileHashInfo = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop
        $computedHash = $fileHashInfo.Hash
        if ($computedHash.Equals($ExpectedHash, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Log "Hash verification passed for $(Split-Path $FilePath -Leaf)." "INFO"
            return $true
        } else {
            Write-Log "Hash verification FAILED for $(Split-Path $FilePath -Leaf). Expected: $ExpectedHash, Got: $computedHash" "ERROR"
            return $false
        }
    } catch {
        Write-Log "Error computing hash for $(Split-Path $FilePath -Leaf): $_" "ERROR"
        return $false
    }
}

# Helper: Verify downloaded binary content (not HTML, size > 100KB, starts with MZ if EXE)
function Verify-DownloadedBinaryContent {
    param(
        [string]$FilePath
    )
    if (-not (Test-Path $FilePath)) { return $false }
    try {
        $size = (Get-Item $FilePath).Length
        if ($size -lt 100KB) {
            Write-Log "Binary verification failed: File size ($size bytes) is less than 100KB. It might be a redirection page or failed download." "ERROR"
            return $false
        }
        
        $firstBytes = [System.IO.File]::ReadAllBytes($FilePath)
        if ($firstBytes.Length -gt 100) {
            $utf8String = [System.Text.Encoding]::UTF8.GetString($firstBytes, 0, [Math]::Min(500, $firstBytes.Length))
            if ($utf8String -match "<!DOCTYPE html" -or $utf8String -match "<html" -or $utf8String -match "<head") {
                Write-Log "Binary verification failed: File starts with HTML tags. It is likely an HTML page rather than a binary executable." "ERROR"
                return $false
            }
        }
        
        if ($FilePath.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($firstBytes.Length -ge 2 -and ($firstBytes[0] -ne 0x4D -or $firstBytes[1] -ne 0x5A)) { # 0x4D 0x5A is 'MZ'
                Write-Log "Binary verification failed: EXE file does not start with MZ header." "ERROR"
                return $false
            }
        }
        
        if ($FilePath.EndsWith(".msi", [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($firstBytes.Length -ge 4 -and 
                ($firstBytes[0] -ne 0xD0 -or $firstBytes[1] -ne 0xCF -or 
                 $firstBytes[2] -ne 0x11 -or $firstBytes[3] -ne 0xE0)) {
                Write-Log "Binary verification failed: MSI file does not start with OLE header (D0 CF 11 E0)." "ERROR"
                return $false
            }
        }
        
        return $true
    } catch {
        Write-Log "Error verifying downloaded binary content: $_" "ERROR"
        return $false
    }
}

# Helper: Test if installer is already cached and valid
function Test-InstallerAlreadyCached {
    param(
        [string]$FilePath,
        [string]$ExpectedHash
    )
    if (-not (Test-Path $FilePath)) { return $false }
    $size = (Get-Item $FilePath).Length
    if ($size -lt 100KB) { return $false }
    if (-not (Verify-DownloadedBinaryContent -FilePath $FilePath)) { return $false }
    if ($ExpectedHash) {
        if (-not (Verify-FileHash -FilePath $FilePath -ExpectedHash $ExpectedHash)) { return $false }
    }
    return $true
}

# Helper: Verify Windows Sandbox is not already running
function Test-SandboxNotRunning {
    $sandbox = Get-Process -Name "WindowsSandbox" -ErrorAction SilentlyContinue
    $client = Get-Process -Name "WindowsSandboxClient" -ErrorAction SilentlyContinue
    if ($sandbox -or $client) { return $false }
    return $true
}

# Helper: Invoke Windows Defender Threat Scanning
function Invoke-DefenderScan {
    param(
        [string]$FilePath,
        [switch]$SimulateMockThreat
    )
    $fileName = Split-Path $FilePath -Leaf
    Write-Log "Scanning $fileName with Windows Defender..." "INFO"

    # Mock Malware Test Mechanism
    if ($fileName -like "*mock-infected*" -or $SimulateMockThreat) {
        Write-Log "MOCK MALWARE TEST: Threat detected in $fileName!" "ERROR"
        return $false
    }

    # Locate MpCmdRun.exe
    $defenderPath = $null
    if (Test-Path "C:\ProgramData\Microsoft\Windows Defender\Platform") {
        try {
            $subfolders = Get-ChildItem -Path "C:\ProgramData\Microsoft\Windows Defender\Platform" -Directory | Sort-Object Name -Descending
            foreach ($folder in $subfolders) {
                $exe = Join-Path $folder.FullName "MpCmdRun.exe"
                if (Test-Path $exe) {
                    $defenderPath = $exe
                    break
                }
            }
        } catch {
            Write-Log "Error searching Defender Platform folder: $_" "WARN"
        }
    }
    if (-not $defenderPath) {
        $fallbackExes = @(
            Join-Path $env:ProgramFiles "Windows Defender\MpCmdRun.exe",
            Join-Path ${env:ProgramFiles(x86)} "Windows Defender\MpCmdRun.exe"
        )
        foreach ($exe in $fallbackExes) {
            if (Test-Path $exe) {
                $defenderPath = $exe
                break
            }
        }
    }

    if ($defenderPath) {
        Write-Log "Using Defender CLI: $defenderPath" "INFO"
        try {
            # Run MpCmdRun.exe
            # -Scan -ScanType 3 -File <path> -DisableRemediation
            # Exit codes: 0 = clean, 2 = threat detected, other = failed/threat
            $proc = Start-Process -FilePath $defenderPath -ArgumentList "-Scan -ScanType 3 -File `"$FilePath`" -DisableRemediation" -Wait -PassThru -NoNewWindow
            Write-Log "Defender scan exited with code: $($proc.ExitCode)" "INFO"
            if ($proc.ExitCode -eq 0) {
                Write-Log "Defender scan clean: $fileName." "INFO"
                return $true
            } else {
                Write-Log "Defender scan failed or threat detected for $fileName. Exit code: $($proc.ExitCode)" "ERROR"
                return $false
            }
        } catch {
            Write-Log "Error executing Defender CLI scan: $_" "ERROR"
            return $false
        }
    } else {
        # Fallback to Start-MpScan
        Write-Log "MpCmdRun.exe not found. Falling back to Start-MpScan..." "WARN"
        try {
            Start-MpScan -ScanType CustomScan -ScanPath $FilePath -ErrorAction Stop
            
            # Since Start-MpScan doesn't return exit codes, let's verify if the file still exists and hasn't been quarantined/deleted.
            if (-not (Test-Path $FilePath)) {
                Write-Log "File $fileName was quarantined or removed by Start-MpScan!" "ERROR"
                return $false
            }
            Write-Log "Start-MpScan completed for $fileName." "INFO"
            return $true
        } catch {
            Write-Log "Start-MpScan reported an error or threat detected: $_" "ERROR"
            return $false
        }
    }
}

function Invoke-SandboxLaunch {
    # 5. Process Tools
    $Script:installConfig = @{ tools = @{} }

    foreach ($toolName in $toolsJson.tools.psobject.properties.name) {
        try {
            $tool = $toolsJson.tools.$toolName
            $skipVarName = $null
            if ($tool.skipFlag) {
                $skipVarName = $tool.skipFlag
            } else {
                $skipVarName = "Skip$($toolName)"
                if ($toolName -eq "beyondcompare") { $skipVarName = "SkipBeyondCompare" }
                elseif ($toolName -eq "notepadpp") { $skipVarName = "SkipNotepadPP" }
                elseif ($toolName -eq "nodejs") { $skipVarName = "SkipNpm" }
                elseif ($toolName -eq "pageassist") { $skipVarName = "SkipPageAssist" }
            }

            $isSkipped = Get-Variable -Name $skipVarName -ValueOnly -ErrorAction SilentlyContinue

            # Determine if enabled
            $enabled = $tool.enabled
            if ($isSkipped) {
                $enabled = $false
            }

            # Populate tool configuration for bootstrap
            $Script:installConfig.tools[$toolName] = @{
                name = $tool.name
                enabled = $enabled
                fileName = $tool.fileName
                silentArgs = $tool.silentArgs
                order = $tool.order
            }

            if (-not $enabled) {
                Write-Log "Skipping tool: $($tool.name)" "INFO"
                continue
            }

            # Execute Download / Pre-Caching
            Write-Log "Processing tool: $($tool.name)" "INFO"
            
            $destFile = $null
            $stagingFile = $null
            if ($tool.fileName -and $tool.downloadType -ne "git" -and $tool.downloadType -ne "pip" -and $tool.downloadType -ne "pwa" -and $tool.downloadType -ne "npm") {
                $destFile = Join-Path $installerPath $tool.fileName
                $stagingFile = Join-Path $stagingPath $tool.fileName
            }

            if ($tool.downloadType -eq "npm") {
                Write-Log "Tool $($tool.name) will be installed via npm inside the sandbox." "INFO"
                continue
            }

            if ($tool.downloadType -eq "direct") {
                if (-not (Test-InstallerAlreadyCached -FilePath $stagingFile -ExpectedHash $tool.hash)) {
                    if (Test-Path $stagingFile) {
                        Write-Log "Cached file is invalid or corrupted. Re-downloading: $($tool.name)" "WARN"
                        Remove-Item -Path $stagingFile -Force -ErrorAction SilentlyContinue
                    }
                    try {
                        Download-FileWithProgress -Uri $tool.url -OutFile $stagingFile
                        if (-not (Verify-DownloadedBinaryContent -FilePath $stagingFile)) {
                            throw "Downloaded file $stagingFile did not pass binary verification check."
                        }
                    } catch {
                        if ($tool.fallbackUrl) {
                            Write-Log "Direct download failed for $($tool.name). Falling back to URL: $($tool.fallbackUrl)" "WARN"
                            if (Test-Path $stagingFile) { Remove-Item -Path $stagingFile -Force -ErrorAction SilentlyContinue }
                            Download-FileWithProgress -Uri $tool.fallbackUrl -OutFile $stagingFile
                            if (-not (Verify-DownloadedBinaryContent -FilePath $stagingFile)) {
                                throw "Fallback downloaded file $stagingFile did not pass binary verification check."
                            }
                        } else {
                            throw $_
                        }
                    }
                } else {
                    Write-Log "Using cached installer in staging for $($tool.name)" "INFO"
                }
            }
            elseif ($tool.downloadType -eq "nodejs") {
                if (-not (Test-Path $stagingFile)) {
                    $resolvedUrl = Get-NodeLtsUrl -BaseUrl $tool.url
                    Download-FileWithProgress -Uri $resolvedUrl -OutFile $stagingFile
                    if (-not (Verify-DownloadedBinaryContent -FilePath $stagingFile)) {
                        throw "Downloaded Node.js file $stagingFile did not pass binary verification check."
                    }
                } else {
                    Write-Log "Using cached installer in staging for $($tool.name)" "INFO"
                }
            }
            elseif ($tool.downloadType -eq "github") {
                if (-not (Test-InstallerAlreadyCached -FilePath $stagingFile -ExpectedHash $tool.hash)) {
                    if (Test-Path $stagingFile) {
                        Write-Log "Cached file is invalid or corrupted. Re-downloading: $($tool.name)" "WARN"
                        Remove-Item -Path $stagingFile -Force -ErrorAction SilentlyContinue
                    }
                    $resolvedUrl = $null
                    try {
                        $resolvedUrl = Get-GitHubReleaseAssetUrl -ApiUrl $tool.url -RegexPattern $tool.assetRegex
                    } catch {}
                    if ([string]::IsNullOrWhiteSpace($resolvedUrl)) {
                        if ($tool.fallbackUrl) {
                            Write-Log "GitHub API resolution failed for $($tool.name). Falling back to direct URL: $($tool.fallbackUrl)" "WARN"
                            $resolvedUrl = $tool.fallbackUrl
                        } else {
                            Write-Log "GitHub API resolution failed for $($tool.name) and no fallback URL is available." "ERROR"
                        }
                    }
                    if ($resolvedUrl) {
                        Download-FileWithProgress -Uri $resolvedUrl -OutFile $stagingFile
                        if (-not (Verify-DownloadedBinaryContent -FilePath $stagingFile)) {
                            throw "Downloaded release asset $stagingFile did not pass binary verification check."
                        }
                    } else {
                        Write-Log "Failed to resolve GitHub asset for $($tool.name) and no fallback URL is available." "ERROR"
                    }
                } else {
                    Write-Log "Using cached installer in staging for $($tool.name)" "INFO"
                }
            }
            elseif ($tool.downloadType -eq "scootersoftware") {
                if (-not (Test-Path $stagingFile)) {
                    $resolvedUrl = Get-BeyondCompareUrl -Url $tool.url
                    Download-FileWithProgress -Uri $resolvedUrl -OutFile $stagingFile
                    if (-not (Verify-DownloadedBinaryContent -FilePath $stagingFile)) {
                        throw "Downloaded Beyond Compare file $stagingFile did not pass binary verification check."
                    }
                } else {
                    Write-Log "Using cached installer in staging for $($tool.name)" "INFO"
                }
            }
            elseif ($tool.downloadType -eq "git") {
                $targetExtPath = Join-Path $extensionPath $tool.fileName
                if (-not (Test-Path $targetExtPath)) {
                    Write-Log "Downloading Page Assist Chrome Extension..." "INFO"
                    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
                    
                    $stagingPageAssist = Join-Path $stagingPath "page-assist"
                    $stagingZip = Join-Path $stagingPath "page-assist.zip"
                    
                    if (Test-Path $stagingPageAssist) {
                        Remove-Item -Path $stagingPageAssist -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    if (Test-Path $stagingZip) {
                        Remove-Item -Path $stagingZip -Force -ErrorAction SilentlyContinue
                    }
                    
                    if ($gitCmd) {
                        Write-Log "Cloning Page Assist to staging folder: $stagingPageAssist" "INFO"
                        try {
                            $gitProcess = Start-Process -FilePath "git" -ArgumentList "clone", $tool.url, $stagingPageAssist -Wait -PassThru -NoNewWindow
                            if ($gitProcess.ExitCode -ne 0) {
                                throw "git clone failed with exit code $($gitProcess.ExitCode)"
                            }
                            
                            if (-not (Invoke-DefenderScan -FilePath $stagingPageAssist -SimulateMockThreat:$SimulateMockThreat)) {
                                Write-Log "Security Check: Windows Defender scan failed or threat detected for Page Assist folder. Blocking copy and disabling tool." "ERROR"
                                if (Test-Path $stagingPageAssist) {
                                    Remove-Item -Path $stagingPageAssist -Recurse -Force -ErrorAction SilentlyContinue
                                }
                                $Script:installConfig.tools[$toolName].enabled = $false
                                continue
                            }
                            
                            Write-Log "Copying Page Assist from staging to sandbox share..." "INFO"
                            Copy-Item -Path $stagingPageAssist -Destination $targetExtPath -Recurse -Force -ErrorAction Stop
                            Remove-Item -Path $stagingPageAssist -Recurse -Force -ErrorAction SilentlyContinue
                        } catch {
                            Write-Log "Page Assist git clone/copy failed: $_" "ERROR"
                            if (Test-Path $stagingPageAssist) {
                                Remove-Item -Path $stagingPageAssist -Recurse -Force -ErrorAction SilentlyContinue
                            }
                            $Script:installConfig.tools[$toolName].enabled = $false
                            continue
                        }
                    } else {
                        $zipUrl = "$($tool.url)/archive/refs/heads/main.zip"
                        Write-Log "Git not found. Downloading Page Assist Zip to staging: $stagingZip" "INFO"
                        try {
                            Download-FileWithProgress -Uri $zipUrl -OutFile $stagingZip
                            
                            if (-not (Verify-FileHash -FilePath $stagingZip -ExpectedHash $tool.hash)) {
                                Write-Log "Security Check: Hash verification failed for Page Assist Zip. Blocking and disabling tool." "ERROR"
                                if (Test-Path $stagingZip) {
                                    Remove-Item -Path $stagingZip -Force -ErrorAction SilentlyContinue
                                }
                                $Script:installConfig.tools[$toolName].enabled = $false
                                continue
                            }
                            
                            if (-not (Invoke-DefenderScan -FilePath $stagingZip -SimulateMockThreat:$SimulateMockThreat)) {
                                Write-Log "Security Check: Windows Defender scan failed or threat detected for Page Assist Zip. Blocking and disabling tool." "ERROR"
                                if (Test-Path $stagingZip) {
                                    Remove-Item -Path $stagingZip -Force -ErrorAction SilentlyContinue
                                }
                                $Script:installConfig.tools[$toolName].enabled = $false
                                continue
                            }
                            
                            Write-Log "Expanding Page Assist Zip to sandbox share..." "INFO"
                            Expand-Archive -Path $stagingZip -DestinationPath $extensionPath -Force -ErrorAction Stop
                            
                            $extractedDir = Join-Path $extensionPath "page-assist-main"
                            if (Test-Path $extractedDir) {
                                Rename-Item -Path $extractedDir -NewName "page-assist" -ErrorAction Stop
                            }
                            Remove-Item -Path $stagingZip -Force -ErrorAction SilentlyContinue
                        } catch {
                            Write-Log "Page Assist zip download/extraction failed: $_" "ERROR"
                            if (Test-Path $stagingZip) {
                                Remove-Item -Path $stagingZip -Force -ErrorAction SilentlyContinue
                            }
                            $Script:installConfig.tools[$toolName].enabled = $false
                            continue
                        }
                    }
                } else {
                    Write-Log "Using cached extension Page Assist" "INFO"
                }
            }

            # Security Check and Verification Block for Installers
            if ($stagingFile -and (Test-Path $stagingFile)) {
                # 1. Hash verification
                if (-not (Verify-FileHash -FilePath $stagingFile -ExpectedHash $tool.hash)) {
                    Write-Log "Security Check: Hash verification failed for $($tool.name). Blocking copy and disabling tool." "ERROR"
                    if (Test-Path $stagingFile) {
                        Remove-Item -Path $stagingFile -Force -ErrorAction SilentlyContinue
                    }
                    if (Test-Path $destFile) {
                        Remove-Item -Path $destFile -Force -ErrorAction SilentlyContinue
                    }
                    $Script:installConfig.tools[$toolName].enabled = $false
                    continue
                }
                
                # 2. Windows Defender Threat Scan
                if (-not (Invoke-DefenderScan -FilePath $stagingFile -SimulateMockThreat:$SimulateMockThreat)) {
                    Write-Log "Security Check: Windows Defender scan failed or threat detected for $($tool.name). Blocking copy and disabling tool." "ERROR"
                    if (Test-Path $stagingFile) {
                        Remove-Item -Path $stagingFile -Force -ErrorAction SilentlyContinue
                    }
                    if (Test-Path $destFile) {
                        Remove-Item -Path $destFile -Force -ErrorAction SilentlyContinue
                    }
                    $Script:installConfig.tools[$toolName].enabled = $false
                    continue
                }
                
                # 3. Copy from staging to shared folder
                try {
                    Write-Log "Copying installer for $($tool.name) from staging to sandbox share..." "INFO"
                    Copy-Item -Path $stagingFile -Destination $destFile -Force -ErrorAction Stop
                } catch {
                    Write-Log "Failed to copy installer for $($tool.name) to sandbox share: $_" "ERROR"
                    $Script:installConfig.tools[$toolName].enabled = $false
                    continue
                }
            }
        } catch {
            Write-Log "Failed to process tool ${toolName}: $_`n$($_.ScriptStackTrace)" "ERROR"
        }
    }

    # 6. Save Configuration to Shared Path
    try {
        # Add host OS info to install-config.json
        $hostOS = Get-HostOSInfo
        if ($null -ne $hostOS) {
            $Script:installConfig.hostOS = @{
                Caption       = $hostOS.Caption
                Version       = $hostOS.Version
                BuildNumber   = $hostOS.BuildNumber
                Architecture  = $hostOS.OSArchitecture
                ProcessorArch = $hostOS.ProcessorArch
                TargetVersion = switch ($hostOS.BuildNumber) {
                    { $_ -ge 26200 } { "Windows 11 25H2" }
                    { $_ -ge 26100 } { "Windows 11 24H2" }
                    default { "Unknown" }
                }
            }
        }
        $Script:installConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $sharePath "install-config.json") -Encoding utf8 -ErrorAction Stop
        $toolsJsonFileDestination = Join-Path $configPath "tools.json"
        Copy-Item -Path $toolsJsonFile -Destination $toolsJsonFileDestination -Force -ErrorAction Stop
    } catch {
        Write-Log "Failed to save configuration or tools.json copy: $_`n$($_.ScriptStackTrace)" "ERROR"
        Exit-Script 1
    }

    # 7. Copy Bootstrap Script to Shared Folder
    try {
        $bootstrapSource = Join-Path $scriptDir "scripts\sandbox-bootstrap.ps1"
        $bootstrapDestination = Join-Path $sharePath "sandbox-bootstrap.ps1"
        if (Test-Path $bootstrapSource) {
            Copy-Item -Path $bootstrapSource -Destination $bootstrapDestination -Force -ErrorAction Stop
        } else {
            Write-Log "Bootstrap script not found at source location $bootstrapSource yet. Ensure it is created before launching!" "WARN"
        }
    } catch {
        Write-Log "Failed to copy bootstrap script: $_`n$($_.ScriptStackTrace)" "ERROR"
        Exit-Script 1
    }

    # 9. Generate WSB Configuration
    try {
        # Windows Sandbox inherits host OS - we target Windows 11 24H2/25H2 x64
        $wsbContent = @"
<!--
    Windows Sandbox Configuration
    Target: Windows 11 24H2 (Build 26100) or 25H2 (Build 26200) - x64
    Architecture: 64-bit (x64) only
    The Sandbox VM mirrors the host's Windows version.
-->
<Configuration>
  <vGPU>Enable</vGPU>
  <Networking>Enable</Networking>
  <MemoryInMB>$SandboxMemoryMB</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$sharePath</HostFolder>
      <SandboxFolder>C:\SharedTools</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$LogsDir</HostFolder>
      <SandboxFolder>C:\ProgramData\WindowsAISandboxApps\Logs</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass -File C:\SharedTools\sandbox-bootstrap.ps1</Command>
  </LogonCommand>
</Configuration>
"@

        $wsbPath = Join-Path $scriptDir "sandbox-config.wsb"
        $wsbContent | Out-File -FilePath $wsbPath -Encoding utf8 -ErrorAction Stop
        Write-Log "Generated sandbox-config.wsb at $wsbPath" "INFO"
    } catch {
        Write-Log "Failed to generate WSB configuration: $_`n$($_.ScriptStackTrace)" "ERROR"
        Exit-Script 1
    }

    # 10. Execution
    try {
        if ($PreCacheOnly) {
            Write-Log "Pre-caching completed successfully. Exiting since -PreCacheOnly was specified." "INFO"
            Exit-Script 0
            return
        }

        Write-Log "Launching Windows Sandbox..." "INFO"
        
        # Remove old progress file if it exists to avoid stale status
        $progressFile = Join-Path $LogsDir "install-progress.json"
        if (Test-Path $progressFile) {
            Remove-Item -Path $progressFile -Force -ErrorAction SilentlyContinue
        }

        if (-not (Test-SandboxNotRunning)) {
            Write-Log "Windows Sandbox is already running. Please close it first." "ERROR"
            Exit-Script 1
        }

        $process = Start-Process WindowsSandbox -ArgumentList $wsbPath -PassThru -ErrorAction Stop
        
        $completed = $false
        while (-not $process.HasExited -and -not $completed) {
            try {
                if (Test-Path $progressFile) {
                    # Read JSON and parse
                    $jsonText = Get-Content -Raw -Path $progressFile -ErrorAction Stop
                    if ($jsonText) {
                        $progressData = ConvertFrom-Json $jsonText -ErrorAction Stop
                        $current = $progressData.currentStep
                        $total = $progressData.totalSteps
                        $active = $progressData.activeInstall
                        $status = $progressData.status
                        
                        if ($total -gt 0) {
                            $percent = [Math]::Round(($current / $total) * 100)
                            $statusStr = "Step $current of ${total}: $active ($status)"
                            Write-Progress -Activity "Provisioning AI Windows Sandbox" -Status $statusStr -PercentComplete $percent
                            
                            if ($GUI -and $Global:GuiProgressBar -and $Global:GuiStatusLabel) {
                                $Global:GuiProgressBar.Value = $percent
                                $Global:GuiStatusLabel.Text = $statusStr
                                
                                if ($Global:GuiCheckedListBox) {
                                    for ($i = 0; $i -lt $Global:GuiCheckedListBox.Items.Count; $i++) {
                                        $itemText = $Global:GuiCheckedListBox.Items[$i].ToString()
                                        if ($itemText -eq $active) {
                                            if ($status -eq "Completed" -or $status -eq "Failed") {
                                                $Global:GuiCheckedListBox.SetItemChecked($i, $true)
                                            }
                                            $Global:GuiCheckedListBox.SelectedIndex = $i
                                        } elseif ($i -lt ($current - 1)) {
                                            $Global:GuiCheckedListBox.SetItemChecked($i, $true)
                                        }
                                    }
                                }
                            }
                        } else {
                            Write-Progress -Activity "Provisioning AI Windows Sandbox" -Status "Initializing..."
                            if ($GUI -and $Global:GuiStatusLabel) {
                                $Global:GuiStatusLabel.Text = "Initializing..."
                            }
                        }
                        
                        if ($current -eq $total -and ($status -eq "Completed" -or $status -eq "Failed")) {
                            $completed = $true
                        }
                    }
                } else {
                    Write-Progress -Activity "Provisioning AI Windows Sandbox" -Status "Waiting for sandbox bootstrap to start..."
                    if ($GUI -and $Global:GuiStatusLabel) {
                        $Global:GuiStatusLabel.Text = "Waiting for sandbox bootstrap to start..."
                    }
                }
            } catch {
                Write-Log "Error during progress loop polling step: $_" "WARN"
            }
            
            if ($GUI) {
                for ($s = 0; $s -lt 20; $s++) {
                    if ($Global:GuiForm -and -not $Global:GuiForm.Visible) { break }
                    [System.Threading.Thread]::Sleep(100)
                    [System.Windows.Forms.Application]::DoEvents()
                }
                if ($Global:GuiForm -and -not $Global:GuiForm.Visible) {
                    Write-Log "Form closed. Aborting monitoring loop." "WARN"
                    break
                }
            } else {
                Start-Sleep -Seconds 2
            }
        }
        
        # Complete progress bar
        Write-Progress -Activity "Provisioning AI Windows Sandbox" -Completed
        if ($GUI -and $Global:GuiProgressBar -and $Global:GuiStatusLabel) {
            $Global:GuiProgressBar.Value = 100
            $Global:GuiStatusLabel.Text = "Provisioning completed."
        }
        
        if (-not $process.HasExited) {
            Write-Log "Sandbox provisioning completed. Waiting for Windows Sandbox to close..." "INFO"
            $process | Wait-Process
        }
        Write-Log "Windows Sandbox has closed." "INFO"
    } catch {
        Write-Log "Error during Windows Sandbox execution: $_`n$($_.ScriptStackTrace)" "ERROR"
    }
    
    # 11. Cleanup
    try {
        if ($CleanCache) {
            Write-Log "Cleaning up cached shared files at $sharePath..." "INFO"
            Remove-Item -Path $sharePath -Recurse -Force -ErrorAction Stop
            Write-Log "Cleanup completed." "INFO"
        }
    } catch {
        Write-Log "Error during cleanup: $_`n$($_.ScriptStackTrace)" "ERROR"
    }
}

if ($GUI) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
    } catch {
        Write-Log "Failed to load System.Windows.Forms or System.Drawing assemblies: $_" "ERROR"
        exit 1
    }

    $Form = New-Object System.Windows.Forms.Form
    $Form.Text = "Windows AI Sandbox Launcher"
    $Form.Size = New-Object System.Drawing.Size(760, 780)
    $Form.StartPosition = "CenterScreen"
    $Form.FormBorderStyle = "FixedDialog"
    $Form.MaximizeBox = $false

    # Font
    $defaultFont = New-Object System.Drawing.Font("Segoe UI", 9)
    $Form.Font = $defaultFont

    # GroupBox for Tools
    $toolsGroupBox = New-Object System.Windows.Forms.GroupBox
    $toolsGroupBox.Text = "Select Tools to Install"
    $toolsGroupBox.Location = New-Object System.Drawing.Point(20, 10)
    $toolsGroupBox.Size = New-Object System.Drawing.Size(700, 360)
    $Form.Controls.Add($toolsGroupBox)

    $checkboxes = @{}
    $sortedTools = $toolsJson.tools.psobject.properties | ForEach-Object {
        $name = $_.Name
        $tool = $toolsJson.tools.$name
        [PSCustomObject]@{
            Id = $name
            Name = $tool.name
            Enabled = $tool.enabled
            Order = $tool.order
        }
    } | Sort-Object Order

    $col1X = 20
    $col2X = 360
    $startY = 25
    $yGap = 26
    $index = 0

    foreach ($tool in $sortedTools) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = $tool.Name
        $cb.Checked = $tool.Enabled
        $cb.AutoSize = $true
        
        $col = $index % 2
        $row = [Math]::Floor($index / 2)
        $x = if ($col -eq 0) { $col1X } else { $col2X }
        $y = $startY + ($row * $yGap)

        $cb.Location = New-Object System.Drawing.Point($x, $y)
        $toolsGroupBox.Controls.Add($cb)
        $checkboxes[$tool.Id] = $cb
        $index++
    }

    # GroupBox for Settings
    $settingsGroupBox = New-Object System.Windows.Forms.GroupBox
    $settingsGroupBox.Text = "Sandbox Settings"
    $settingsGroupBox.Location = New-Object System.Drawing.Point(20, 380)
    $settingsGroupBox.Size = New-Object System.Drawing.Size(700, 60)
    $Form.Controls.Add($settingsGroupBox)

    $memLabel = New-Object System.Windows.Forms.Label
    $memLabel.Text = "RAM Memory Size (MB):"
    $memLabel.Location = New-Object System.Drawing.Point(20, 25)
    $memLabel.AutoSize = $true
    $settingsGroupBox.Controls.Add($memLabel)

    $memInput = New-Object System.Windows.Forms.NumericUpDown
    $memInput.Minimum = 2048
    $memInput.Maximum = 65536
    $memInput.Value = $SandboxMemoryMB
    $memInput.Increment = 1024
    $memInput.Location = New-Object System.Drawing.Point(180, 23)
    $memInput.Size = New-Object System.Drawing.Size(100, 23)
    $settingsGroupBox.Controls.Add($memInput)

    # Launch Button
    $launchButton = New-Object System.Windows.Forms.Button
    $launchButton.Text = "Launch Sandbox"
    $launchButton.Location = New-Object System.Drawing.Point(20, 455)
    $launchButton.Size = New-Object System.Drawing.Size(150, 35)
    $Form.Controls.Add($launchButton)

    # Progress Bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Location = New-Object System.Drawing.Point(190, 460)
    $progressBar.Size = New-Object System.Drawing.Size(530, 25)
    $progressBar.Minimum = 0
    $progressBar.Maximum = 100
    $progressBar.Value = 0
    $Form.Controls.Add($progressBar)

    # Status/Checklist Label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = "Ready"
    $statusLabel.Location = New-Object System.Drawing.Point(190, 490)
    $statusLabel.Size = New-Object System.Drawing.Size(530, 20)
    $Form.Controls.Add($statusLabel)

    # Checklist GroupBox
    $checklistGroupBox = New-Object System.Windows.Forms.GroupBox
    $checklistGroupBox.Text = "Bootstrap Status Checklist"
    $checklistGroupBox.Location = New-Object System.Drawing.Point(20, 520)
    $checklistGroupBox.Size = New-Object System.Drawing.Size(340, 210)
    $Form.Controls.Add($checklistGroupBox)

    $checkedListBox = New-Object System.Windows.Forms.CheckedListBox
    $checkedListBox.Location = New-Object System.Drawing.Point(15, 25)
    $checkedListBox.Size = New-Object System.Drawing.Size(310, 170)
    $checkedListBox.SelectionMode = "None"
    $checklistGroupBox.Controls.Add($checkedListBox)

    # Logs GroupBox
    $logsGroupBox = New-Object System.Windows.Forms.GroupBox
    $logsGroupBox.Text = "Real-time Installation Logs"
    $logsGroupBox.Location = New-Object System.Drawing.Point(380, 520)
    $logsGroupBox.Size = New-Object System.Drawing.Size(340, 210)
    $Form.Controls.Add($logsGroupBox)

    $logTextBox = New-Object System.Windows.Forms.TextBox
    $logTextBox.Multiline = $true
    $logTextBox.ReadOnly = $true
    $logTextBox.ScrollBars = "Vertical"
    $logTextBox.Location = New-Object System.Drawing.Point(15, 25)
    $logTextBox.Size = New-Object System.Drawing.Size(310, 170)
    $logsGroupBox.Controls.Add($logTextBox)

    # Setup Global references
    $Global:GuiLogTextBox = $logTextBox
    $Global:GuiProgressBar = $progressBar
    $Global:GuiStatusLabel = $statusLabel
    $Global:GuiCheckedListBox = $checkedListBox
    $Global:GuiForm = $Form

    $Form.Add_FormClosing({
        $Global:GuiLogTextBox = $null
        $Global:GuiProgressBar = $null
        $Global:GuiStatusLabel = $null
        $Global:GuiCheckedListBox = $null
        $Global:GuiForm = $null
    })

    $launchButton.Add_Click({
        # Disable GUI controls
        $launchButton.Enabled = $false
        foreach ($cb in $checkboxes.Values) { $cb.Enabled = $false }
        $memInput.Enabled = $false

        # Update config based on GUI inputs
        $Global:SandboxMemoryMB = [int]$memInput.Value
        
        $checkedListBox.Items.Clear()
        
        $enabledStepsList = [System.Collections.Generic.List[string]]::new()
        
        foreach ($toolName in $checkboxes.Keys) {
            $chk = $checkboxes[$toolName].Checked
            $tool = $toolsJson.tools.$toolName
            $skipVarName = $null
            if ($tool.skipFlag) {
                $skipVarName = $tool.skipFlag
            } else {
                $skipVarName = "Skip$($toolName)"
                if ($toolName -eq "beyondcompare") { $skipVarName = "SkipBeyondCompare" }
                elseif ($toolName -eq "notepadpp") { $skipVarName = "SkipNotepadPP" }
                elseif ($toolName -eq "nodejs") { $skipVarName = "SkipNpm" }
                elseif ($toolName -eq "pageassist") { $skipVarName = "SkipPageAssist" }
            }
            
            $existing = Get-Variable -Name $skipVarName -ValueOnly -ErrorAction SilentlyContinue
            if ($existing) {
                # Already skipped
            } else {
                Set-Variable -Name $skipVarName -Value (-not $chk) -Scope Script
            }
        }
        
        $chkNpm = $checkboxes["nodejs"].Checked
        $chkPython = $checkboxes["python"] -and $checkboxes["python"].Checked
        $chkCrew = $checkboxes["crewai"].Checked
        $chkChrome = $checkboxes["chrome"].Checked
        $chkPageAssist = $checkboxes["pageassist"].Checked
        $chkBrave = $checkboxes["brave"].Checked
        $chkNpp = $checkboxes["notepadpp"].Checked
        $chkBc = $checkboxes["beyondcompare"].Checked
        $chkOllama = $checkboxes["ollama"].Checked
        $chkLm = $checkboxes["lmstudio"].Checked
        $chkOpenCodeTerminal = $checkboxes["opencode-terminal"].Checked
        $chkOpenCodeDesktop = $checkboxes["opencode-desktop"].Checked
        $chkCopilot = $checkboxes["copilot"].Checked
        $chkVSCode = $checkboxes["vscode"].Checked
        $chkVSCommunity = $checkboxes["vscommunity"].Checked
        $chk7Zip = $checkboxes["7zip"].Checked
        $chkSysinternals = $checkboxes["sysinternals"].Checked
        $chkPowerToys = $checkboxes["powertoys"].Checked
        $chkWindowsSDK = $checkboxes["windowssdk"].Checked
        $chkADK = $checkboxes["adk"].Checked
        $chkADKWinPE = $checkboxes["adkwinpe"].Checked
        $chkAntigravity = $checkboxes["antigravity"].Checked

        if ($chkNpm) { [void]$enabledStepsList.Add("Node.js + npm") }
        if ($chkPython) { [void]$enabledStepsList.Add("Python") }
        if ($chkChrome) { [void]$enabledStepsList.Add("Google Chrome") }
        if ($chkPageAssist -and $chkChrome) { [void]$enabledStepsList.Add("Page Assist Extension") }
        if ($chkBrave) { [void]$enabledStepsList.Add("Brave Browser") }
        if ($chkNpp) { [void]$enabledStepsList.Add("Notepad++") }
        if ($chkBc) { [void]$enabledStepsList.Add("Beyond Compare 4") }
        if ($chkOllama) { 
            [void]$enabledStepsList.Add("Ollama")
            [void]$enabledStepsList.Add("Gemma4 Model")
            [void]$enabledStepsList.Add("nous-hermes2 Model")
        }
        if ($chkLm) { [void]$enabledStepsList.Add("LM Studio") }
        if ($chkOpenCodeTerminal) { [void]$enabledStepsList.Add("OpenCode Terminal") }
        if ($chkOpenCodeDesktop) { [void]$enabledStepsList.Add("OpenCode Desktop") }
        if ($chkCrew) { [void]$enabledStepsList.Add("Crew AI") }
        if ($chkCopilot -and $chkChrome) { [void]$enabledStepsList.Add("Microsoft Copilot PWA") }
        if ($chkVSCode) { [void]$enabledStepsList.Add("Visual Studio Code") }
        if ($chkVSCommunity) { [void]$enabledStepsList.Add("Visual Studio Community") }
        if ($chk7Zip) { [void]$enabledStepsList.Add("7-Zip") }
        if ($chkSysinternals) { [void]$enabledStepsList.Add("Sysinternals Suite") }
        if ($chkPowerToys) { [void]$enabledStepsList.Add("Windows PowerToys") }
        if ($chkWindowsSDK) { [void]$enabledStepsList.Add("Windows SDK") }
        if ($chkADK) { [void]$enabledStepsList.Add("Windows ADK") }
        if ($chkADKWinPE) { [void]$enabledStepsList.Add("Windows ADK WinPE Add-on") }
        if ($chkAntigravity) { [void]$enabledStepsList.Add("Antigravity CLI") }

        foreach ($stepName in $enabledStepsList) {
            [void]$checkedListBox.Items.Add($stepName, $false)
        }

        try {
            Invoke-SandboxLaunch
        } catch {
            Write-Log "Launch failed: $_" "ERROR"
        } finally {
            $launchButton.Enabled = $true
            foreach ($cb in $checkboxes.Values) { $cb.Enabled = $true }
            $memInput.Enabled = $true
        }
    })

    # Show the dialog
    $null = $Form.ShowDialog()
} else {
    Invoke-SandboxLaunch
}

try { Stop-Transcript -ErrorAction SilentlyContinue } catch {}

