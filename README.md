# pwxe — PwX Build Engine & CLI

<p align="center">
  <strong>Modern, ultra-fast and standalone PowerShell script to EXE build engine.</strong><br>
  <em>Convert PowerShell scripts into native Windows executables with zero external dependencies.</em>
</p>

<p align="center">
  <a href="https://github.com/mtahiryilmazz/pwxe/releases/latest"><img src="https://img.shields.io/badge/release-v1.0.1-blue.svg?style=flat-square" alt="Latest Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat-square" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6.svg?style=flat-square" alt="Platform: Windows">
  <img src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207.4%2B-5391FE.svg?style=flat-square" alt="PowerShell 5.1 & 7.4+">
  <img src="https://img.shields.io/badge/PSGallery-pwxe-success.svg?style=flat-square" alt="PowerShell Gallery: pwxe">
</p>

---

## 🌟 Why pwxe?

`pwxe` is the standalone compilation engine that powers [PwX Studio](https://github.com/mtahiryilmazz/pwxstudio). Designed from the ground up for command-line users, DevOps engineers, and CI/CD automation pipelines:

- **🚀 Zero External Dependencies:** No need to download unverified third-party modules or connect to PSGallery at compile time. Works 100% offline in air-gapped enterprise environments.
- **⚡ Dual Target Runtimes:**
  - **PowerShell 5.1:** Uses Windows native `csc.exe` (Roslyn / .NET Framework) to build ultra-lightweight (~500 KB) executables in under 0.5 seconds.
  - **PowerShell 7.4+:** Compiles modern scripts using `.NET 8 SDK` and `Microsoft.PowerShell.SDK`.
- **📦 Single-File Packaging:** Option to embed all PS7 runtime libraries into a single, self-contained `.exe`.
- **🖼️ Icon & Form Integration:** Automatic PE header icon embedding + WinForms runtime icon bootstrapping.

---

## 📥 Installation

From **PowerShell Gallery**:
```powershell
Install-Module -Name pwxe -Scope CurrentUser
```

Or clone directly from GitHub:
```powershell
git clone https://github.com/mtahiryilmazz/pwxe.git
Import-Module .\pwxe\pwxe.psd1
```

---

## 🚀 Usage

### 1. Simple Quick Compile (CLI)
```powershell
pwxe .\myscript.ps1 .\myapp.exe
```

### 2. Full-Featured Cmdlet (`Invoke-Pwxe`)
```powershell
Invoke-Pwxe -Source .\myscript.ps1 `
            -Output .\myapp.exe `
            -Target PS51 `
            -Mode Gui `
            -Icon .\app.ico `
            -Title "My App" `
            -CompanyName "My Company" `
            -FileVersion "1.0.0.0"
```

### 3. PowerShell 7 Single-File Build
```powershell
Invoke-Pwxe -Source .\modern.ps1 `
            -Output .\modern.exe `
            -Target PS7 `
            -Runtime SelfContained `
            -SingleFile
```

---

## 📊 Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `-Source` | String | *Required* | Path to input `.ps1` script |
| `-Output` | String | `Source.exe` | Output `.exe` path |
| `-Target` | `PS51` / `PS7` | `PS51` | Target PowerShell engine |
| `-Mode` | `Console` / `Gui` | `Console` | Console window visibility |
| `-Runtime` | `SelfContained` / `FrameworkDependent` | `SelfContained` | PS7 runtime bundling |
| `-SingleFile` | Switch | `False` | Embed all dependencies into single `.exe` (PS7) |
| `-Icon` | String | `$null` | Application `.ico` file path |
| `-Title` | String | File name | Product name and description |
| `-CompanyName` | String | `$null` | Company/Publisher name |
| `-FileVersion` | String | `1.0.0.0` | Assembly file version |
| `-Force` | Switch | `False` | Overwrite existing output |

---

## 🖥️ Desktop GUI: PwX Studio

If you prefer a modern, full-featured desktop GUI with built-in online icon search, dark mode themes, and drag-and-drop support, check out **[PwX Studio](https://github.com/mtahiryilmazz/pwxstudio)**.

---

## 🧪 Testing

[![pwxe CI](https://github.com/mtahiryilmazz/pwxe/actions/workflows/ci.yml/badge.svg)](https://github.com/mtahiryilmazz/pwxe/actions/workflows/ci.yml)

| Suite | Command | Covers |
| :--- | :--- | :--- |
| Module | `powershell.exe -ExecutionPolicy Bypass -File .\tests\Test-Module.ps1` | Manifest, exports, `Invoke-Pwxe` PS51 + PS7 end-to-end |
| GUI host logic | `pwsh .\tests\Test-GuiHostLogic.ps1` | PS7 GUI host exit codes & argument binding |
| Smoke | `powershell.exe -ExecutionPolicy Bypass -File .\tests\Run-Smoke.ps1 [-SingleFile]` | PS51, PS7 console, PS7 GUI executables |

All suites run on every push via GitHub Actions as separate checks.

## 🗺️ Roadmap

See our planned milestones, security signing, and cross-platform goals in [ROADMAP.md](ROADMAP.md).

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).