# Implementation Plan: Windows AI Sandbox Generator

This plan outlines the architecture and implementation steps to build the Windows AI Sandbox generator based on the new specifications in `PROMPT_NEW.md`.

## Proposed Architecture

1. **Host-side Launcher (`Launch-AISandbox.ps1`)**:
   - Elevated privileges check and auto-elevation.
   - Pre-flight checks: check if Windows Sandbox optional feature is enabled. If not, offer to enable it and exit (requires reboot).
   - Read `config/tools.json` to understand registry of tools.
   - Evaluate `-Skip*` flags to filter the list of tools to install.
   - Download enabled installers to a shared temporary directory: `$env:TEMP\AISandboxShare\Installers\`.
   - Clone or download the Page Assist Chrome Extension and place it in `$env:TEMP\AISandboxShare\Extensions\page-assist\`.
   - Generate `install-config.json` containing the status (enabled/disabled) and parameters for each tool.
   - Generate the `.wsb` (Windows Sandbox configuration) file pointing to the shared directory and with configured RAM (minimum 16384 MB), vGPU, and Networking enabled.
   - Launch Windows Sandbox and wait for it to exit (or run asynchronously if required).
   - Clean up the cache if `-CleanCache` is set.

2. **In-Sandbox Bootstrap (`scripts/sandbox-bootstrap.ps1`)**:
   - Automatically runs inside the sandbox via the logon command.
   - Sets up logs at `C:\sandbox-install.log`.
   - Reads `C:\SharedTools\install-config.json` to verify which tools to install.
   - Installs tools sequentially according to their dependency order:
     1. Node.js + npm
     2. Python (checked and installed if missing, required for CrewAI)
     3. Google Chrome (and loads Page Assist unpacked extension via Chrome shortcut or policy)
     4. Brave Browser
     5. Notepad++
     6. Beyond Compare 4
     7. Ollama (starts service, pulls `nous-hermes2`)
     8. LM Studio
     9. OpenCode
     10. CrewAI (via pip)
     11. Microsoft Copilot PWA (Chrome app shortcut)
     12. Placeholder tools (Antigravity 2.0) with graceful skip and warnings.
   - Sends a Toast notification/MessageBox upon completion.

3. **Tool Registry (`config/tools.json`)**:
   - Defines all download URLs, installer arguments, validation commands, and flags in a clean JSON format.

4. **Documentation**:
   - Update `README.md` and `USER_GUIDE.md` to reflect the new tool list and configuration.

## Proposed Changes

### Root Workspace

#### [NEW] [Launch-AISandbox.ps1](file:///C:/Users/pellu/OneDrive/Documents/AntiGravity_AIWindowsSandbox/Launch-AISandbox.ps1)
The primary entry point on the host. It handles elevation, optional feature validation, installer pre-caching, `.wsb` file generation, and launcher execution.

### Config Component

#### [NEW] [tools.json](file:///C:/Users/pellu/OneDrive/Documents/AntiGravity_AIWindowsSandbox/config/tools.json)
Central configuration containing URL resolution paths, download destinations, parameters, and installer flags.

### Scripts Component

#### [NEW] [sandbox-bootstrap.ps1](file:///C:/Users/pellu/OneDrive/Documents/AntiGravity_AIWindowsSandbox/scripts/sandbox-bootstrap.ps1)
The script that runs inside the Windows Sandbox instance to perform silent installs, logs outputs, and alerts the user.

### Documentation

#### [MODIFY] [README.md](file:///C:/Users/pellu/OneDrive/Documents/AntiGravity_AIWindowsSandbox/README.md)
Update the README to match the new tool list from `PROMPT_NEW.md`.

#### [MODIFY] [USER_GUIDE.md](file:///C:/Users/pellu/OneDrive/Documents/AntiGravity_AIWindowsSandbox/USER_GUIDE.md)
Update the guide to match the new tools and flags.

#### [NEW] [troubleshooting.md](file:///C:/Users/pellu/OneDrive/Documents/AntiGravity_AIWindowsSandbox/docs/troubleshooting.md)
Detailed guide on common execution problems.

#### [NEW] [adding-new-tools.md](file:///C:/Users/pellu/OneDrive/Documents/AntiGravity_AIWindowsSandbox/docs/adding-new-tools.md)
Instructions on how to register and deploy new applications.

## Verification Plan

### Manual Verification
- We will execute the scripts locally to verify file generation, download flows, and sandbox configuration.
- We will double check that all download endpoints resolve correctly.
