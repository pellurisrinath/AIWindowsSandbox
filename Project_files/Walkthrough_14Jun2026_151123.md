# Walkthrough: Bugfixes for HttpClient Assembly Missing & GitHub API Rate Limit

This walkthrough documents the bugfixes applied to address the execution failures reported.

## Fixes Implemented

### 1. Replaced System.Net.Http.HttpClient with System.Net.HttpWebRequest
- **Problem**: PowerShell 5.1 runs on .NET Framework, which does not load `System.Net.Http.dll` by default. This led to a `Cannot find type [System.Net.Http.HttpClient]` error when executing downloads.
- **Solution**: Rewrote the progress-aware downloader (`Download-FileWithProgress` in `Launch-AISandbox.ps1`) to utilize `[System.Net.HttpWebRequest]` instead. This class is part of `System.dll` and is natively loaded by default in all Windows PowerShell environments, restoring robust, dependency-free progress downloads.

### 2. GitHub API Rate Limit Fallback
- **Problem**: Querying `https://api.github.com/` for Notepad++ and OpenCode versions resulted in a `Failed to query GitHub API: {"message":"API rate limit exceeded...` error.
- **Solution**:
  - Registered direct release installer links under a `"fallbackUrl"` key in `config/tools.json`.
  - Updated `Launch-AISandbox.ps1` resolver logic to detect when the API call fails or yields no URL and fall back gracefully to downloading from the direct `fallbackUrl` (e.g., direct download links for Notepad++ v8.6.8 and OpenCode v0.0.1).
