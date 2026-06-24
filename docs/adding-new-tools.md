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
| Inno Setup | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` (also `/SP-` to skip the "are you sure" prompt) |
| MSI / WiX | `msiexec /i foo.msi /qn /norestart` (the helper auto-appends `/L*v "<log>"` for `.msi` if `logFile` is configured) |
| WiX Burn bundle (PowerToys, ADK, SDK) | `/quiet /norestart` |
| VS Burn bootstrapper (VS Community) | `--quiet --wait --norestart --add <workload-id> ...` |
| Chrome / Brave bootstrapper | `/silent /install` (add `--system-level` for explicit per-machine) |
| Sysmon (special case) | `sysmon64 -accepteula -i <config.xml>` — `-accepteula` is **mandatory** otherwise the EULA prompt hangs |

### Exit codes
The `Install-SilentProcess` helper treats the following exit codes as success:
- `0` — success
- `1641` — MSI: restart initiated (success, reboot in progress)
- `3010` — MSI: restart required (success, reboot pending)

These reboot-related codes are emitted legitimately by VS Community, PowerToys, ADK, and SDK even with `/norestart`, so they should not be treated as failures in the Windows Sandbox (the VM is discarded on close).

### Per-user / per-machine installs
The Windows Sandbox runs as the `WDAGUtilityAccount` with admin rights. For "install for all users" semantics:
- **MSI**: include `ALLUSERS=1` in `silentArgs` (e.g. `/qn ALLUSERS=1 /norestart`).
- **Inno Setup / NSIS**: run as admin (which the sandbox bootstrap does) — these install to `Program Files` and write to `HKLM` by default.
- **PATH additions**: use `[System.Environment]::SetEnvironmentVariable("Path", "...", [System.EnvironmentVariableTarget]::Machine)`.

### Special cases
- **Sysmon**: Microsoft ships Sysinternals only as a ZIP; there is no official MSI. The bootstrap extracts the ZIP to `C:\Tools\Sysinternals`, adds it to Machine PATH, and runs `sysmon64 -accepteula -i <default-config.xml>` to install the driver + service.
- **Page Assist / Chrome extensions**: extensions are not traditional installers. The bootstrap creates a desktop shortcut that launches Chrome with `--load-extension=<path>`.
- **Ollama**: the installer is an Inno Setup bundle. Even with `/S`, Ollama registers a Windows service (`OllamaWindows.exe`) that auto-starts and may briefly hold the bootstrap while initializing.
- **Windows ADK / SDK**: these are Burn web installers that download several GB of payload before installing. With `/quiet /norestart` they run unattended but may take 5-30 minutes.

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

---

## Status window (translucent bottom-right popup)

A small WinForms popup appears in the bottom-right of the sandbox desktop the moment the bootstrap starts. It shows:

- The current step number and tool name (e.g. "Step 7 / 18 — Google Chrome")
- A progress bar (0–100 %)
- Live counters: Installed / Failed / Skipped
- An **opacity slider** (30 %–100 %) so the user can dial down translucency

When all installs finish, the window switches to a summary screen with the final counts and an **OK** button. The sandbox bootstrap blocks until the user clicks OK.

### Implementation notes
- The popup runs in the same PowerShell process as the bootstrap (no extra runtime). The WinForms message loop is pumped via `[System.Windows.Forms.Application]::DoEvents()` calls injected into:
  - `Update-InstallProgress` (after every step's progress JSON write)
  - `Wait-ProcessWithDoEvents` (a new helper that replaces `-Wait` on long-running `Start-Process` calls)
- Communication is via two JSON files in `C:\ProgramData\WindowsAISandboxApps\Logs\`:
  - `install-progress.json` — already written by the existing `Update-InstallProgress` helper
  - `status-counters.json` — new, written by `Update-StatusCounters` on every progress update
- The popup's polling `Timer` reads these files every 500 ms. No cross-thread marshaling.
- The OK button is the only way to dismiss the form. ALT+F4 and the X button are wired to no-op before the summary appears.
- Pass `-NoStatusWindow` to the bootstrap (via WSB `LogonCommand` or by editing the WSB) to suppress the popup entirely and fall back to the original end-of-bootstrap `MessageBox`.

### Where the popup logic lives
All status-window code is in `scripts/sandbox-bootstrap.ps1`:
- `Initialize-StatusWindow` — loads WinForms assemblies
- `New-StatusWindow` — creates the form, controls, opacity slider, polling timer
- `Show-StatusSummary` — switches the form to summary mode
- `Close-StatusWindow` — disposes the form
- `Wait-ProcessWithDoEvents` — message-loop pump used in place of `-Wait`

---

## Installer caching and "skip if already present" behavior

The bootstrap has two layers of caching that work together to avoid re-downloading installers.

### Host-side cache (Launch-AISandbox.ps1)
- Staging directory: `%TEMP%\AISandboxStaging`
- `Test-InstallerAlreadyCached` (in `Launch-AISandbox.ps1:484-497`) checks the staging file's existence, size (>100KB), and binary content (PE/OLE header validation) before re-downloading from the internet
- If the cached file is valid, the host logs `"Using cached installer in staging for X"` and skips the download
- This layer persists across sandbox runs

### Sandbox-side copy (sandbox-bootstrap.ps1)
- Source: `C:\SharedTools\Installers` (the mapped share, read-only)
- Destination: `C:\ProgramData\WindowsAISandboxApps\Installers` (writable, ephemeral)
- The bootstrap retries each copy up to **5 times** with 1s backoff to handle Windows Defender locks
- Before copying, it checks if the destination already has a same-sized file (the bootstrap ran on the host earlier). If so, it skips the copy with `"Skipped (already present)"` — saves ~1s on interrupted re-runs
- If **0 files** were copied after all retries, the bootstrap **fails fast** with a clear error rather than silently running 22 install blocks that all fail
- A 2-second startup settle delay runs before the copy loop to give Defender time to finish scanning the mapped share

### What you should NOT do
- Don't clear `%TEMP%\AISandboxStaging` between runs unless you want to force a re-download (e.g. if a new version is available)
- Don't clear `C:\ProgramData\WindowsAISandboxApps\Installers` on the host (it's the destination that gets skipped)
- The sandbox's `C:\ProgramData\...` is **discarded** when the sandbox VM closes — there's no need to clean it
