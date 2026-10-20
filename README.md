# pwxe — PwX Build Engine & CLI

<p align="center">
  <strong>Modern, ultra-fast and standalone PowerShell script to EXE build engine.</strong><br>
  <em>Convert PowerShell scripts into native Windows executables with zero external dependencies.</em>
</p>

<p align="center">
  <a href="https://github.com/mtahiryilmazz/pwxe/releases/latest"><img src="https://img.shields.io/badge/release-v1.6.2-blue.svg?style=flat-square" alt="Latest Release"></a>
  <a href="https://www.powershellgallery.com/packages/pwxe"><img src="https://img.shields.io/powershellgallery/v/pwxe.svg?style=flat-square&label=PSGallery" alt="PowerShell Gallery: pwxe"></a>
  <a href="https://www.nuget.org/packages/pwxe"><img src="https://img.shields.io/nuget/v/pwxe.svg?style=flat-square&label=NuGet" alt="NuGet: pwxe"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat-square" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-Windows%2010%20%7C%2011-0078D6.svg?style=flat-square" alt="Platform: Windows">
  <img src="https://img.shields.io/badge/PowerShell-5.1%20%7C%207.4%2B-5391FE.svg?style=flat-square" alt="PowerShell 5.1 & 7.4+">
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

## Build modes and Windows options

PS7 builds include the PowerShell engine. The pwsh command is not required on the target machine.

| Mode | Target-machine requirement | Typical size |
|---|---|---:|
| SelfContained | No .NET runtime installation | Largest; single-file is commonly 100+ MiB |
| FrameworkDependent | .NET 8 Runtime; GUI requires .NET 8 Desktop Runtime | Small host or roughly 40 MiB single-file |

SelfContained remains the default. Use RuntimeMode FrameworkDependent when a smaller distribution is more important than zero runtime prerequisites. Single-file can be combined with either mode.

The engine supports x86/x64, administrator execution, DPI awareness, Windows compatibility, long paths, EXE.config generation, UTF-8/Unicode output and output suppression.

The PS7 build machine needs a .NET 8 SDK and an enabled NuGet source. The target machine only needs the runtime listed above.

## 📥 Installation & Usage
 
### From PowerShell Gallery (Recommended)
```powershell
# PowerShell 7+ (Modern PSResourceGet)
Install-PSResource -Name pwxe -Scope CurrentUser

# PowerShell 5.1 / PowerShellGet
Install-Module -Name pwxe -Scope CurrentUser
```

### From NuGet.org
```powershell
# Using dotnet CLI
dotnet add package pwxe

# Using NuGet CLI
nuget install pwxe
```

### From GitHub Repository
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
| `-EnableTrim` | Switch | `False` | **Experimental.** `PublishTrimmed`; requires `-Runtime SelfContained` (PowerShell uses reflection - test the output) |
| `-EnableUpx` | Switch | `False` | **Experimental.** UPX-compress the output if `upx` is on PATH (skipped for single-file; may trigger AV false positives) |
| `-AutoInstallPrereqs` | Switch | `False` | PS7: install a missing .NET SDK 8 (winget, or the official `dotnet-install.ps1`) and enable `nuget.org` if no NuGet source is enabled |

> **PS7 output modes:** `SelfContained` (default) runs on any Windows machine without extra installs. `FrameworkDependent` is much smaller but needs the **.NET 8 Runtime** (GUI apps: **Windows Desktop Runtime 8**) on the target machine - `pwsh` is *not* required, the PowerShell engine ships inside the output. See [docs/PS7-build-modes.md](docs/PS7-build-modes.md).
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
