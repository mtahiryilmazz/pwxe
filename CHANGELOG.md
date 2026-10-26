# pwxe — Changelog

All notable changes to the `pwxe` (PwX Build Engine & CLI) project are documented in this file.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)  
Versioning: Semantic Versioning  
Project: pwxe — Standalone PowerShell to EXE Build Engine

---

## [1.8.0] — 2026-10-26

### Added
- **Payload Protection & Encryption:** Added `-EncryptPayload` and `-BindToMachine` parameters to `Invoke-Pwxe` and `scripts/PwX-Build.ps1`.
  - Scripts are protected using AES-256-CBC with randomized IVs and HMAC-SHA256 authenticated integrity tags (`PWXENC01` envelope).
  - Eliminates plaintext script extraction from compiled PE binary files.
  - Optional Windows DPAPI machine binding (`-BindToMachine`) locks executable decryption keys to the current machine and user context.
  - Ephemeral runtime in-memory execution and temporary runtime file cleanup.
- **Automated Verification:** Added `tests/Test-PayloadEncryption.ps1` with 7 end-to-end tests covering encrypted PS5.1, DPAPI machine-bound, and PS7 single-file encrypted builds.

### Fixed
- **Smoke Test Pipeline Encoding:** Improved standard console output decoding resilience for Turkish and Unicode characters in `tests/Run-Smoke.ps1`.

## [1.7.1] — 2026-10-26

### Fixed
- **Engine Reliability & Deployment Sync:** Updated core packaging with clean standalone module layout, refreshed dependencies, and full PwX Studio GUI engine synchronization.
- **Documentation & Research:** Integrated v1.8.0 Payload Protection specification and in-process hybrid research into `docs/`.

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
