# pwxe — Changelog

All notable changes to the `pwxe` (PwX Build Engine & CLI) project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)  
Versioning: Semantic Versioning  
Project: pwxe — Standalone PowerShell to EXE Build Engine

---

## [1.0.0] — 2026-10-16

### Initial Release
- **Pure Standalone Engine:** Decoupled from PwX Studio to serve as an independent CLI tool and PowerShell module.
- **PowerShell Gallery Ready:** Structured with `pwxe.psd1` manifest and `pwxe.psm1` root module for seamless `Install-Module pwxe` distribution.
- **Dual Target Runtimes:**
  - **PowerShell 5.1:** Built with Windows built-in `csc.exe` compiler; zero external SDK dependencies, ultra-lightweight (~500 KB) output.
  - **PowerShell 7.4+:** Built using modern `.NET 8 SDK` and `Microsoft.PowerShell.SDK`.
  - **Single-File Bundling:** Support for packaging all PS7 runtime dependencies into a single, standalone executable.
- **Commands & Aliases:**
  - `Invoke-Pwxe` (primary cmdlet)
  - `Test-PwxeEnvironment` (environment verification)
  - `pwxe` (CLI shortcut alias)
  - `New-PwxeExecutable` (standard verb alias)
- **Automated Testing & CI:** Complete smoke test suite (`tests/Run-Smoke.ps1`) and GitHub Actions Windows CI pipeline.
- **Icon & Metadata Management:** PE header icon embedding and WinForms runtime window icon injection.