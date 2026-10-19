# pwxe — Roadmap & Future Milestones

This document outlines the strategic roadmap, architecture goals, and planned feature milestones for **`pwxe`** (PwX Build Engine & CLI).

---

## 🎯 Vision

Provide the PowerShell and DevOps ecosystem with the most reliable, modern, and high-performance script-to-executable compilation engine. Built on official Microsoft toolchains (`csc.exe` and `Microsoft.PowerShell.SDK`), `pwxe` eliminates fragile third-party wrappers and delivers battle-tested native Windows binaries.

---

## 🗺️ Milestone Overview

| Milestone | Status | Key Focus | Target Release |
| :--- | :--- | :--- | :--- |
| **v1.0.x** | ✅ Completed | Dual-Engine Core, Exit Code Fidelity, PS7 Module Sanitation | Q4 2026 |
| **v1.1.0** | 🟡 In Progress | Security, Code Signing & UAC Manifest Controls | Q1 2027 |
| **v1.2.0** | 📋 Planned | Third-Party Module Bundling & Size Optimization | Q2 2027 |
| **v1.3.0** | 📋 Planned | Cross-Platform Runtimes (Linux/macOS) & Windows Services | Q3 2027 |

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
- [ ] **Authenticode Code Signing:**
  - `-CertificateThumbprint` / `-CertificateFile` parameters to automatically sign generated `.exe` binaries via `signtool.exe` or `Set-AuthenticodeSignature`.
  - Configurable RFC 3161 timestamping servers.
- [ ] **UAC Elevation Control:**
  - `-ExecutionLevel` parameter supporting `asInvoker` (default), `requireAdministrator`, and `highestAvailable`.
  - Embedded application manifest (`app.manifest`) generation without external tool dependencies.
- [ ] **Payload Protection:**
  - Optional AES-256 payload encryption with ephemeral in-memory decryption to protect proprietary logic in enterprise environments.
  - Antivirus false-positive mitigation guidelines and clean PE signature generation.

---

### Milestone 3: v1.2.0 — Custom Module Bundling & Performance
- [ ] **Custom Module Bundling (`-IncludeModules`):**
  - Package external PowerShell modules (e.g. `Import-Module Az.Accounts`, `Pester`, internal company modules) directly into the binary's embedded payload or output directory.
- [ ] **Binary Size Reduction:**
  - Explore safe managed assembly trimming for self-contained PS7 builds without breaking PowerShell dynamic language runtime (DLR) features.
- [ ] **Enhanced GUI Bootstrapping:**
  - Built-in splash screen option (`-SplashScreen <image.png>`) for long-loading GUI scripts.
  - DPI-awareness manifest defaults (`PerMonitorV2`).

---

### Milestone 4: v1.3.0 — Cross-Platform Compilation & Windows Services
- [ ] **Cross-Platform Host Targets:**
  - Compile to native Linux ELF (`linux-x64`, `linux-arm64`) and macOS Mach-O (`osx-x64`, `osx-arm64`) executables from Windows or Linux hosts.
- [ ] **Windows Service Wrapper Mode:**
  - Option to build scripts as Windows Services with Start/Stop lifecycle management and event log integration.
- [ ] **Standardized Logging Callbacks:**
  - Structured output streaming (JSON/Event Log/File) for headless automation environments.

---

## 🤝 Contributing to the Roadmap

Have ideas or requests? Please open an issue or feature discussion on the [pwxe GitHub Repository](https://github.com/mtahiryilmazz/pwxe).
