# 📖 User Guide — Windows AI Sandbox

> **Audience:** End users who want to launch the AI Sandbox on their Windows 11 machine. No prior PowerShell or DevOps knowledge required.

---

## What Is This?

The Windows AI Sandbox is a **safe, temporary computing environment** that runs inside your real Windows PC without affecting it. Think of it as a self-contained bubble where AI tools, browsers, and developer utilities are automatically installed for you.

When you close the sandbox window, **everything inside it is deleted** — your main PC stays exactly as it was. No leftover files, no registry changes, no clutter.

### What you get inside the sandbox (automatically installed):

- **AI tools:** Ollama, LM Studio, OpenCode, Crew AI, Microsoft Copilot
- **Browsers:** Google Chrome (with Page Assist AI extension), Brave
- **Dev tools:** VS Code, Visual Studio Community, Node.js, Python, Git, Notepad++
- **System utilities:** 7-Zip, Sysinternals, Windows ADK, Windows SDK, PowerToys
- **Productivity:** Beyond Compare, Notepad++

---

## Before You Begin — Checklist

Go through this checklist **before** running any scripts. Skipping steps here is the #1 cause of problems.

### ✅ 1. Confirm your Windows edition

Windows Sandbox **does not work** on Windows 11 Home edition.

To check your edition:
1. Press `Win + R`, type `winver`, press **Enter**
2. Look for the edition in the dialog

**Required editions:** Windows 11 Pro, Enterprise, or Education

---

### ✅ 2. Check your hardware

Open **Task Manager** (`Ctrl + Shift + Esc`) → **Performance** tab to verify:

| What to check | Where to find it | Minimum needed |
|---|---|---|
| RAM | Memory section | **16 GB** total (32 GB recommended) |
| CPU cores | CPU section | **4 cores** (8 recommended) |
| Free disk space | (see step below) | **40 GB free** (80 GB recommended) |

**To check disk space:**
1. Open **File Explorer** (`Win + E`)
2. Click **This PC** in the left panel
3. Look at your C: drive — it should show at least **40 GB free**

---

### ✅ 3. Check BIOS virtualisation is enabled

> ⚠️ If you're not sure about this, try running the script first — it will tell you if this is the problem.

Virtualisation allows your PC to run the sandbox. Most modern PCs have it enabled by default.

**To verify:**
1. Open **Task Manager** (`Ctrl + Shift + Esc`)
2. Click the **Performance** tab
3. Click **CPU**
4. Look for **Virtualization: Enabled** in the bottom right

