# 📖 User Guide — Windows AI Sandbox

> **Audience:** End users who want to launch the AI Sandbox on their Windows 11 machine. No prior PowerShell or DevOps knowledge required.

---

## What Is This?

The Windows AI Sandbox is a **safe, temporary computing environment** that runs inside your real Windows PC without affecting it. Think of it as a self-contained bubble where AI tools, browsers, and developer utilities are automatically installed for you.

When you close the sandbox window, **everything inside it is deleted** — your main PC stays exactly as it was. No leftover files, no registry changes, no clutter.

### What you get inside the sandbox (automatically installed):

- **AI tools:** Ollama, LM Studio, OpenCode, Crew AI, nous-hermes2, Microsoft Copilot PWA
- **Browsers:** Google Chrome (with Page Assist extension shortcut), Brave
- **Dev tools:** Node.js, Python 3, Notepad++
- **Productivity:** Beyond Compare 4

---

## Before You Begin — Checklist

Go through this checklist **before** running any scripts.

### 1. Confirm your Windows edition
Windows Sandbox **does not work** on Windows Home edition.
**Required editions:** Windows 10/11 Pro, Enterprise, or Education.

### 2. Check your hardware
- **Memory (RAM):** 16 GB minimum allocated (32 GB recommended on host).
- **Disk Space:** 30 GB minimum free disk space on drive C:.
- **Virtualisation:** Ensure CPU Virtualisation is enabled in the BIOS/UEFI.

### 3. Enable Windows Sandbox Feature
If not enabled, the host launcher script will ask you if you'd like to enable it automatically. A computer restart is required after enabling it.

---

## Step-by-Step: Launching the Sandbox

### Step 1 — Navigate to the project folder
Open PowerShell as Administrator and navigate to the project directory:
```powershell
cd C:\Users\pellu\OneDrive\Documents\AntiGravity_AIWindowsSandbox
```

### Step 2 — Run the launcher script
Run the launcher with your desired tools:

**Full install (everything):**
```powershell
.\Launch-AISandbox.ps1
```

**Minimal install (faster startup, skipping LM Studio and Brave):**
```powershell
.\Launch-AISandbox.ps1 -SkipLMStudio -SkipBrave
```

**Pre-cache installers only (do not launch sandbox immediately):**
```powershell
.\Launch-AISandbox.ps1 -PreCacheOnly
```

### Step 3 — Monitor logs inside the sandbox
Once the sandbox starts, a command window will automatically perform the installations.
You can view detailed logs at:
`C:\sandbox-install.log`

---

## Skip Flags Quick Reference

Add these switches to `Launch-AISandbox.ps1` to skip installation of specific tools:

- `-SkipOllama` (Skip Ollama)
- `-SkipLMStudio` (Skip LM Studio)
- `-SkipOpenCode` (Skip OpenCode)
- `-SkipChrome` (Skip Google Chrome)
- `-SkipBrave` (Skip Brave Browser)
- `-SkipNotepadPP` (Skip Notepad++)
- `-SkipBeyondCompare` (Skip Beyond Compare 4)
- `-SkipNpm` (Skip Node.js / npm)
- `-SkipCrewAI` (Skip Crew AI)
- `-SkipCopilot` (Skip Copilot PWA)
- `-SkipPageAssist` (Skip Page Assist)

Example:
```powershell
.\Launch-AISandbox.ps1 -SkipBrave -SkipBeyondCompare -SkipLMStudio
```

---

## Troubleshooting & Help

- If a download fails, make sure your internet connection is active and stable.
- If the sandbox window closes unexpectedly, search `C:\sandbox-install.log` inside the sandbox or the console output on the host.
- Refer to `docs/adding-new-tools.md` to see how to register new tools in `config/tools.json`.
