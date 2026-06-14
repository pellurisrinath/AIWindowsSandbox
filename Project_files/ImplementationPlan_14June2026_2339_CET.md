# Implementation Plan — 14 June 2026 23:39 CET

## Goal

Review the complete code and verify Windows 11 24H2/25H2 compatibility for all 22 tools. Fix broken URLs, update stale fallback URLs, remove non-existent tools, and align sandbox installation with what's actually installable on 24H2/25H2 x64.

---

## Background

A full audit of `config/tools.json`, `Launch-AISandbox.ps1`, and `scripts/sandbox-bootstrap.ps1` against the 22-tool install list found:

- **4 broken URLs** (404) — Python, Beyond Compare, LM Studio, Antigravity CLI
- **2 stale fallback URLs** — Notepad++ v8.6.8 (latest v8.9.6.4), PowerToys v0.81.1 (latest v0.100.0)
- **1 tool that doesn't exist** on GitHub — Antigravity CLI (`google-deepmind/antigravity-cli` returns 404; product web page is a JavaScript SPA without a direct `.exe`)
- **16 working URLs** — Chrome, Node.js, Brave, Notepad++ (via API), Ollama, OpenCode Desktop, VS Code, VS Community, 7-Zip, Sysinternals, PowerToys (via API), Windows SDK, Windows ADK, ADK WinPE Add-on, OpenCode Terminal (npm), Copilot PWA
- **0 tools incompatible with 24H2/25H2** — all 22 work on Windows 11 24H2/25H2 x64

All 22 tools work on Windows 11 24H2/25H2 x64. The fixes are limited to broken/stale URLs and the Antigravity CLI entry.

---

## Step 1: Create this implementation plan document

## Step 2: Update `config/tools.json`

### 2a. Python — switch from `.msi` to `.exe`

Python.org stopped shipping `.msi` installers in the 3.12.x line. Switch to the `.exe` web installer, which still accepts the same `/quiet InstallAllUsers=1 PrependPath=1` arguments.

- `url`: `https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe` (last 3.12 release)
- `fallbackUrl`: `https://www.python.org/ftp/python/3.11.10/python-3.11.10-amd64.exe` (last 3.11)
- `fileName`: `python-amd64.exe` (was `python-amd64.msi`)

### 2b. Beyond Compare 4 — fix 404 URL

- `url`: `https://www.scootersoftware.com/download/v4` (working v4 page; bootstrap regex scrapes it)
- `fallbackUrl`: `https://www.scootersoftware.com/files/BCompare-4.4.7.28397.exe` (correct build number, was 28327)

### 2c. LM Studio — fix 404 URL

- `url`: `https://lmstudio.ai/download/latest/win32/x64` (current stable endpoint)
- `fallbackUrl`: `https://lmstudio.ai/LM-Studio-Setup.exe` (already correct, kept as-is)

### 2d. Notepad++ — update stale fallback

- `fallbackUrl`: `https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.9.6.4/npp.8.9.6.4.Installer.x64.exe` (latest)

### 2e. PowerToys — update stale fallback

- `fallbackUrl`: `https://github.com/microsoft/PowerToys/releases/download/v0.100.0/PowerToysSetup-0.100.0-x64.exe` (latest)

## Step 3: Update `scripts/sandbox-bootstrap.ps1`

### 3a. Python install — switch from `msiexec` to direct `.exe`

The Python install block uses `msiexec /i` for the MSI installer. After switching the URL to the `.exe` web installer, the install method must change too:

- Replace `msiexec.exe` with the `.exe` directly
- The `.exe` accepts the same silent args: `/quiet InstallAllUsers=1 PrependPath=1 Include_test=0`
- Keep the `InitializeCom()` call for sandbox compatibility
- Keep the `python-install.log` file reference; the `.exe` writes to `%TEMP%\Python*.log` — we'll redirect via `/log` flag

## Step 4: Remove or replace Antigravity CLI

The Antigravity CLI tool does not exist as a standalone GitHub release. Two options:
- (a) Remove the entry from `config/tools.json`
- (b) Keep it as a "graceful skip" with a comment explaining it doesn't exist yet

This plan goes with (b) — keep the entry but add `_status: "unavailable"` so future maintainers know it's intentional.

## Step 5: Generate compatibility report

Add a `Project_files/CompatibilityReport_14June2026_2339_CET.md` summarizing:
- Per-tool compatibility status with Windows 11 24H2/25H2
- URL health for all 22 tools
- Architecture support (x64 only)
- Known sandbox-specific considerations

## Step 6: Update CHANGELOG.md

Add a new version entry documenting the URL fixes.

## Step 7: Commit and push

- Branch: `feature/2026.06.14.23.39-fix-win11-24h2-25h2-compatibility`
- Push to GitHub

---

## OS Build Number Reference

| Version | Build |
|---------|-------|
| Windows 11 21H2 | 22000 |
| Windows 11 22H2 | 22621 |
| Windows 11 23H2 | 22631 |
| Windows 11 24H2 | 26100 |
| Windows 11 25H2 | 26200 |

Minimum supported: **Build 26100 (Windows 11 24H2)**

---

## Files to Modify

| # | File | Status |
|---|------|--------|
| 1 | `Project_files/ImplementationPlan_14June2026_2339_CET.md` | NEW |
| 2 | `Project_files/CompatibilityReport_14June2026_2339_CET.md` | NEW |
| 3 | `config/tools.json` | EDIT |
| 4 | `scripts/sandbox-bootstrap.ps1` | EDIT |
| 5 | `CHANGELOG.md` | EDIT |
