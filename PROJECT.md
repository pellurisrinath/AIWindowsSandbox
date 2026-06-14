# Project: Windows AI Sandbox Security Checks

## Architecture
- Host-side launcher `Launch-AISandbox.ps1` downloads installers to a shared temporary directory.
- Before copying, it does Windows Defender scans and file checksum verification.
- It generates `sandbox-config.wsb` and launches Windows Sandbox.
- Inside sandbox, logon script `scripts/sandbox-bootstrap.ps1` runs.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | Initial Exploration | Run discovery, analyze `Launch-AISandbox.ps1` and dependencies. | none | PLANNED |
| 2 | Code Implementation | Implement malware scanning, checksum verification, and OpenCode download link. | M1 | PLANNED |
| 3 | Verification Testing | Run manual/automated tests to confirm functionality of scan, checksum and downloads. | M2 | PLANNED |

## Interface Contracts
- Host-side launcher writes logs to `C:\ProgramData\AIWindowsSandbox\Logs\Launch-AISandbox.log`.
- Shared folder at `$env:TEMP\AISandboxShare` contains `Installers`, `Extensions`, `config` and logon script.
- Config file `config/tools.json` maps metadata, download type, urls, checksums, etc.
