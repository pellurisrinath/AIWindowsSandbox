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
- Wait up to 5 minutes on first boot — Windows Sandbox takes time to initialise.
- Check that vGPU is supported on your GPU driver version.
- Try disabling vGPU: edit `sandbox-config.wsb`, change `<vGPU>Enable</vGPU>` to `<vGPU>Disable</vGPU>`

---

## Install Failures Inside Sandbox

### Check the log first
```powershell
Get-Content C:\sandbox-install.log | Select-String -Pattern "\[ERROR\]|\[WARN\]"
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
Page Assist loads as an unpacked extension. If the shortcut doesn't show it:
1. Open Chrome → three-dot menu → **Extensions** → **Manage Extensions**
2. Enable **Developer mode** (top right toggle)
3. Click **Load unpacked**
4. Navigate to `C:\SharedTools\Extensions\page-assist\`

---

## Network Issues

### Downloads timing out
```
Invoke-WebRequest : The operation has timed out
```
**Fix:** The default timeout is 300 seconds. Use `-PreCacheOnly` to download on the host before launching:
```powershell
.\Launch-AISandbox.ps1 -PreCacheOnly
```
Then launch normally — the cached files are used and no re-download occurs.

---

## Performance Issues

### Sandbox is very slow
- Ensure at least **16 GB RAM** is allocated: `.\Launch-AISandbox.ps1 -SandboxMemoryMB 16384`
- Close other applications on the host before launching.

### Ollama/LM Studio GPU not available inside sandbox
GPU passthrough inside Windows Sandbox is limited to display rendering (vGPU). CUDA and ROCm are generally **not available inside the sandbox**. AI inference will run on CPU only. This is a Windows Sandbox platform limitation, not a script issue.
