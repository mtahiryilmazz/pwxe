# pwxe — Changelog

All notable changes to the `pwxe` (PwX Build Engine & CLI) project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)  
Versioning: Semantic Versioning  
Project: pwxe — Standalone PowerShell to EXE Build Engine

---

## [Unreleased]

## [1.6.0] — 2026-10-19

### Added
- End-to-end Windows output options: x86/x64 architecture, administrator manifest, DPI awareness, supported Windows versions, long paths, EXE.config, UTF-8/Unicode output and output suppression.
- FrameworkDependent + SingleFile packaging for smaller PS7 distributions.
- Comprehensive PS5.1, PS7 Console and PS7 GUI test coverage with runtime, negative-path and log validation.

### Changed
- FrameworkDependent remains opt-in; SelfContained remains the default.
- Documentation separates build-machine requirements from target-machine runtime requirements.

### Added
- Windows output options are now wired end-to-end: x86/x64 architecture, administrator manifest, DPI awareness, supported Windows versions, long paths, EXE.config, UTF-8/Unicode console output and output suppression.
- FrameworkDependent can now be combined with SingleFile for a smaller single executable that still requires the matching .NET 8 runtime.
- The PowerShell module forwards the Windows output options to the build engine.
- **PS7 prerequisite detection:** `-Target PS7` verifies a real .NET SDK 8+ (a runtime alone is not enough, `PWX3005`) and an enabled NuGet source (`PWX3006`) and fails early with a clear message instead of an opaque `dotnet publish` exit code.
- **`-AutoInstallPrereqs`** (script and `Invoke-Pwxe`): installs a missing .NET SDK 8 (winget, falling back to Microsoft's official `dotnet-install.ps1` into the user profile) and adds/enables `nuget.org` in the user-level NuGet config. Opt-in only.
- **`-EnableTrim`** (experimental): `PublishTrimmed` for PS7. Requires `-RuntimeMode SelfContained` (`PWX3007` otherwise).
- **`-EnableUpx`** (experimental): UPX compression pass; skipped for single-file output, exit code is checked.
- `Invoke-Pwxe` now forwards `-EnableTrim`, `-EnableUpx` and `-AutoInstallPrereqs`.
- `dotnet publish` failures now explain `NU1100` / `NU1101` / `NU1301` (NuGet) causes.
- `docs/PS7-build-modes.md`: accurate description of SelfContained vs FrameworkDependent and their requirements.

### Changed
- `-RuntimeMode` default stays **`SelfContained`**. `FrameworkDependent` is an explicit option; its build warning now correctly says the target needs the **.NET 8 Runtime** (Desktop Runtime for GUI), not `pwsh`.
- Native `dotnet` calls run with an English UI language (parseable logs, no OEM-codepage mojibake); environment variables are restored afterwards.

### Fixed
- `ConvertTo-CsLiteral` over-escaped backslashes (each `\` became four) - restored.
- Duplicate error code: the SDK check no longer reuses `PWX3004` ("PwXApp.exe not found"); it is `PWX3005`.

### Removed
- `docs/PS7-size-optimization-audit.md` (contained inaccurate claims: "requires pwsh", trimming with FrameworkDependent, non-existent CI action) and a stray `0001-*.patch` file in the repository root.

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
