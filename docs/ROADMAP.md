# pwxe — Roadmap & Future Milestones

This document outlines the strategic roadmap, architecture goals, and planned feature milestones for **`pwxe`** (PwX Build Engine & CLI).

---

## 🎯 Vision

Provide the PowerShell and DevOps ecosystem with the most reliable, modern, and high-performance script-to-executable compilation engine. Built on official Microsoft toolchains (`csc.exe` and `Microsoft.PowerShell.SDK`), `pwxe` eliminates fragile third-party wrappers and delivers battle-tested native Windows binaries.

---

## 🗺️ Milestone Overview

| Milestone | Status | Key Focus | Target Release |
| :--- | :--- | :--- | :--- |
| **v1.8.0** | ✅ Completed | Payload Encryption (AES-256), DPAPI Machine Binding & Test Suite | Q4 2026 |
| **v1.7.0** | ✅ Completed | Authenticode Code Signing, UAC Elevation Manifest Controls | Q4 2026 |
| **v1.6.4** | ✅ Completed | Security Hardening, Path Planting Protection, Dependency Updates | Q4 2026 |
| **v1.9.0** | ✅ Completed | In-Process Hosting, Zero-Subprocess SMA Runspaces | Q4 2026 |
| **v2.0.0** | 🏆 Released | Grand Final Major Release: Zero-Subprocess, Enterprise Security & 100% CI Fidelity | Q4 2026 |

---

## 🚀 Detailed Milestones

### Milestone 1: v1.0.x — Core Engine & Host Fidelity (Current)

The current implementation now includes validated PS5.1 and PS7 Console/GUI builds, SelfContained and FrameworkDependent modes, SingleFile packaging, x86/x64 selection, Windows manifests, EXE.config generation and deterministic diagnostics. The remaining work in this milestone is release packaging and broader clean-machine validation.
- [x] **Dual Target Engines:**
  - Fast, zero-dependency Windows PowerShell 5.1 compilation via Roslyn `csc.exe`.
  - Modern PowerShell 7.4+ hosting via .NET 8 SDK and `Microsoft.PowerShell.SDK`.
- [x] **Full Argument & Pipeline Support:**
  - High-fidelity argument forwarding supporting positional, named (`-Param Val`), colon syntax (`-Param:Val`), and switch parameters without value consumption.
- [x] **Exit Code Integrity:**
  - Exact exit code propagation from internal scripts (`exit N`), uncaught exceptions (exit code 1), and suppression of native process leakage (`$LASTEXITCODE` isolation).
- [x] **PowerShell Core Module Resolution:**
  - Automatic deployment and discovery of built-in Core modules (`Microsoft.PowerShell.Utility`, `Management`, etc.).
  - Inherited environment sanitation: stripping Windows PowerShell 5.1 Desktop paths from `$env:PSModulePath` to prevent runtime conflicts in child PS7 processes.
- [x] **CI/CD Smoke Testing Suite:**
  - Automated smoke tests (`tests/Run-Smoke.ps1`) covering PS5.1, PS7 console, PS7 GUI, and headless GUI host logic (`tests/Test-GuiHostLogic.ps1`).

---

### Milestone 2: v1.1.0 — Security, Signing & Manifest Control
- [x] **Authenticode Code Signing:**
  - `-CertificateThumbprint` / `-CertificateFile` parameters to automatically sign generated `.exe` binaries via `signtool.exe` or `Set-AuthenticodeSignature`.
  - Configurable RFC 3161 timestamping servers.
- [x] **UAC Elevation Control:**
  - `-ExecutionLevel` parameter supporting `asInvoker` (default), `requireAdministrator`, and `highestAvailable`.
  - Embedded application manifest (`app.manifest`) generation without external tool dependencies.
- [x] **Payload Protection (v1.8.0):**
  - Optional AES-256 payload encryption (`-EncryptPayload`) with ephemeral in-memory decryption to protect proprietary logic in enterprise environments.
  - Dual engine crypto design: AES-256-CBC + HMAC-SHA256 (`PWXENC01` envelope).
  - Optional machine and user binding (`-BindToMachine`) using Windows DPAPI.
  - See detailed architecture: [v1.8.0 Design Document](design/v1.8.0-payload-protection.md).
  - Experimental in-process hybrid research: [In-Process Hybrid Research](research/in-process-hybrid.md).
  - Strict kill criteria and isolated branch: [Hybrid Kill Criteria](design/hybrid-kill-criteria.md).

---

### Milestone 3: v1.9.0 — In-Process Hosting, Module Bundling & Performance
- [x] **Zero-Subprocess In-Process Runspace Hosting:**
  - Direct in-memory execution via `System.Management.Automation` for Windows PowerShell 5.1 (`-HostMode InProcess` / `-InProcess`).
  - AST-based parameter parser (`ScriptArguments`), exit code propagation, and full DPAPI/AES-256 payload protection integration.
- [ ] **Smart Stub Shared Runtime Extraction:**
  - Authenticode-verified, SHA-256 integrity-checked shared PowerShell runtime cache in `%LOCALAPPDATA%\pwxe\runtime`.
- [ ] **Custom Module Bundling (`-IncludeModules`):**
  - Package external PowerShell modules (e.g. `Import-Module Az.Accounts`, `Pester`, internal company modules) directly into the binary's embedded payload or output directory.
- [ ] **Binary Size Reduction:**
  - Explore safe managed assembly trimming for self-contained PS7 builds without breaking PowerShell dynamic language runtime (DLR) features.
- [ ] **Enhanced GUI Bootstrapping:**
  - Built-in splash screen option (`-SplashScreen <image.png>`) for long-loading GUI scripts.
  - DPI-awareness manifest defaults (`PerMonitorV2`).

---

### Milestone 4: v2.0.0 — Grand Final Major Release (Enterprise Hardening & Zero-Subprocess Production)
- [x] **Zero-Subprocess In-Process Runspace Hosting (PS5.1):**
  - Fully integrated in-memory execution via native `System.Management.Automation` Runspaces (`-HostMode InProcess` / `-InProcess`).
  - Native Windows API console codepage configuration (CP 65001 / UTF-8) across InProcess and Subprocess modes.
  - Complete AST parameter parser (`ScriptArguments`), exit code capture, and seamless AES-256/DPAPI payload encryption.
- [x] **Universal Encoding & CI Stability:**
  - Full UTF-8 BOM test suite validation ensuring 100% CI pass rate across all Windows runners.
  - Cross-architecture and dual-engine test coverage (Module, PS7 GUI, Smoke tests).
- [x] **Production Multi-Channel Publishing:**
  - Automated dual-channel release to PowerShell Gallery (`PSGallery`) and NuGet.org with OIDC authentication.

---

### Future Exploration: Cross-Platform Compilation & Windows Services
- [ ] **Cross-Platform Host Targets:**
  - Compile to native Linux ELF (`linux-x64`, `linux-arm64`) and macOS Mach-O (`osx-x64`, `osx-arm64`) executables from Windows or Linux hosts.
- [ ] **Windows Service Wrapper Mode:**
  - Option to build scripts as Windows Services with Start/Stop lifecycle management and event log integration.
- [ ] **Standardized Logging Callbacks:**
  - Structured output streaming (JSON/Event Log/File) for headless automation environments.

---

## 🤝 Contributing to the Roadmap

Have ideas or requests? Please open an issue or feature discussion on the [pwxe GitHub Repository](https://github.com/mtahiryilmazz/pwxe).
