# 🔧 Troubleshooting Guide

## Sandbox Won't Start

### Error: Feature not enabled
```
The virtual machine or container could not be started because a required feature is not installed.
```
**Fix:**
```powershell
Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All
# Reboot required
```

### Error: Hypervisor not running
```
Hyper-V encountered a fatal error
```
**Fixes:**
1. Enable VT-x or AMD-V in BIOS
2. If inside VMware: VM Settings → Processors → Enable `Virtualise Intel VT-x/EPT or AMD-V/RVI`
3. If inside Hyper-V: Run on parent partition: `Set-VMProcessor -VMName YourVM -ExposeVirtualizationExtensions $true`

### Sandbox window is black on launch
- Wait up to 5 minutes on first boot — Windows Sandbox takes time to initialise
- Check that vGPU is supported on your GPU driver version
- Try disabling vGPU: edit the `.wsb` file, change `<vGPU>Enable</vGPU>` to `<vGPU>Disable</vGPU>`

---

## Install Failures Inside Sandbox

### Check the log first
```powershell
Get-Content C:\sandbox-install.log | Select-String -Pattern "\[ERROR\]|\[WARN\]"
```

### Visual Studio Community hangs
VS Community can appear frozen for 20–40 minutes. Check CPU/disk activity in Task Manager inside the sandbox before force-closing.

**If it genuinely hangs:**
```powershell
# Kill and retry with fewer workloads — inside sandbox
Stop-Process -Name "vs_installer" -Force
Start-Process "C:\SharedTools\Installers\vs_community.exe" -ArgumentList "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.ManagedDesktop"
```

### Python / pip tools fail
```
ERROR: Could not install packages due to an OSError
```
**Fix:** Python may not be in PATH yet.
```powershell
$env:PATH += ";C:\Users\WDAGUtilityAccount\AppData\Local\Programs\Python\Python312"
$env:PATH += ";C:\Users\WDAGUtilityAccount\AppData\Local\Programs\Python\Python312\Scripts"
pip install crewai
```

### Chrome extension not appearing
Page Assist loads as an unpacked extension. If the puzzle piece icon doesn't show it:
1. Open Chrome → three-dot menu → **Extensions** → **Manage Extensions**
2. Enable **Developer mode** (top right toggle)
3. Click **Load unpacked**
4. Navigate to `C:\SharedTools\Extensions\page-assist\`

### ADK / SDK install fails with 0x80070005 (Access Denied)
Windows ADK requires the bootstrap script to run as Administrator. This should be the case by default but verify:
```powershell
# Inside sandbox PowerShell
[Security.Principal.WindowsIdentity]::GetCurrent().Groups -match "S-1-5-32-544"
# Should return True
```

---

## Network Issues

### Downloads timing out
```
Invoke-WebRequest : The operation has timed out
```
**Fix:** The default timeout is 300 seconds. For large files (VS, ADK), use `-PreCacheOnly` to download on the host before launching:
```powershell
.\Launch-AISandbox.ps1 -PreCacheOnly
```
Then launch normally — the cached files are used and no re-download occurs.

### Corporate proxy blocking downloads
```powershell
# Set proxy before running the launcher
$env:HTTP_PROXY  = "http://proxy.company.com:8080"
$env:HTTPS_PROXY = "http://proxy.company.com:8080"
.\Launch-AISandbox.ps1
```

---

## Performance Issues

### Sandbox is very slow
- Ensure at least **16 GB RAM** is allocated: `.\Launch-AISandbox.ps1 -SandboxMemoryMB 16384`
- Close other applications on the host before launching
- If on HDD: move the AISandboxShare folder to an SSD path

### Ollama/LM Studio GPU not available inside sandbox
GPU passthrough inside Windows Sandbox is limited to display rendering (vGPU). CUDA and ROCm are generally **not available inside the sandbox**. AI inference will run on CPU only. This is a Windows Sandbox platform limitation, not a script issue.

---

## Common Exit Codes

| Exit Code | Meaning | Action |
|---|---|---|
| 0 | Success | None needed |
| 1 | General error | Check install log |
| 1603 | MSI install failed | Check for conflicting processes; relaunch sandbox |
| 1602 | User cancelled | Should not happen in silent mode — check args |
| 3010 | Reboot required | Cannot reboot inside sandbox — tool may still work |
| 5 | Access denied | Bootstrap not running as admin |