If it says **Disabled**, you need to enable it in your BIOS — see [Enabling Virtualisation in BIOS](#enabling-virtualisation-in-bios) below.

---

### ✅ 4. Ensure internet access

The script downloads all tools automatically. You need a **stable internet connection** with no content-filtering proxy that blocks GitHub, Microsoft, or vendor download servers.

Estimated download sizes:
| Scenario | Download size |
|---|---|
| AI tools + browsers only | ~2–4 GB |
| Full install (all tools) | ~10–20 GB |
| With Visual Studio Community | ~15–25 GB |

> 💡 Tip: Use the `-PreCacheOnly` flag to download everything in advance on a fast connection, then run the full launch later.

---

### ✅ 5. Enable Windows Sandbox Feature

**Method A — Using the script (easiest):**

The launcher script checks for this automatically. If Windows Sandbox isn't enabled, it will ask you:
```
Windows Sandbox is not enabled. Would you like to enable it now? [Y/N]:
```
Type `Y` and press Enter. Your PC will need to **restart** after this.

**Method B — Manual (via Windows Features):**

1. Press `Win + R`
2. Type `optionalfeatures.exe` and press **Enter**
3. Scroll down to find **Windows Sandbox**
4. Check the box next to it
5. Click **OK**
6. Click **Restart now** when prompted

---

## Step-by-Step: Launching the Sandbox

### Step 1 — Download the project

**Option A — Using Git (recommended):**
```powershell
git clone https://github.com/YOUR_USERNAME/windows-ai-sandbox.git
```

**Option B — Download ZIP:**
1. Go to the GitHub repository page
2. Click the green **Code** button
3. Click **Download ZIP**
4. Extract the ZIP to a folder (e.g. `C:\tools\windows-ai-sandbox`)

---

### Step 2 — Open PowerShell as Administrator

This is required — the script cannot run without administrator rights.

**Method A:**
1. Click the **Start menu**
2. Type `PowerShell`
3. Right-click **Windows PowerShell** in the results
4. Click **Run as administrator**
5. Click **Yes** on the User Account Control popup

**Method B:**
1. Press `Win + X`
2. Click **Windows Terminal (Admin)** or **PowerShell (Admin)**

You'll know it's running as administrator because the title bar says **Administrator**.

---

### Step 3 — Navigate to the project folder

In the PowerShell window, type:

```powershell
cd C:\path\to\windows-ai-sandbox
```

Replace `C:\path\to\` with wherever you saved/extracted the project. For example:
```powershell
cd C:\tools\windows-ai-sandbox
```

---

### Step 4 — Allow the script to run (first time only)

Windows blocks scripts by default for security. Run this once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

Type `Y` and press Enter when prompted.

---

### Step 5 — Run the launcher script

**Full install (everything):**
```powershell
.\Launch-AISandbox.ps1
```

**Faster install — skip the large IDE tools:**
```powershell
.\Launch-AISandbox.ps1 -SkipVSCommunity -SkipADK -SkipSDK
```

**AI tools and browsers only (quickest):**
```powershell
.\Launch-AISandbox.ps1 -SkipVSCommunity -SkipADK -SkipSDK -SkipSysinternals -SkipPowerToys
```

---

### Step 6 — Wait for provisioning to complete

After the sandbox window opens, you'll see a black command prompt window running inside it. This is the bootstrap script installing all the tools. 

**Do not close the sandbox window** while this is running.

A Windows notification will appear inside the sandbox when everything is installed:
> ✅ *AI Sandbox ready — all tools installed. See C:\sandbox-install.log for details.*

---

## What's Inside the Sandbox When Ready

After provisioning completes, you'll find:

| Tool | Where to find it |
|---|---|
| Google Chrome | Desktop shortcut + Taskbar |
| Brave Browser | Desktop shortcut |
| Page Assist (AI extension) | Chrome toolbar (puzzle piece icon → Page Assist) |
| Ollama | Running as a background service |
| LM Studio | Desktop shortcut |
| Visual Studio Code | Desktop shortcut + Start menu |
| Notepad++ | Start menu / Desktop |
| Beyond Compare | Start menu |
| PowerToys | System tray |
| Sysinternals | `C:\Tools\Sysinternals\` folder |
| Install log | `C:\sandbox-install.log` |

---

## Common Questions

### How long does it take?

| Scenario | Approximate time |
|---|---|
| AI tools + browsers only | 10–20 minutes |
| Full install (no VS Community) | 25–40 minutes |
| Full install with VS Community | 45–90 minutes |

Times depend heavily on your internet speed and PC performance.

---

### Can I save my work from inside the sandbox?

**By default, no.** Everything inside the sandbox is lost when you close it. This is by design — it keeps your PC clean.

To save files from the sandbox to your PC, you can:
- Use the clipboard (`Ctrl+C` / `Ctrl+V` works between sandbox and host)
- Enable a shared writable folder (advanced — see `docs/adding-shared-folder.md`)

---

### Can I run the sandbox again tomorrow?

Yes. Each time you run `Launch-AISandbox.ps1`, it creates a fresh sandbox. If you used `-PreCacheOnly` to download installers, subsequent launches reuse the cached files and are much faster (5–15 minutes instead of 30–90).

---

### Can I have two sandboxes running at once?

No. Windows only supports one Sandbox instance at a time.

---

### Will this affect my PC?

No. The sandbox is completely isolated. The only thing the launcher script does on your host PC is:
- Download installers to a temporary shared folder
- Create a `.wsb` configuration file
- Launch the sandbox process

Your installed programs, registry, and files are never touched.

---

### The sandbox window is black / frozen

1. Wait 2–3 minutes — it may be loading
2. If still frozen after 5 minutes, close the sandbox window and relaunch
3. If it happens repeatedly, try: `.\Launch-AISandbox.ps1 -SkipVSCommunity -SkipADK`

---

## Enabling Virtualisation in BIOS

> Only needed if Task Manager shows **Virtualization: Disabled**

This process varies by PC manufacturer. General steps:

1. **Restart your PC**
2. During startup, press the BIOS key repeatedly:
   - **Dell:** F2 or F12
   - **HP:** F10 or Esc
   - **Lenovo:** F1 or F2
   - **ASUS:** Del or F2
   - **MSI:** Del
3. Find the **Virtualisation** or **CPU Configuration** section
4. Enable **Intel Virtualization Technology (VT-x)** or **AMD SVM Mode**
5. Save and exit (usually F10)

If you're unsure, search Google for: `enable virtualization [your PC model] BIOS`

---

## Skip Flags Quick Reference

Add these to the command to skip specific tools and speed up the install:

```powershell
# Skip large tools (fastest useful install)
.\Launch-AISandbox.ps1 -SkipVSCommunity -SkipADK -SkipSDK

# Skip all IDEs
.\Launch-AISandbox.ps1 -SkipVSCode -SkipVSCommunity

# Skip all system tools
.\Launch-AISandbox.ps1 -SkipSysinternals -SkipADK -SkipSDK -SkipPowerToys

# Skip all browsers
.\Launch-AISandbox.ps1 -SkipChrome -SkipBrave -SkipPageAssist -SkipCopilot

# Skip AI tools
.\Launch-AISandbox.ps1 -SkipOllama -SkipLMStudio -SkipOpenCode -SkipCrewAI
```

---

## Getting Help

- Check `C:\sandbox-install.log` inside the sandbox for detailed install results
- See `docs/troubleshooting.md` for common error solutions
- Open an issue on GitHub with the contents of the install log

---

*Last updated: June 2026*
