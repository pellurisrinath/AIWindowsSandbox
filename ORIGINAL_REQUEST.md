# Original User Request

## Initial Request — 2026-06-14T14:12:46+02:00

Enhance the Windows AI Sandbox project scripts (Launch-AISandbox.ps1 and sandbox-bootstrap.ps1) with a GUI status window, detailed progress bar, advanced logging to C:\ProgramData\AIWindowsSandbox\Logs, and robust error handling.

Working directory: C:\Users\pellu\OneDrive\Documents\AntiGravity_AIWindowsSandbox
Integrity mode: demo

## Requirements

### R1. Logs Directory and Transcript Logging
All runtime execution progress, steps, successes, and warnings/errors must be logged to a detailed transcript log file in the folder `C:\ProgramData\AIWindowsSandbox\Logs` on the host side.

### R2. Detailed Progress Bar
When the launcher or bootstrap is executing, it must display a detailed, active progress bar indicating the status of the downloads and tool installations.

### R3. GUI-Based Status Window
When running `Launch-AISandbox.ps1` with the `-GUI` parameter, a graphical user interface (GUI) window built using **Windows Forms (System.Windows.Forms)** must be displayed to show real-time installation progress, status checklists, and logs.

### R4. Robust Error Handling
All script blocks must utilize try-catch blocks to handle unexpected exceptions and write detailed error stack traces and messages to the log files.

## Constraints & Integrity Rules
- Prohibit running external scripts or delegating execution to other third-party tools (other than the Windows Sandbox execution itself).
- Prohibit copying code from external open-source projects unless scanned thoroughly for security risks.

## Acceptance Criteria

### Execution & Verification
- [ ] Running with `-GUI` launches a responsive Windows Forms GUI window showing tool status.
- [ ] Progress bar updates dynamically during execution.
- [ ] Logs are written to `C:\ProgramData\AIWindowsSandbox\Logs` containing timestamps and detailed transcripts.
- [ ] Failures in individual tool installs are caught via try-catch and fully logged.

## Follow-up — 2026-06-14T13:23:49Z

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
