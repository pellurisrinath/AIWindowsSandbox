# 🪟 Windows AI Sandbox (PROMPT_NEW version)

> A fully automated, disposable Windows Sandbox environment pre-loaded with AI runtimes, browsers, and essential developer tools — provisioned by a single PowerShell script.

---

## Overview

**Windows AI Sandbox** automates the creation of a fully isolated, ephemeral Windows Sandbox session loaded with a curated set of AI tools, browsers, developer utilities, and productivity software. Everything is downloaded and installed fresh on every launch. When the sandbox closes, nothing persists to the host machine — perfect for safe experimentation, demos, client presentations, or reproducible AI dev environments.

### Key Design Principles

| Principle | Detail |
|---|---|
| **Fully disposable** | Sandbox state is destroyed on close; host is never modified |
| **Self-contained** | All installers are downloaded fresh or pre-cached to a shared folder |
| **Silent installs** | No UI popups, no confirmation dialogs, no reboots during provisioning |
| **Selective** | Skip any tool via `-Skip*` flags |
| **Extensible** | Modular config design — add new tools in one place (`config/tools.json`) |

---

## Repository Structure

```
windows-ai-sandbox/
├── README.md                   ← project overview, quick start, requirements
├── USER_GUIDE.md               ← full usage walkthrough (the "Usage Guide" output)
├── PROMPT.md                   ← single source of truth for generation
├── CHANGELOG.md                ← versioned record of prompt/script changes
├── Launch-AISandbox.ps1        ← host-side launcher
├── scripts/
│   └── sandbox-bootstrap.ps1   ← in-sandbox logon script
├── config/
│   └── tools.json              ← tool registry (URLs, silent args, etc.)
└── docs/
    ├── troubleshooting.md       ← common failures (vGPU, Ollama route, silent flags)
    └── adding-new-tools.md      ← how to extend tools.json + bootstrap
```

---

## Prerequisites

- **Windows 10/11 Pro, Enterprise, or Education** (Windows Sandbox feature is not supported on Home editions).
- **Windows Sandbox feature enabled**.
- **PowerShell 5.1 or higher** (run as Administrator).
- **Network connection** (to resolve and download installers).

---

## Software Installed

The sandbox will silently install the following software packages depending on skip flags:

- **Ollama** — Silent installation, pulls `nous-hermes2` model automatically.
- **LM Studio** — Silent installation of the desktop inference platform.
- **OpenCode** — CLI tool configured against local Ollama endpoint.
- **Google Chrome** — Pre-loaded with **Page Assist** extension shortcut.
- **Brave Browser** — Desktop browser.
- **Node.js + npm (LTS)** — Core runtime environment.
- **Python 3** — Pre-installed to support `pip` and **Crew AI**.
- **Notepad++** — Text editor.
- **Beyond Compare 4** — Folder and file diffing.
- **Crew AI** — Python framework for agent orchestrations.
- **Microsoft Copilot PWA** — Silently deployed Chrome app.

---

## ⭐ Star History

[![Star History Chart](https://api.star-history.com/svg?repos=pellurisrinath/AIWindowsSandbox&type=Date)](https://star-history.com/#pellurisrinath/AIWindowsSandbox)

A ⭐ helps other developers find this project.

---

## Quick Start

1. Open PowerShell as Administrator.
2. Allow script execution if not already set:
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```
3. Run the launcher:
   ```powershell
   # Launch with all tools
   .\Launch-AISandbox.ps1

   # Skip specific tools (e.g. Brave and Beyond Compare)
   .\Launch-AISandbox.ps1 -SkipBrave -SkipBeyondCompare
   ```

Check the `C:\sandbox-install.log` file inside the sandbox to monitor progress.
