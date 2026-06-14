# 🪟 Windows AI Sandbox

> A fully automated, disposable Windows Sandbox environment pre-loaded with AI runtimes, developer tools, browsers, and productivity utilities — provisioned by a single PowerShell script.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Hardware Requirements](#hardware-requirements)
- [Software Installed](#software-installed)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Script Reference](#script-reference)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Known Limitations & Placeholders](#known-limitations--placeholders)
- [Contributing](#contributing)
- [License](#license)

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
| **Extensible** | Modular bootstrap design — add new tools in one place |

---

## Architecture

```
Host Machine (Windows 11)
│
├── Launch-AISandbox.ps1          ← Entry point — run this
│   ├── Checks prerequisites
│   ├── Pre-caches large installers to SharedFolder/
│   ├── Generates sandbox-config.wsb dynamically
│   └── Launches Windows Sandbox
│
└── SharedFolder/ (read-only inside sandbox)
    ├── sandbox-bootstrap.ps1     ← Runs automatically at sandbox logon
    ├── Installers/               ← Pre-downloaded .exe / .msi files
    └── Extensions/               ← Unpacked browser extensions
         └── page-assist/

Windows Sandbox (ephemeral, isolated)
│
└── sandbox-bootstrap.ps1 runs as LogonCommand
    ├── Installs tools in dependency order
    ├── Logs all results to C:\sandbox-install.log
    └── Shows Windows Toast notification on completion
```

---

## Prerequisites

### Windows Feature: Windows Sandbox

Windows Sandbox must be enabled before running the script. The launcher script checks for this automatically and offers to enable it. To enable manually:

**Option A — PowerShell (run as Administrator):**
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All
```

**Option B — Windows Features GUI:**
1. Press `Win + R`, type `optionalfeatures.exe`, press Enter
2. Scroll to **Windows Sandbox**
3. Check the box → OK → Restart when prompted

**Option C — DISM (run as Administrator):**
```cmd
dism /online /Enable-Feature /FeatureName:Containers-DisposableClientVM /All /NoRestart
```

> ⚠️ A **reboot is required** after enabling Windows Sandbox for the first time.

### Windows Edition

Windows Sandbox is only available on:

| Edition | Supported |
|---|---|
| Windows 11 Pro | ✅ |
| Windows 11 Enterprise | ✅ |
| Windows 11 Education | ✅ |
| Windows 11 Home | ❌ (not supported) |
| Windows 10 Pro / Enterprise (1903+) | ✅ |
| Windows 10 Home | ❌ (not supported) |

### PowerShell Version

- PowerShell **5.1 or higher** (built into Windows 10/11)
- No external modules required
- Script must be run as **Administrator**

### Internet Access

The host machine requires internet access at launch time to download installers. Estimated total download size: **~8–15 GB** depending on tools selected (VS, ADK, and SDK are the largest).

---

## Hardware Requirements

### Minimum (basic AI tooling, no GPU inference)

| Component | Minimum |
|---|---|
| **CPU** | 4-core 64-bit processor with virtualisation support (Intel VT-x / AMD-V) |
| **RAM** | 16 GB (8 GB allocated to sandbox + 8 GB for host) |
| **Disk (free)** | 40 GB free on the system drive |
| **GPU** | Optional — integrated graphics |
| **OS** | Windows 11 Pro / Enterprise / Education, **24H2 (Build 26100) or 25H2 (Build 26200)**, x64 |
| **Architecture** | x64 (64-bit) only — ARM64 and x86 are not supported |
| **BIOS** | Virtualisation enabled (VT-x or AMD-V) |
| **Hyper-V** | Must be supported and not blocked by host hypervisor |

### Recommended (AI inference + full IDE tooling)

| Component | Recommended |
|---|---|
| **CPU** | 8-core modern processor (Intel Core i7/i9 12th gen+, AMD Ryzen 7/9 5000+) |
| **RAM** | 32 GB (16 GB allocated to sandbox) |
| **Disk (free)** | 80 GB free (SSD strongly preferred) |
| **GPU** | NVIDIA RTX 3060+ or AMD RX 6700+ with 8 GB+ VRAM (for Ollama/LM Studio GPU inference) |
| **OS** | Windows 11 Pro / Enterprise 23H2+ |
| **Display** | 1080p minimum for full IDE layout |

### Assumptions

> The following assumptions are baked into the default script configuration. Override via flags if your environment differs.

- **Virtualisation is enabled** in BIOS/UEFI. If the sandbox fails to start, check BIOS settings for `Intel Virtualization Technology`, `VT-d`, or `AMD-V / SVM Mode`.
- **Hyper-V is not blocked** by a third-party hypervisor (e.g. VMware Workstation in legacy mode). If running inside a VM, ensure nested virtualisation is enabled on the host hypervisor.
- **Disk is SSD**. Installer extraction and sandbox provisioning will be very slow on spinning HDDs, especially for Visual Studio and Windows ADK/SDK.
- **No proxy / corporate firewall** blocks direct downloads from Microsoft, GitHub, and vendor CDNs. If behind a proxy, configure `$env:HTTP_PROXY` before running.
- **Windows is up to date**. The script targets **Windows 11 24H2 (Build 26100) or Windows 11 25H2 (Build 26200)**. Older builds (21H2, 22H2, 23H2) are not supported and the launcher will refuse to start. Update via Settings > Windows Update.
- **GPU drivers are up to date** if vGPU is expected for AI inference inside the sandbox.

---

## Software Installed

### 🤖 AI Runtimes & Agents

| Software | Source | Install Method |
|---|---|---|
| **Ollama** | https://ollama.com | Official installer, silent |
| **LM Studio** | https://lmstudio.ai | Official installer, silent |
| **OpenCode** | https://github.com/opencode-ai/opencode | GitHub latest release |
| **Crew AI** | https://github.com/crewaiinc/crewai | `pip install crewai` |
| **Nous Hermes 2 model** | Ollama registry | `ollama pull nous-hermes2` |
| **Microsoft Copilot** | https://copilot.microsoft.com | Chrome PWA install |

> **Note:** Hermes Agent (nousresearch/hermes-agent) does not have a published installable CLI binary. The script pulls the `nous-hermes2` model via Ollama as a functional equivalent. Update the script when an official CLI is released.

### 🌐 Browsers

| Software | Source | Notes |
|---|---|---|
| **Google Chrome** | Google CDN | Silent install |
| **Page Assist Extension** | https://github.com/n4ze3m/page-assist | Cloned and loaded as unpacked extension |
| **Brave Browser** | https://brave.com | Silent install |

### 🛠️ Developer Tools

| Software | Source | Notes |
|---|---|---|
| **Node.js + npm (LTS)** | https://nodejs.org | Silent MSI install |
| **Python 3.12** | https://python.org | Silent install, added to PATH |
| **7-Zip** | https://www.7-zip.org | Silent install |
| **Notepad++** | https://notepad-plus-plus.org | Silent `/S` install |
| **Beyond Compare 4** | https://www.scootersoftware.com | Silent install |
| **Git** | https://git-scm.com | Silent install |
| **Visual Studio Code** | https://visualstudio.microsoft.com | Silent install |
| **Visual Studio Community** | https://visualstudio.microsoft.com | Silent install with workloads |

> **Note:** Visual Studio Community installation is large (~5–20 GB depending on workloads selected). The default script installs with `.NET desktop`, `C++ desktop`, and `Node.js development` workloads. Adjust via config.

### 🔧 System & Productivity Tools

| Software | Source | Notes |
|---|---|---|
| **Windows PowerToys** | https://aka.ms/getPowertoys | WinGet or GitHub release |
| **Sysinternals Suite** | https://learn.microsoft.com/sysinternals | ZIP download + PATH |
| **Windows ADK (Assessment & Deployment Kit)** | https://go.microsoft.com/fwlink/?linkid=2289980 | Silent install |
| **Windows ADK WinPE Addon** | https://go.microsoft.com/fwlink/?linkid=2289981 | Silent install |
| **Windows SDK** | https://developer.microsoft.com/windows/downloads/windows-sdk | Silent install |
| **Windows Performance Toolkit** | Included with ADK | Subset install |

---

## Repository Structure

```
windows-ai-sandbox/
├── README.md                        ← You are here
├── USER_GUIDE.md                    ← End-user setup guide
├── PROMPT.md                        ← GPT prompt to regenerate/extend the scripts
├── CHANGELOG.md                     ← Version history
│
├── Launch-AISandbox.ps1             ← Host-side launcher (run this)
├── sandbox-config.wsb               ← Windows Sandbox config (auto-generated)
│
├── scripts/
│   ├── sandbox-bootstrap.ps1        ← Runs inside sandbox at logon
│   ├── install-browsers.ps1         ← Browser installation module
│   ├── install-ai-tools.ps1         ← AI runtime installation module
│   ├── install-dev-tools.ps1        ← Developer tools module
│   ├── install-system-tools.ps1     ← System utilities module
│   └── utils.ps1                    ← Shared helpers (logging, download, verify)
│
├── config/
│   └── tools.json                   ← Central tool registry (versions, URLs, flags)
│
├── extensions/
│   └── page-assist/                 ← Page Assist Chrome extension (cloned)
│
└── docs/
    ├── architecture.md
    ├── troubleshooting.md
    └── adding-new-tools.md
```

---

## Quick Start

### 1. Clone the repository

```powershell
git clone https://github.com/YOUR_USERNAME/windows-ai-sandbox.git
cd windows-ai-sandbox
```

### 2. Open PowerShell as Administrator

Right-click the Start menu → **Windows Terminal (Admin)** or **PowerShell (Admin)**.

### 3. Allow script execution (if not already set)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### 4. Launch the sandbox

```powershell
# Full install (all tools)
.\Launch-AISandbox.ps1

# Skip specific tools
.\Launch-AISandbox.ps1 -SkipVSCommunity -SkipADK -SkipSDK

# Verbose output + pre-cache installers only (no sandbox launch)
.\Launch-AISandbox.ps1 -PreCacheOnly -Verbose
```

The script will:
1. Verify Windows Sandbox is enabled (offer to enable if not)
2. Download all installers to a temp shared folder
3. Generate the `.wsb` configuration file
4. Launch the sandbox — provisioning begins automatically

> ⏱️ **First run time:** 15–60 minutes depending on internet speed and which tools are selected. Visual Studio and ADK are the longest.

---

## Script Reference

### `Launch-AISandbox.ps1` Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-SkipOllama` | Switch | false | Skip Ollama AI runtime |
| `-SkipLMStudio` | Switch | false | Skip LM Studio |
| `-SkipOpenCode` | Switch | false | Skip OpenCode CLI |
| `-SkipCrewAI` | Switch | false | Skip Crew AI (pip) |
| `-SkipChrome` | Switch | false | Skip Google Chrome |
| `-SkipPageAssist` | Switch | false | Skip Page Assist extension |
| `-SkipBrave` | Switch | false | Skip Brave Browser |
| `-SkipNotepadPP` | Switch | false | Skip Notepad++ |
| `-SkipBeyondCompare` | Switch | false | Skip Beyond Compare |
| `-SkipNpm` | Switch | false | Skip Node.js / npm |
| `-SkipPython` | Switch | false | Skip Python |
| `-SkipGit` | Switch | false | Skip Git |
| `-SkipVSCode` | Switch | false | Skip Visual Studio Code |
| `-SkipVSCommunity` | Switch | false | Skip Visual Studio Community |
| `-SkipPowerToys` | Switch | false | Skip Windows PowerToys |
| `-SkipSysinternals` | Switch | false | Skip Sysinternals Suite |
| `-SkipADK` | Switch | false | Skip Windows ADK |
| `-SkipSDK` | Switch | false | Skip Windows SDK |
| `-Skip7Zip` | Switch | false | Skip 7-Zip |
| `-SkipCopilot` | Switch | false | Skip Microsoft Copilot PWA |
| `-SandboxMemoryMB` | Int | 16384 | Sandbox RAM allocation in MB |
| `-PreCacheOnly` | Switch | false | Download installers but do not launch sandbox |
| `-Verbose` | Switch | false | Detailed console output |
| `-CleanCache` | Switch | false | Delete pre-cached installers after sandbox closes |

### Example Invocations

```powershell
# Minimal AI-only sandbox (fast, ~2 GB download)
.\Launch-AISandbox.ps1 -SkipVSCommunity -SkipADK -SkipSDK -SkipSysinternals

# Pre-cache everything over lunch, then launch later
.\Launch-AISandbox.ps1 -PreCacheOnly
.\Launch-AISandbox.ps1  # Uses cached files, skips re-download

# Max memory for heavy AI workloads
.\Launch-AISandbox.ps1 -SandboxMemoryMB 24576

# Browser + AI tools only, no dev IDE
.\Launch-AISandbox.ps1 -SkipVSCode -SkipVSCommunity -SkipADK -SkipSDK

# Clean up cache when done
.\Launch-AISandbox.ps1 -CleanCache
```

---

## Configuration

### `config/tools.json`

Central registry for all tool metadata. Edit here to change download URLs, installer flags, or disable tools globally without touching the scripts.

```json
{
  "tools": {
    "ollama": {
      "enabled": true,
      "url": "https://ollama.com/download/OllamaSetup.exe",
      "args": "/S",
      "verify": "ollama --version"
    },
    "chrome": {
      "enabled": true,
      "url": "https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe",
      "args": "/silent /install",
      "verify": "chrome.exe --version"
    }
  }
}
```

### Sandbox Memory

Default: **16384 MB (16 GB)**. Minimum recommended: **8192 MB**. Adjust with `-SandboxMemoryMB`:

```powershell
.\Launch-AISandbox.ps1 -SandboxMemoryMB 32768
```

### vGPU

vGPU is enabled by default in the generated `.wsb` file. To disable (e.g. in VM environments):

Edit `sandbox-config.wsb` before launch, or set `$EnableVGPU = $false` at the top of `Launch-AISandbox.ps1`.

---

## Troubleshooting

### Sandbox fails to start

**Error: `The virtual machine could not be started because a required feature is not installed`**
```powershell
# Enable required Windows features
Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All
Enable-WindowsOptionalFeature -Online -FeatureName "VirtualMachinePlatform" -All
# Reboot required
```

**Error: `Hypervisor is not running`**
- Enable Intel VT-x / AMD-V in BIOS
- If running inside VMware: enable nested virtualisation for the VM
- If running inside Hyper-V: enable nested virtualisation on the parent partition

### Install fails inside sandbox

Check `C:\sandbox-install.log` inside the sandbox for per-tool errors. The bootstrap script logs every step.

```powershell
# View the log inside sandbox
Get-Content C:\sandbox-install.log
```

### Chrome extension not loading (Page Assist)

The Page Assist extension requires Chrome to be launched with `--load-extension`. If Chrome opens without it:
1. Check that `extensions\page-assist\` was correctly populated (git clone ran)
2. Verify the Chrome shortcut in the sandbox was created by the bootstrap script

### Visual Studio install timeout

VS Community can take 30–90 minutes. Increase the bootstrap script's install timeout:

```powershell
# In sandbox-bootstrap.ps1, find the VS install block and increase -Timeout
Wait-Process -Name "vs_installer" -Timeout 7200
```

### Beyond Compare — trial mode

Beyond Compare installs in trial mode. A licence key can be injected via registry at install time:

```powershell
# Add to sandbox-bootstrap.ps1 after BC install
reg add "HKCU\Software\Scooter Software\Beyond Compare 4" /v LicenseKey /t REG_SZ /d "YOUR-KEY-HERE" /f
```

---

## Known Limitations & Placeholders

| Item | Status | Notes |
|---|---|---|
| **Antigravity 2.0 / IDE / CLI** | ⚠️ Placeholder | `antigravity.google/download` is not a real product. Script checks at runtime and skips gracefully if unreachable. |
| **Hermes Agent CLI** | ⚠️ Placeholder | No public installable CLI exists. Script installs `nous-hermes2` via Ollama. Update when official release available. |
| **Microsoft Copilot** | ℹ️ Limited | Installed as Chrome PWA pointing to `copilot.microsoft.com`. Full functionality requires Microsoft account sign-in inside sandbox. |
| **VS Community workloads** | ℹ️ Configurable | Default installs .NET, C++, and Node.js workloads. Edit `scripts/install-dev-tools.ps1` to add/remove. |
| **Beyond Compare licence** | ℹ️ Trial | Installs as 30-day trial. Inject licence key via registry if needed. |
| **GPU inference inside sandbox** | ℹ️ Limited | vGPU passthrough works for display but CUDA/ROCm inside sandbox is hardware- and driver-dependent. Not guaranteed. |

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/add-my-tool`
3. Follow the pattern in `scripts/install-dev-tools.ps1` to add new tools
4. Register the tool in `config/tools.json`
5. Add the tool to the skip flags in `Launch-AISandbox.ps1`
6. Submit a pull request with a clear description

See `docs/adding-new-tools.md` for a step-by-step guide.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

> **Disclaimer:** This project downloads and installs third-party software. Each application is subject to its own licence terms. Review licences for Beyond Compare, Visual Studio, Windows ADK, and Windows SDK before use in commercial or production contexts.
