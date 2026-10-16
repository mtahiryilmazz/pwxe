# pwxe — Changelog

All notable changes to the `pwxe` (PwX Build Engine & CLI) project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)  
Versioning: Semantic Versioning  
Project: pwxe — Standalone PowerShell to EXE Build Engine

---

## [1.0.1] — 2026-10-16

### Fixed
- **PS7 Built-in Module Resolution:** Resolved `Microsoft.PowerShell.Utility` command discovery failure when launching compiled PS7 binaries from Windows PowerShell or clean environments.
- **`PSModulePath` Sanitation:** Added automatic filtering in `PwX.BuildHost.PS7` to eliminate inherited Windows PowerShell 5.1 (Desktop edition) paths from polluting the child PowerShell 7 Core runtime.
- **Module Output Deployment:** Updated `PwX-Build.ps1` to ensure `Modules/` directory containing PowerShell Core manifests (`.psd1`) is automatically mirrored into the application output package.
- **Harness & CI Reliability:** Smoke tests now pass 100% across all runtimes (`PS51`, `PS7` console, `PS7` single-file, and `PS7-GUI`).
- **`Invoke-Pwxe -Target PS7`:** The module forwarded a non-existent `-Runtime` parameter to the engine (expected `-RuntimeMode`), so every PS7 build via the module failed. Removed unsupported `win-x86` from `-Architecture`.
- **Encoding:** Restored UTF-8 BOM on engine scripts so Turkish log output renders correctly under Windows PowerShell 5.1.

### Added
- **Module Tests:** New `tests/Test-Module.ps1` (manifest validity, version/CHANGELOG match, exported commands & aliases, end-to-end `Invoke-Pwxe` builds for PS51 and PS7).
- **CI Jobs:** GitHub Actions split into separate checks: module tests, PS7 GUI host logic, smoke tests (folder & single-file).
- **Roadmap:** Added comprehensive [ROADMAP.md](ROADMAP.md) detailing upcoming features, security signing, UAC manifests, and cross-platform milestones.

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