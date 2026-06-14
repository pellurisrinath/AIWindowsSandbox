# Teamwork Project Prompt — Draft

> Status: Launched
> Goal: Craft prompt → get user approval → delegate to teamwork_preview

Enhance the Windows AI Sandbox host-side launcher (Launch-AISandbox.ps1) to perform pre-download and pre-install security checks (Windows Defender scans and file checksum verification) on installers, and update the OpenCode download link.

Working directory: C:\Users\pellu\OneDrive\Documents\AntiGravity_AIWindowsSandbox
Integrity mode: demo

## Requirements

### R1. Anti-Malware / Virus Scanning (Pre-install)
Before transferring and running installers inside the sandbox, the host-side launcher must scan each downloaded installer file for virus and malware signatures using Windows Defender (via PowerShell's native `Start-MpScan` or `MpCmdRun.exe`). If any installer fails the security scan or is flagged, execution/copying for that installer must be blocked and a warning logged.

### R2. Checksum / Hash Verification
Implement verification of downloaded files against pre-calculated file hashes (where available) to ensure file integrity before copy operations.

### R3. Updated OpenCode Download Link
Modify the OpenCode registry logic to download from the official link: `https://opencode.ai/download` instead of querying the GitHub release API.

## Acceptance Criteria

### Execution & Verification
- [ ] Launching the sandbox triggers Defender security scans on all enabled installers prior to copying them to the sandbox share.
- [ ] If a mock malware file is placed in the installers folder, the script detects it, logs a critical error, blocks its transfer to the sandbox, and does not try to install it.
- [ ] OpenCode tool downloads successfully from the link `https://opencode.ai/download`.
