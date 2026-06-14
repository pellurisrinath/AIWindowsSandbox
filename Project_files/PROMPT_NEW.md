# PROMPT.md — Windows AI Sandbox Generator

> This file is the single source of truth. The launcher, bootstrap script, and
> `tools.json` are all generated **from this prompt**. Keep it in sync with
> `CHANGELOG.md` whenever requirements change.

---

## Model / Execution Instructions (read first)

- **Use the locally installed Ollama instance for all programming/code-generation
  tasks.** Endpoint: `http://100.90.169.70:11434`
  - Point any code-assist tooling (OpenCode, CrewAI, agents, IDE integrations) at
    this base URL rather than a hosted API.
  - Example env wiring inside generated scripts:
    `OLLAMA_HOST=http://100.90.169.70:11434` and
    `OPENAI_BASE_URL=http://100.90.169.70:11434/v1` (for OpenAI-compatible clients).
- **Minimize token usage.** Prefer concise output: no restating the prompt back,
  no verbose preamble, no duplicated boilerplate across the three scripts. Emit
  only the requested deliverables and tight inline comments. Reuse shared helper
  functions instead of repeating logic.

---

## Task
Write a complete, production-quality PowerShell solution that:
1. Launches a Windows Sandbox instance
2. Automatically installs and configures ALL of the following tools inside the sandbox

## Software to Install

### AI Runtimes & Backends
- **Ollama** — https://ollama.com (latest release, silent install)
- **LM Studio** — https://lmstudio.ai (latest release, silent install)
- **OpenCode** — https://github.com/opencode-ai/opencode (latest GitHub release)

### Browsers
- **Google Chrome** — fetch latest from https://dl.google.com/chrome/install/ChromeStandaloneSetup64.exe
  - After install, auto-deploy the **Page Assist** Chrome Extension
    from https://github.com/n4ze3m/page-assist (pack as .crx or use
    Chrome's `--load-extension` flag pointing to a cloned/unpacked build)
- **Brave Browser** — fetch latest from https://brave.com/download

### Developer Tools
- **Node.js + npm** — fetch LTS installer from https://nodejs.org/en/download (silent)
- **Notepad++** — fetch latest from https://notepad-plus-plus.org/downloads (silent `/S`)
- **Beyond Compare 4** (Scooter Software) — fetch from
    https://www.scootersoftware.com/download (silent `/silent` install flag)

### AI Agents & Frameworks
- **Crew AI** — install via pip after ensuring Python 3.10+ is present:
    `pip install crewai`; verify with `crewai --version`.
    Configure CrewAI's LLM to use the local Ollama endpoint above.
- **[PLACEHOLDER] Hermes Agent** — install `nous-hermes2` model via Ollama as a
    substitute until an official hermes-agent CLI is confirmed:
    `ollama pull nous-hermes2`
    (Flag in log if a real hermes-agent binary is found at `nousresearch/hermes-agent`)
- **[PLACEHOLDER] Antigravity 2.0 / IDE / CLI** — SOURCE UNVERIFIED.
    Script should check https://antigravity.google/download at runtime;
    if unreachable, log a warning and skip gracefully. Do not hard-fail.
- **[PLACEHOLDER] Microsoft Copilot** — Install the Copilot PWA silently
    via Chrome after Chrome is installed, using:
    `chrome.exe --app=https://copilot.microsoft.com --install-webapp`
    Log a note that full Copilot functionality requires an active Microsoft account.

## Sandbox Configuration (.wsb)
- Networking: Enabled
- vGPU: Enabled (required for LM Studio / Ollama GPU inference)
- Memory: minimum 16384 MB (AI workloads are memory-heavy)
- Shared host folder (ReadOnly) for transferring bootstrap scripts and pre-cached installers
- LogonCommand: runs `sandbox-bootstrap.ps1` automatically at startup

