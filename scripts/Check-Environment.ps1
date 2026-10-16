<#
.SYNOPSIS
  PwX Build Engine ortam kontrolü (Roadmap Aşama 1).
  Windows PowerShell 5.1, pwsh, .NET SDK ve csc.exe varlığını raporlar. Sistemde hiçbir şeyi değiştirmez.
#>
[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Continue'
$r = [ordered]@{}

$r.Windows       = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { [Environment]::OSVersion.VersionString }
$r.Is64BitOS     = [Environment]::Is64BitOperatingSystem
$r.HostPowerShell = $PSVersionTable.PSVersion.ToString()

$ps51 = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$r.WindowsPowerShell51 = Test-Path -LiteralPath $ps51

$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$r.Pwsh = if ($pwsh) { (& $pwsh.Source -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') } else { $null }

$dotnet = Get-Command dotnet.exe -ErrorAction SilentlyContinue
$sdks = @()
if ($dotnet) { $sdks = @(& $dotnet.Source --list-sdks 2>$null | ForEach-Object { ($_ -split ' ')[0] }) }
$r.DotnetSdks = $sdks
$sdk8 = @($sdks | Where-Object { $_ -match '^(\d+)\.' -and [int]$Matches[1] -ge 8 }).Count -gt 0

$csc = @("$env:windir\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
         "$env:windir\Microsoft.NET\Framework\v4.0.30319\csc.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
$r.Csc51 = $csc

$r.Backend_PS51_Ready = [bool]($r.WindowsPowerShell51 -and $csc)
$r.Backend_PS7_Ready  = [bool]$sdk8
$r.NuGetOrgReachable  = try { (Invoke-WebRequest 'https://api.nuget.org/v3/index.json' -UseBasicParsing -TimeoutSec 8).StatusCode -eq 200 } catch { $false }

if ($Json) { $r | ConvertTo-Json -Depth 4; return }

Write-Host "`n=== PwX Build Engine - Ortam Kontrolü ===" -ForegroundColor Cyan
foreach ($k in $r.Keys) {
    $v = $r[$k]; if ($v -is [array]) { $v = ($v -join ', ') }
    $ok = ($v -ne $null -and $v -ne '' -and $v -ne $false)
    Write-Host ('{0,-22} {1}' -f $k, $v) -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
}
Write-Host ''
if (-not $r.Backend_PS7_Ready)  { Write-Host "PS7 backend için .NET SDK 8+ gerekli (https://dotnet.microsoft.com/download)." -ForegroundColor Yellow }
if (-not $r.Backend_PS51_Ready) { Write-Host "PS 5.1 backend için powershell.exe ve .NET Framework csc.exe gerekli." -ForegroundColor Yellow }
if ($r.Backend_PS7_Ready -and -not $r.NuGetOrgReachable) { Write-Host "NuGet'e erişilemiyor: PS7 derlemesi paket geri yükleyemez (ilk derleme internet ister)." -ForegroundColor Yellow }
if (-not ($r.Backend_PS51_Ready -or $r.Backend_PS7_Ready)) { exit 1 }
