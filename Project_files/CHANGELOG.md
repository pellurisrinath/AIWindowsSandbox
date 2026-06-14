# Changelog

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
