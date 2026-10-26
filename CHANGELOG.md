# pwxe — Changelog

All notable changes to the `pwxe` (PwX Build Engine & CLI) project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)  
Versioning: Semantic Versioning  
Project: pwxe — Standalone PowerShell to EXE Build Engine

---

## [1.7.0] — 2026-10-26

### Added
- **Authenticode Digital Code Signing:** Added `-CertificateThumbprint`, `-CertificateFile`, `-CertificatePassword`, and `-TimestampServer` parameters to `Invoke-Pwxe` and `PwX-Build.ps1`. Automatically signs generated binaries using `signtool.exe` (with RFC 3161 timestamps) with seamless fallback to native `Set-AuthenticodeSignature` (zero external dependencies).
- **UAC Execution Level Manifest Control:** Added `-ExecutionLevel` parameter supporting `asInvoker`, `requireAdministrator`, and `highestAvailable`. Directly embeds UAC elevation controls into the native Windows application manifest (`app.manifest`) without external tool requirements.
- **Automated Verification Tests:** Added comprehensive end-to-end tests `M-010` and `M-011` covering execution levels and self-signed code signing in `Test-Module.ps1`.

## [1.6.4] — 2026-10-21

### Security & Hardening
- **Host Error Handling Isolation:** Wrapped `PWX_ERROR_LOG` fatal error interception in `#if DEBUG || PWX_TESTHOOKS` preprocessor conditions to prevent arbitrary file append vulnerabilities in elevated release EXEs.
- **Safe Log Directory:** Changed default engine log directory to `%LOCALAPPDATA%\pwxe\logs` (with `%TEMP%` fallback) to prevent permission failures in machine-wide (`-Scope AllUsers`) module installations.
- **SDK & Dependency Updates:** Bumped `Microsoft.PowerShell.SDK` to `7.4.7`. Verified package vulnerability status.
- **Download Integrity Verification:** Added Authenticode digital signature and file size validation to `dotnet-install.ps1` in `Install-DotnetSdk8`.
- **Package Hygiene:** Added explicit exclude filters in `pwxe.nuspec` for `bin/`, `obj/`, and temporary files to prevent packaging intermediate build artifacts.
- **Publishing Key Protection:** Secured `Publish-Package.ps1` and CI workflows against leaking NuGet/PSGallery API keys in process lists or inline script strings.

### Fixed
- **Architecture Validation:** Added `win-x86` to `Invoke-Pwxe`'s `-Architecture` parameter validation set.
- **English Standardization:** Normalized all CLI diagnostic and error messages across module and publishing scripts to English.