> Note: The local Ollama endpoint `http://100.90.169.70:11434` must be reachable
> from inside the sandbox. Because Networking is Enabled, ensure the host route to
> `100.90.169.70` (e.g. Tailscale/LAN) is up before launch, and log a clear warning
> in the bootstrap if the endpoint does not respond.

## Bootstrap Script Behavior (inside sandbox)
- Install all tools in dependency order:
    1. Node.js + npm
    2. Python (if not present, for crewai/pip tools)
    3. Chrome → then Page Assist extension
    4. Brave
    5. Notepad++
    6. Beyond Compare
    7. Ollama → pull `nous-hermes2` model
    8. LM Studio
    9. OpenCode (configured against local Ollama endpoint)
    10. Crew AI (pip, configured against local Ollama endpoint)
    11. Copilot PWA (Chrome app)
    12. Placeholder items with graceful skip + log
- Set `OLLAMA_HOST=http://100.90.169.70:11434` (and OpenAI-compatible base URL)
  for all code-assist tooling.
- Log all outcomes (success/skip/fail) to `C:\sandbox-install.log`
- Show a summary notification via Windows Toast when all installs complete

## Host-Side Launcher Script Behavior
- Check that Windows Sandbox feature is enabled; if not, offer to enable it via:
    `Enable-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM"`
- Accept optional skip flags:
    `-SkipOllama -SkipLMStudio -SkipOpenCode -SkipChrome -SkipBrave`
    `-SkipNotepadPP -SkipBeyondCompare -SkipNpm -SkipCrewAI`
    `-SkipCopilot -SkipPageAssist`
- Accept `-Verbose` for detailed console progress
- Pre-cache large installers to shared folder before launching sandbox
    to avoid redundant downloads inside the sandbox
- Clean up temp/shared folder after sandbox session ends

## Constraints
- PowerShell 5.1+ compatible — no external modules required
- No hardcoded version numbers — always resolve latest dynamically
    (GitHub Releases API, official download redirects, etc.)
- All installs must be silent (no UI popups, no reboot prompts)
- Fully disposable — sandbox closes clean with no host side effects
- Thorough but concise inline comments explaining every section

---

## Recommended Repository Layout

Generate the deliverables to match this structure so the repo is ready to commit:

```
windows-ai-sandbox/
├── README.md                   ← project overview, quick start, requirements
├── USER_GUIDE.md               ← full usage walkthrough (the "Usage Guide" output)
├── PROMPT.md                   ← this file: source of truth for generation
├── CHANGELOG.md                ← versioned record of prompt/script changes
├── Launch-AISandbox.ps1        ← generate from PROMPT.md (host-side launcher)
├── scripts/
│   └── sandbox-bootstrap.ps1   ← generate from PROMPT.md (in-sandbox logon script)
├── config/
│   └── tools.json              ← generate from PROMPT.md (tool registry: URLs,
│                                  install args, silent flags, skip-flag names)
└── docs/
    ├── troubleshooting.md       ← common failures (vGPU, Ollama route, silent flags)
    └── adding-new-tools.md      ← how to extend tools.json + bootstrap
```

### Mapping of outputs to files
- `config/tools.json` — externalize every installer (name, download/resolver URL,
  silent args, dependency order, matching `-Skip*` flag). The launcher and bootstrap
  read from this so adding a tool means editing JSON, not code.
- `sandbox-config.wsb` is generated at runtime by `Launch-AISandbox.ps1` into a temp
  path; it does not need to be committed (keep it out of the repo or in `.gitignore`).

## Output Format
Provide in order:
1. **Launch-AISandbox.ps1** — host-side launcher (writes the `.wsb`, pre-caches, cleans up)
2. **config/tools.json** — tool registry consumed by the launcher and bootstrap
3. **scripts/sandbox-bootstrap.ps1** — logon script that runs inside the sandbox
4. **USER_GUIDE.md** — example commands and how to extend with new apps (point readers
   to `docs/adding-new-tools.md`)

Start with **Launch-AISandbox.ps1**.
