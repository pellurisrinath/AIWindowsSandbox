# Implementation Plan — 14 June 2026 18:09 CET

## Goal
Fix all tool installation errors in Windows AI Sandbox so that every tool installs successfully inside the sandbox, with verbose logging and proper error handling.

---

## Step 1: Create `Project_files/ImplementationPlan_14June2026_1809_CET.md`
This document — the master plan.

## Step 2: Update `config/tools.json`

### 2a. Python — switch to MSI installer with verbose logging
- Change URL to: `https://www.python.org/ftp/python/3.12.4/python-3.12.4-amd64.msi`
- Change `fileName` to: `python-amd64.msi`
- Add `logFile` field: `C:\ProgramData\WindowsAISandboxApps\Logs\python-install.log`
- Update `silentArgs` to MSI-compatible args

### 2b. OpenCode Terminal — switch to npm install
- Change `downloadType` to `"npm"`
- Clear URL/fileName/silentArgs
- Update `skipFlag` to `SkipOpenCodeTerminal`

### 2c. OpenCode Desktop — fix URL and filename
- Change URL to: `https://opencode.ai/download/stable/windows-x64-nsis`
- Add `fallbackUrl`: `https://github.com/anomalyco/opencode/releases/latest/download/opencode-desktop-win-x64.exe`
- Change `fileName` to: `opencode-desktop-win-x64.exe`

---

## Step 3: Update `scripts/sandbox-bootstrap.ps1`

### 3a. Change log directory
- Line 8: `C:\ProgramData\AIWindowsSandbox\Logs` → `C:\ProgramData\WindowsAISandboxApps\Logs`
- Line 121: Update hardcoded path in `Update-InstallProgress`
- Line 932: Update MessageBox reference

### 3b. Fix Python install (lines 223-270)
- Use `msiexec /i` with `/L*v` for verbose logging
- Initialize COM before install
- Use new `.msi` filename

### 3c. Fix Ollama install (lines 401-515)
- Add WDAC bypass: set `VerifiedAndReputablePolicyState` to 0
- Add curl fallback: download CLI directly if installer blocked

### 3d. Fix OpenCode Terminal install (lines 539-559)
- Replace direct install with `npm i -g opencode-ai`
- Check Node.js is available first

### 3e. Fix Copilot PWA (lines 617-642)
- Replace hardcoded Chrome path with dynamic lookup
- Remove invalid `--install-webapp` flag
- Create desktop shortcut instead

### 3f. Add verbose logging to `Install-SilentProcess`
- Add optional `LogFile` parameter
- Auto-append `/L*v` for MSI installers

---

## Step 4: Update `Launch-AISandbox.ps1`

### 4a. Fix Node.js fallback URL (line 301)
- Change from v20.12.2 to v20.18.0

### 4b. Add MSI binary verification
- Add OLE header check (D0 CF 11 E0) in `Verify-DownloadedBinaryContent`

### 4c. Handle npm downloadType
- Add case for `downloadType -eq "npm"` to skip host-side download

### 4d. Update WSB log path
- Change `<SandboxFolder>` to `C:\ProgramData\WindowsAISandboxApps\Logs`

### 4e. Add sandbox running check
- Use `Test-SandboxNotRunning` before `Start-Process WindowsSandbox`

---

## Step 5: Update `Start_Launch-AISandboxPS1-withGUIModeON.bat`
- Remove `if %errorlevel%` conditional — always wait after kill

---

## Step 6: Update `CHANGELOG.md`
- Add version 2026.06.14.18.09 entry with all fixes

---

## Step 7: Commit and Push
- Branch: `feature/2026.06.14.18.09-fix-all-installation-errors`
- Commit all changes
- Push to GitHub

---

## Files to Modify

| # | File | Status |
|---|------|--------|
| 1 | `Project_files/ImplementationPlan_14June2026_1809_CET.md` | NEW |
| 2 | `config/tools.json` | EDIT |
| 3 | `scripts/sandbox-bootstrap.ps1` | EDIT |
| 4 | `Launch-AISandbox.ps1` | EDIT |
| 5 | `Start_Launch-AISandboxPS1-withGUIModeON.bat` | EDIT |
| 6 | `CHANGELOG.md` | EDIT |
