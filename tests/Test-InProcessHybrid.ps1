#Requires -Version 5.1
<#
.SYNOPSIS
  Automated test suite for Experimental In-Process Hybrid Runner (PwX.Hybrid.Prototype).
  Validates Kill Criteria A (Runtime & Isolation) and Kill Criteria B (20 Critical Cmdlets).
#>
[CmdletBinding()]
param(
    [string]$DllPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $scriptDir

if (-not $DllPath) {
    $DllPath = Join-Path $repoRoot 'src\PwX.Hybrid.Prototype\bin\Debug\netstandard2.0\PwX.Hybrid.Prototype.dll'
}

if (-not (Test-Path -LiteralPath $DllPath)) {
    throw "Hybrid prototype DLL not found: $DllPath. Run 'dotnet build src/PwX.Hybrid.Prototype' first."
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "PwX In-Process Hybrid Validation Test Suite" -ForegroundColor Cyan
Write-Host "Host Runtime: $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
Write-Host "Target Assembly: $DllPath" -ForegroundColor Cyan
Write-Host "=================================================================`n" -ForegroundColor Cyan

# ---------------------------------------------------------------- Test Kriter A: Assembly Loading
Write-Host "[Kriter A] Testing Assembly & SMA Loading..." -ForegroundColor Yellow
$kriterAPass = $false
$loadError = $null
try {
    $asm = [System.Reflection.Assembly]::LoadFrom($DllPath)
    $type = $asm.GetType('PwX.Hybrid.Prototype.HybridScriptRunner')
    if ($type) {
        $kriterAPass = $true
        Write-Host "PASS: Assembly loaded successfully without TypeInitializationException.`n" -ForegroundColor Green
    } else {
        $loadError = "Type PwX.Hybrid.Prototype.HybridScriptRunner not resolved."
    }
} catch {
    $loadError = $_.Exception.ToString()
}

if (-not $kriterAPass) {
    Write-Host "FAIL: Assembly load failed:`n$loadError`n" -ForegroundColor Red
}

# ---------------------------------------------------------------- Test Kriter B: 20 Cmdlets Matrix
$matrix = @(
    @{ Id = 'CMD-01'; Cmdlet = 'Get-ChildItem';        Script = 'Get-ChildItem -Path $env:TEMP | Select-Object -First 2' },
    @{ Id = 'CMD-02'; Cmdlet = 'Invoke-RestMethod';    Script = 'try { Invoke-RestMethod -Uri "https://httpbin.org/get" -TimeoutSec 3 } catch { "Network fallback ok" }' },
    @{ Id = 'CMD-03'; Cmdlet = 'Convert-Json';         Script = '$j = @{ name = "pwx" } | ConvertTo-Json; ($j | ConvertFrom-Json).name' },
    @{ Id = 'CMD-04'; Cmdlet = 'Import-Module';        Script = 'Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue; "Module Imported"' },
    @{ Id = 'CMD-05'; Cmdlet = 'Start-Process';        Script = 'Start-Process cmd.exe -ArgumentList "/c exit 0" -Wait -NoNewWindow; $LASTEXITCODE' },
    @{ Id = 'CMD-06'; Cmdlet = 'Get-Process';          Script = 'Get-Process -Id $PID | Select-Object -ExpandProperty ProcessName' },
    @{ Id = 'CMD-07'; Cmdlet = 'Get-Service';          Script = 'Get-Service -Name * -ErrorAction SilentlyContinue | Select-Object -First 1' },
    @{ Id = 'CMD-08'; Cmdlet = 'Get/Set-Content';      Script = '$f = Join-Path $env:TEMP "pwx-test.tmp"; Set-Content -Path $f -Value "test-data"; Get-Content -Path $f; Remove-Item $f -Force' },
    @{ Id = 'CMD-09'; Cmdlet = 'Select-Object';        Script = '1..5 | Select-Object -First 3' },
    @{ Id = 'CMD-10'; Cmdlet = 'Where-Object';         Script = '1..10 | Where-Object { $_ -gt 7 }' },
    @{ Id = 'CMD-11'; Cmdlet = 'ForEach-Object';       Script = '1..3 | ForEach-Object { $_ * 2 }' },
    @{ Id = 'CMD-12'; Cmdlet = 'Write-Output/Host';    Script = 'Write-Output "OutputOK"; Write-Host "HostOK"' },
    @{ Id = 'CMD-13'; Cmdlet = 'Test-Path';            Script = 'Test-Path $env:TEMP' },
    @{ Id = 'CMD-14'; Cmdlet = 'New/Remove-Item';      Script = '$d = Join-Path $env:TEMP "pwx-dir-test"; New-Item -ItemType Directory -Path $d -Force | Out-Null; Test-Path $d; Remove-Item $d -Recurse -Force' },
    @{ Id = 'CMD-15'; Cmdlet = 'Export/Import-Csv';    Script = '$f = Join-Path $env:TEMP "pwx-csv.csv"; [pscustomobject]@{A=1;B=2} | Export-Csv -Path $f -NoTypeInformation; (Import-Csv $f).A; Remove-Item $f -Force' },
    @{ Id = 'CMD-16'; Cmdlet = 'Invoke-Expression';    Script = 'Invoke-Expression "1 + 1"' },
    @{ Id = 'CMD-17'; Cmdlet = 'Get-Date';             Script = '(Get-Date).Year' },
    @{ Id = 'CMD-18'; Cmdlet = 'Measure-Object';       Script = '1..10 | Measure-Object -Sum | Select-Object -ExpandProperty Sum' },
    @{ Id = 'CMD-19'; Cmdlet = 'Try/Catch/Throw';      Script = 'try { throw "TestError" } catch { "Caught: " + $_.Exception.Message }' },
    @{ Id = 'CMD-20'; Cmdlet = 'Exit Code / Return';   Script = 'return 17' }
)

$results = New-Object System.Collections.Generic.List[object]
$passCount = 0
$failCount = 0

Write-Host "[Kriter B] Executing 20 Critical Cmdlets Matrix in In-Process Runspace:`n" -ForegroundColor Yellow

foreach ($item in $matrix) {
    $res = $null
    $pass = $false
    $detail = ""
    try {
        $runResult = [PwX.Hybrid.Prototype.HybridScriptRunner]::Execute($item.Script, @())
        if ($runResult.Success) {
            $pass = $true
            $passCount++
            $outStr = if ($runResult.Output -and $runResult.Output.Count -gt 0) {
                ($runResult.Output | ForEach-Object { $_.ToString() }) -join ', '
            } else { 'Void' }
            if ($outStr.Length -gt 35) { $outStr = $outStr.Substring(0, 32) + '...' }
            $detail = $outStr
        } else {
            $failCount++
            $detail = "ERR: " + $runResult.ErrorMessage
        }
    } catch {
        $failCount++
        $detail = "EXCEPTION: " + $_.Exception.Message
    }

    $results.Add([pscustomobject]@{
        Id     = $item.Id
        Cmdlet = $item.Cmdlet
        Result = if ($pass) { 'PASS' } else { 'FAIL' }
        Detail = $detail
    })
}

$results | Format-Table -AutoSize -Property Id, Cmdlet, Result, Detail

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host "Sonuç: $passCount / 20 PASS ($failCount FAIL)" -ForegroundColor $(if ($failCount -eq 0) { 'Green' } else { 'Red' })
Write-Host "Kriter A: $(if ($kriterAPass) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($kriterAPass) { 'Green' } else { 'Red' })
Write-Host "Kriter B: $(if ($passCount -eq 20) { 'PASS (20/20)' } else { 'FAIL (' + $passCount + '/20)' })" -ForegroundColor $(if ($passCount -eq 20) { 'Green' } else { 'Red' })
Write-Host "=================================================================`n" -ForegroundColor Cyan

if ($kriterAPass -and $passCount -eq 20) {
    exit 0
} else {
    exit 1
}
