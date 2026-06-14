# ➕ Adding New Tools to the Sandbox

This guide explains how to add a new tool to the Windows AI Sandbox.

---

## Step 1 — Add the tool definition to `config/tools.json`

Add a new key under `tools` in `config/tools.json`:

```json
"mytool": {
  "name": "My New Tool",
  "enabled": true,
  "downloadType": "direct",
  "url": "https://example.com/mytool-installer.exe",
  "fileName": "mytool-installer.exe",
  "silentArgs": "/S /norestart",
  "skipFlag": "SkipMyTool",
  "order": 12
}
```

### Properties Reference
- **`downloadType`**: Type of resolver logic. Options: `direct` (direct download URL), `github` (resolved via Releases API using `assetRegex`), `nodejs` (Node.js LTS page parsing), `scootersoftware` (Beyond Compare parsing), `git` (cloned repository).
- **`url`**: The URL to download or resolve from.
- **`assetRegex`**: Used for `github` downloads to identify the asset matching the pattern.
- **`fileName`**: Name to cache the file under on the host.
- **`silentArgs`**: Installation flags for background, non-interactive setup.

Common silent install flags by installer type:
| Installer type | Silent flag |
|---|---|
| NSIS (most `.exe`) | `/S` |
| Inno Setup | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` |
| MSI | `/quiet /norestart` |
| WiX | `/quiet /norestart` |

---

## Step 2 — Add the skip flag to `Launch-AISandbox.ps1`

Add the skip flag switch parameter at the top of `Launch-AISandbox.ps1`:

```powershell
[switch]$SkipMyTool,
```

Also configure the mapping in the `foreach` loop inside `Launch-AISandbox.ps1`:

```powershell
elseif ($toolName -eq "mytool") { $skipVarName = "SkipMyTool" }
```

---

## Step 3 — Add the install block to `scripts/sandbox-bootstrap.ps1`

Find the order location in `scripts/sandbox-bootstrap.ps1` and add:

```powershell
# Order 12: My New Tool
if ($tools.mytool.enabled) {
    $installer = "C:\SharedTools\Installers\$($tools.mytool.fileName)"
    $res = Install-SilentProcess -ToolId "mytool" -ToolName "My New Tool" -InstallerPath $installer -SilentArgs $tools.mytool.silentArgs
    $results["mytool"] = $res
} else {
    Write-Log "[SKIP] My New Tool"
    $results["mytool"] = "SKIP"
}
```

---

## Step 4 — Run and Test

Run the launcher from PowerShell:
```powershell
.\Launch-AISandbox.ps1
```
Check `C:\sandbox-install.log` inside the sandbox to ensure your tool installed successfully.
