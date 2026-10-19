# PS7 build modes

`-Target PS7` produces an executable that hosts the PowerShell SDK (`Microsoft.PowerShell.SDK`, .NET 8). The PowerShell engine is **always part of the output**; the installed `pwsh` is never used.

| Mode | Option | Runs on a clean Windows machine | Size |
|------|--------|---------------------------------|------|
| Self-contained (default) | `-RuntimeMode SelfContained` | Yes | Largest (bundles the .NET runtime) |
| Framework-dependent | `-RuntimeMode FrameworkDependent` | Needs **.NET 8 Runtime** (GUI apps: **Windows Desktop Runtime 8**) | Much smaller (runtime not bundled) |

`-SingleFile` packs everything into one `.exe` in either mode.

## Windows output options

The build engine supports Architecture win-x86, win-x64 and win-arm64, administrator execution, DPI awareness, supported Windows versions, long paths, EXE.config generation, UTF-8/Unicode output and output suppression. These options are embedded in the executable or emitted beside it as EXE.config.

## Build-machine requirements (PS7 target)
- A real **.NET SDK 8+** (the runtime alone is not enough) - error `PWX3005`.
- At least one enabled **NuGet source** to restore the PowerShell SDK packages - error `PWX3006`.
- `-AutoInstallPrereqs` can fix both (winget, or the official `dotnet-install.ps1`; `nuget.org` is added/enabled in the user-level NuGet config).

## Experimental options
- `-EnableTrim` (`PublishTrimmed`): requires `-RuntimeMode SelfContained` (`PWX3007`). The PowerShell engine relies heavily on reflection, so always test the trimmed output.
- `-EnableUpx`: runs `upx --best --lzma` on the main exe if `upx` is on PATH. Skipped for single-file output (bundles can be corrupted). Packed executables are often flagged by antivirus products.

## Not measured
Output sizes are not tracked in this repository yet; measure with your own payload before choosing a mode.
