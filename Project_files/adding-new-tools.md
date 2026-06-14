# ➕ Adding New Tools to the Sandbox

This guide explains how to add a new tool to the Windows AI Sandbox in 5 steps.

---

## Step 1 — Add the tool to `config/tools.json`

```json
{
  "tools": {
    "mytool": {
      "enabled": true,
      "description": "What this tool does",
      "installerFileName": "mytool-installer.exe",
      "silentArgs": "/S /NORESTART",
      "verifyCommand": "mytool.exe --version",
      "postInstall": ""
    }
  }
}
```

**`installerFileName`** — the filename that will be saved to `C:\SharedTools\Installers\`
**`silentArgs`** — the flags to pass for silent, unattended installation
**`verifyCommand`** — a command to run to confirm the install worked
**`postInstall`** — optional command to run after install (e.g. `ollama pull llama3`)

Common silent install flags by installer type:
| Installer type | Silent flag |
|---|---|
| NSIS (most `.exe`) | `/S` |
| Inno Setup | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` |
| MSI | `/quiet /norestart` |
| WiX | `/quiet /norestart` |

---

## Step 2 — Add the download URL to `Launch-AISandbox.ps1`

Find the download section (marked `## TOOL DOWNLOADS`) and add:

```powershell
if (-not $SkipMyTool) {
    Write-Progress "Downloading MyTool..."
    $myToolUrl = "https://example.com/mytool-installer.exe"
    # If using GitHub releases API:
    # $release = Invoke-RestMethod "https://api.github.com/repos/owner/repo/releases/latest"
    # $myToolUrl = ($release.assets | Where-Object { $_.name -like "*win*x64*.exe" }).browser_download_url
    Invoke-WebRequest -Uri $myToolUrl -OutFile "$SharedFolder\Installers\mytool-installer.exe" -UseBasicParsing
}
```

---

## Step 3 — Add the skip flag parameter

At the top of `Launch-AISandbox.ps1`, in the `param()` block, add:

```powershell
[switch]$SkipMyTool,
```

---

## Step 4 — Write the install config entry

In the section that generates `install-config.json`, add:

```powershell
mytool = @{ enabled = (-not $SkipMyTool) }
```

---

## Step 5 — Add the install block to `sandbox-bootstrap.ps1`

Find the right position in the install order (dependency-aware) and add:

```powershell
# ── MyTool ──────────────────────────────────────────────────────
if ($config.tools.mytool.enabled) {
    Write-Log "Installing MyTool..."
    try {
        $installer = "C:\SharedTools\Installers\mytool-installer.exe"
        if (-not (Test-Path $installer)) {
            Write-Log "[ERROR] MyTool installer not found at $installer"
        } else {
            $proc = Start-Process -FilePath $installer `
                                  -ArgumentList "/S /NORESTART" `
                                  -Wait -PassThru -NoNewWindow
            if ($proc.ExitCode -in @(0, 3010)) {
                Write-Log "[OK] MyTool installed (exit code: $($proc.ExitCode))"
            } else {
                Write-Log "[WARN] MyTool exited with code $($proc.ExitCode)"
            }
        }
    } catch {
        Write-Log "[ERROR] MyTool install exception: $_"
    }
} else {
    Write-Log "[SKIP] MyTool (disabled)"
}
```

---

## Done!

Test it with:
```powershell
.\Launch-AISandbox.ps1 -Verbose
```

Check the result in the sandbox at `C:\sandbox-install.log`.
