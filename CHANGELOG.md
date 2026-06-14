# Changelog

## [2026.06.14.16.11] — 2026-06-14

### Added
- Version-aware installer caching: skip re-downloading if latest version is already present
- `Test-InstallerAlreadyCached` helper function with hash-based verification
- Fallback file size check for tools without SHA-256 hashes
- Cache check now prioritizes final `$installerPath` over staging folder

### Changed
- All download blocks (`direct`, `nodejs`, `github`, `scootersoftware`) now check final installer path first
- Improved logging for cache hits/misses with file size information

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
