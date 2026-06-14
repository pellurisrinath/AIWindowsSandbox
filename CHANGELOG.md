# Changelog

## [2026.06.14.16.40] — 2026-06-14

### Fixed
- GUI form size increased to accommodate all 22 tools (760x780)
- Tools GroupBox height increased to 360px to show all tool checkboxes
- Moved Settings, Launch button, Progress bar, Checklist, and Logs sections down to fit

### Changed
- Updated param block with new skip flags: `-SkipOpenCodeTerminal`, `-SkipOpenCodeDesktop`, `-SkipVSCode`, `-SkipVSCommunity`, `-Skip7Zip`, `-SkipSysinternals`, `-SkipPowerToys`, `-SkipWindowsSDK`, `-SkipADK`, `-SkipADKWinPE`, `-SkipAntigravity`
- Updated launch button click handler to handle all new tools dynamically from tools.json
- Checklist now includes all selected tools with correct display names

---

## [2026.06.14.16.28] — 2026-06-14

### Added
- **Visual Studio Code** — Silent install with context menu and PATH integration
- **Visual Studio Community** — Full IDE with .NET, C++, and Node.js workloads
- **7-Zip** — File archiver with silent install
- **Sysinternals Suite** — ZIP extraction to `C:\Tools\Sysinternals` with PATH
- **Windows PowerToys** — Utility suite for Windows
- **Windows SDK** — Development tools for Windows apps
- **Windows ADK** — Assessment and Deployment Kit
- **Windows ADK WinPE Add-on** — WinPE add-on for ADK
- **OpenCode Terminal** — CLI installer (renamed from "OpenCode")
- **OpenCode Desktop** — Desktop GUI installer
- **Gemma4 Model** — Auto-pulled after Ollama installation
- **Antigravity CLI** — Attempted download/install (if available)

### Changed
- Updated installation order to include all new tools
- Ollama now pulls both Gemma4 AND nous-hermes2 models
- Removed placeholder checks (Antigravity 2.0, Hermes Agent CLI)

### Full installation order
1. Node.js + npm
2. Python
3. Google Chrome
4. Page Assist Extension
5. Brave Browser
6. Notepad++
7. Beyond Compare 4
8. Ollama → Gemma4 → nous-hermes2
9. LM Studio
10. OpenCode Terminal
11. OpenCode Desktop
12. Crew AI
13. Microsoft Copilot PWA
14. Visual Studio Code
15. Visual Studio Community
16. 7-Zip
17. Sysinternals Suite
18. Windows PowerToys
19. Windows SDK
20. Windows ADK
21. Windows ADK WinPE Add-on
22. Antigravity CLI (if available)

---

## [1.1.0] — 2026-06-14

### Added
- Windows Defender pre-install security scans (`Start-MpScan`) on all downloaded installers before copying to sandbox
- SHA-256 checksum verification for installer integrity
- Updated OpenCode download link to official source: `https://opencode.ai/download`
- Fallback URLs in `config/tools.json` for GitHub API rate-limit resilience

### Changed
- Replaced `System.Net.Http.HttpClient` with `System.Net.HttpWebRequest` in `Launch-AISandbox.ps1` for PowerShell 5.1/.NET Framework compatibility
- GitHub API rate-limit now falls back gracefully to direct `fallbackUrl` entries

---

## [1.0.0] — Initial Release

### Added
- Core launcher script (`Launch-AISandbox.ps1`) with full skip-flag support
- Sandbox configuration generator (`.wsb` auto-generation)
- Bootstrap provisioning script (`sandbox-bootstrap.ps1`)
- Central tool registry (`config/tools.json`)

### Tools included
**AI Runtimes:** Ollama, LM Studio, OpenCode, Crew AI, Nous Hermes 2 (via Ollama)
**Browsers:** Google Chrome, Brave, Page Assist extension, Microsoft Copilot PWA
**Developer:** VS Code, Visual Studio Community, Node.js/npm, Python 3, Git
**Productivity:** Notepad++, Beyond Compare, 7-Zip, Windows PowerToys
**System:** Sysinternals Suite, Windows ADK + WinPE Addon, Windows SDK

### Known placeholders
- Antigravity 2.0 / IDE / CLI — source unverified; graceful skip
- Hermes Agent CLI — no public binary; substituted with nous-hermes2 via Ollama
