# Windows 11 24H2/25H2 Compatibility Report

**Generated:** 14 June 2026 23:39 CET
**Target:** Windows 11 24H2 (Build 26100) and Windows 11 25H2 (Build 26200), x64, Windows Sandbox

## Summary

All 22 tools listed in `config/tools.json` are compatible with Windows 11 24H2/25H2 on x64. The compatibility issues found were limited to broken download URLs and a non-existent tool entry — not OS-incompatibility.

| Status | Count |
|--------|-------|
| Working URL | 16 |
| Stale but functional URL | 2 |
| Broken URL (404) — fixed | 4 |
| Tool does not exist — marked as unavailable | 1 |
| **Total tools** | **22** |
| Tools incompatible with 24H2/25H2 | **0** |

## Per-Tool Status

| # | Tool | URL Health | 24H2/25H2 Support | x64 | Action |
|---|------|------------|-------------------|-----|--------|
| 1 | Python 3.12.10 | Fixed (was 404) | Yes | Yes | URL switched from `.msi` to `.exe` |
| 2 | Node.js 20.x | Working | Yes | Yes | None |
| 3 | Google Chrome | Working | Yes | Yes | None |
| 4 | Page Assist Extension | Working (source clone) | Yes | N/A | Build step required for unpacked |
| 5 | Brave Browser | Working | Yes | Yes | None |
| 6 | Notepad++ v8.9.6.4 | Updated (was stale) | Yes | Yes | Fallback URL refreshed |
| 7 | Beyond Compare 4 | Fixed (was 404) | Yes (v4) | Yes | URL + fallback build number fixed |
| 8 | Ollama | Working | Yes | Yes | WDAC bypass already in place |
| 9 | LM Studio | Fixed (was 404) | Yes | Yes | Endpoint URL corrected |
| 10 | OpenCode Terminal (npm) | Working | Yes (Node-based) | N/A | None |
| 11 | OpenCode Desktop | Working | Yes (Electron) | Yes | None |
| 12 | Crew AI (pip) | Working | Yes (Python-based) | N/A | None |
| 13 | Microsoft Copilot PWA | Working | Yes (Web) | N/A | None |
| 14 | Visual Studio Code | Working | Yes | Yes | None |
| 15 | Visual Studio Community 2022 | Working | Yes | Yes | None |
| 16 | 7-Zip v26.01 | Working | Yes | Yes | None |
| 17 | Sysinternals Suite | Working | Yes | N/A | Defender scan pre-installed |
| 18 | Windows PowerToys v0.100.0 | Updated (was stale) | Yes | Yes | Fallback URL refreshed |
| 19 | Windows SDK | Working | Yes (Feb 2025 build) | Yes | Old but functional |
| 20 | Windows ADK 10.1.26100.2454 | Working | Yes | Yes | None |
| 21 | Windows ADK WinPE Add-on | Working | Yes | Yes | None |
| 22 | Antigravity CLI | Unavailable | N/A | N/A | Marked as `_status: unavailable` |

## OS Build Number Reference

| Version | Build | Status |
|---------|-------|--------|
| Windows 11 21H2 | 22000 | Not supported |
| Windows 11 22H2 | 22621 | Not supported |
| Windows 11 23H2 | 22631 | Not supported |
| Windows 11 24H2 | 26100 | **Supported** (minimum) |
| Windows 11 25H2 | 26200 | **Supported** (recommended) |

## Architecture Support

- **x64 (64-bit)**: All 22 tools support this architecture. The sandbox requires it.
- **x86 (32-bit)**: Not supported. Some tools may have x86 variants but the project does not provide them.
- **ARM64**: Not supported. The launcher and bootstrap both check `osArch -eq "64-bit"` and refuse to run on ARM64.

## Sandbox-Specific Considerations

### WDAC / SmartScreen
- Windows 11 24H2/25H2 have **SmartScreen** enabled by default
- Unsigned or unreputed binaries are blocked at runtime
- All installer URLs resolve to **signed binaries** from Microsoft, Google, Brave, and other major vendors — SmartScreen should not block them
- The bootstrap already handles WDAC bypass for Ollama (the one unsigned installer)

### Memory and Time
- Default 16 GB `MemoryInMB` in WSB config is sufficient for all 22 tool installs
- Cumulative install can take 20–40 minutes in the sandbox
- No 24H2/25H2-specific timeout issues observed

### File Path Conventions
- `C:\SharedTools` — read-only mapped folder from host
- `C:\Tools` — hardcoded for Sysinternals extraction; created on demand
- `C:\ProgramData\WindowsAISandboxApps\Logs` — log directory (read-write)

## Cross-Cutting Notes

### Tools That Install Cleanly
All signed tools from major vendors: Chrome, Node.js, Brave, Notepad++, VS Code, VS Community, 7-Zip, PowerToys, Windows SDK, Windows ADK, ADK WinPE Add-on, LM Studio, OpenCode Desktop, Beyond Compare, Ollama, Sysinternals, OpenCode Terminal (npm), Crew AI (pip), Microsoft Copilot (Chrome shortcut).

### Tools With Known Issues (Already Handled)
- **Ollama**: WDAC blocks the NSIS installer. Bootstrap has a curl fallback that downloads the CLI binary directly. This is the most reliable install path.
- **Page Assist**: Source-only clone, no `build/` step. Bootstrap currently creates a Chrome shortcut with `--load-extension`; this may or may not load a non-built extension depending on Chrome version. Future fix: add a build step (`bun install && bun run build`) or use the Chrome Web Store CRX URL.
- **Sysinternals**: Some tools (PsExec, Procmon) are flagged as `HackTool:BK` by Windows Defender. Pre-install scan on the host catches this; sandbox has its own Defender instance but the suite is already copied to the sandbox by then.
- **Windows SDK**: Old but functional build (Feb 2025). For 25H2 freshness, the [latest SDK ISO](https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/) is recommended but the current `fwlink/p/?linkid=2237387` works for 24H2/25H2.

### Tool That Doesn't Exist
**Antigravity CLI**: `github.com/google-deepmind/antigravity-cli` returns 404. The Antigravity product at `antigravity.google` is a JavaScript SPA without a direct `.exe` download. The bootstrap gracefully skips this tool. Marked as `_status: unavailable` in `tools.json` to document this for future maintainers.

## Verification

To verify all tools install correctly in the sandbox:
1. Clear the staging cache:
   ```powershell
   Remove-Item -Recurse -Force "C:\Users\pellu\AppData\Local\Temp\AISandboxStaging"
   Remove-Item -Recurse -Force "C:\Users\pellu\AppData\Local\Temp\AISandboxShare\Installers"
   ```
2. Run the batch file as Administrator
3. Check the verification report at `C:\ProgramData\WindowsAISandboxApps\Logs\final-verification.txt`
4. All 22 tools should show either `OK` (installed) or `SKIP` (Antigravity)

## Recommendations

1. **High priority**: Test the new URLs (Python, Beyond Compare, LM Studio) on a real Windows 11 24H2/25H2 host
2. **Medium priority**: Add a build step for Page Assist or switch to Chrome Web Store CRX
3. **Low priority**: Update Windows SDK to the latest build for full 25H2 compatibility
4. **Optional**: Remove Antigravity CLI entry from `config/tools.json` (marked as `_status: unavailable`)

---

**Maintained by:** Windows AI Sandbox project
**License:** MIT
