# Implementation Plan — 14 June 2026 23:09 CET

## Goal
Update Windows Sandbox to target **Windows 11 25H2** and update the installation logic to support **Windows 11 24H2 or Windows 11 25H2 (x64)**. Add OS detection in both host launcher and in-sandbox bootstrap script to handle architecture and version differences.

---

## Step 1: Create Implementation Plan Document
This file: `Project_files/ImplementationPlan_14June2026_2309_CET.md`

## Step 2: Update `Launch-AISandbox.ps1`

### 2a. Add host-side OS detection
- Detect host Windows version (build number)
- Build 26100 = Windows 11 24H2
- Build 26200 = Windows 11 25H2
- Warn if host is older than 24H2
- Block launch with clear error if host is not Windows 11 Pro/Enterprise/Education

### 2b. Update WSB configuration
- Add OS version metadata to WSB config (informational)
- Ensure x64 bit operating system is the only supported architecture
- Document the minimum requirement (Windows 11 24H2 / Build 26100+)

### 2c. Pass OS info to install-config.json
- Add `hostOS` and `hostArch` fields to install-config.json
- The bootstrap script uses this to make OS-specific decisions

## Step 3: Update `scripts/sandbox-bootstrap.ps1`

### 3a. Add in-sandbox OS detection
- Detect Windows version from registry/WMI
- Detect architecture (must be x64)
- Refuse to run if not Windows 11 24H2/25H2 x64
- Log OS info to log file for debugging

### 3b. Use detected OS info
- For tools that have OS-specific installers, use the correct one
- Log OS detection to the verification report

## Step 4: Update `config/tools.json`

### 4a. Add OS-specific installer variants where needed
- Most installers work for both 24H2 and 25H2 (same x64 binary)
- Add explicit x64-only requirement
- Add OS build minimum in metadata

## Step 5: Update Documentation

### 5a. Update `Project_files/README.md`
- Change "Windows 11 22H2 or later" to "Windows 11 24H2 or later (Build 26100+)"
- Mention 25H2 support

### 5b. Update `Project_files/USER_GUIDE.md`
- Update system requirements section

## Step 6: Update CHANGELOG.md
- Add new version entry documenting the OS upgrade

## Step 7: Commit and Push
- Branch: `feature/2026.06.14.23.09-update-windows-sandbox-25h2`
- Push to GitHub

---

## OS Build Number Reference

| Version | Build Number |
|---------|--------------|
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
| 1 | `Project_files/ImplementationPlan_14June2026_2309_CET.md` | NEW |
| 2 | `Launch-AISandbox.ps1` | EDIT |
| 3 | `scripts/sandbox-bootstrap.ps1` | EDIT |
| 4 | `config/tools.json` | EDIT |
| 5 | `Project_files/README.md` | EDIT |
| 6 | `Project_files/USER_GUIDE.md` | EDIT |
| 7 | `CHANGELOG.md` | EDIT |
