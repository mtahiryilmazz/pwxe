#Requires -Version 5.1
<#
.SYNOPSIS
  Integration test suite for pwxe InProcess hosting mode (-HostMode InProcess / -InProcess).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $scriptDir
$buildScript = Join-Path $repoRoot 'scripts\PwX-Build.ps1'
$sample = Join-Path $repoRoot 'tests\samples\hello.ps1'
$outDir = Join-Path $repoRoot 'artifacts\test-results\inproc_suite'

if (Test-Path -LiteralPath $outDir) { Remove-Item -LiteralPath $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $outDir | Out-Null

$results = New-Object System.Collections.Generic.List[object]

function Assert-Test {
    param([string]$Id, [string]$Name, [bool]$Pass, [string]$Detail)
    $results.Add([pscustomobject]@{
        Test   = $Id
        Name   = $Name
        Result = if ($Pass) { 'PASS' } else { 'FAIL' }
        Detail = $Detail
    })
}

# 1. PS51 InProcess Basic Build & Run
$exe1 = Join-Path $outDir 'inproc_basic.exe'
$res1 = & $buildScript -Source $sample -Output $exe1 -Target PS51 -HostMode InProcess -Force
Assert-Test 'T-INP-01' 'PS51 builds with -HostMode InProcess' ($res1.Success -and (Test-Path -LiteralPath $exe1)) "Size: $($res1.OutputSize)"

$out1 = & $exe1 -Message 'PwX InProcess Live' -Code 17
$code1 = $LASTEXITCODE
$pass1 = ($code1 -eq 17) -and ($out1 -join ' ' -match 'PwX InProcess Live') -and ($out1 -join ' ' -match 'ğüşıöçĞÜŞİÖÇ')
Assert-Test 'T-INP-02' 'PS51 InProcess executes with args, exit code, and unicode' $pass1 "ExitCode: $code1"

# 2. PS51 InProcess with EncryptPayload
$exe2 = Join-Path $outDir 'inproc_enc.exe'
$res2 = & $buildScript -Source $sample -Output $exe2 -Target PS51 -InProcess -EncryptPayload -Force
Assert-Test 'T-INP-03' 'PS51 InProcess builds with -EncryptPayload' ($res2.Success -and (Test-Path -LiteralPath $exe2)) "Size: $($res2.OutputSize)"

$out2 = & $exe2 -Message 'Encrypted InProcess' -Code 25
$code2 = $LASTEXITCODE
$pass2 = ($code2 -eq 25) -and ($out2 -join ' ' -match 'Encrypted InProcess')
Assert-Test 'T-INP-04' 'PS51 InProcess encrypted executes and returns exit code' $pass2 "ExitCode: $code2"

# 3. PS51 InProcess GUI Mode
$guiSample = Join-Path $repoRoot 'tests\samples\gui-edge.ps1'
$exe3 = Join-Path $outDir 'inproc_gui.exe'
$res3 = & $buildScript -Source $guiSample -Output $exe3 -Target PS51 -HostMode InProcess -Mode Gui -Force
Assert-Test 'T-INP-05' 'PS51 InProcess builds in Gui mode' ($res3.Success -and (Test-Path -LiteralPath $exe3)) "Size: $($res3.OutputSize)"

$p = Start-Process -FilePath $exe3 -ArgumentList '-Code 19' -PassThru -WindowStyle Hidden
$p.WaitForExit(10000) | Out-Null
$code3 = $p.ExitCode
Assert-Test 'T-INP-06' 'PS51 InProcess GUI executes and exits with code' ($code3 -eq 19) "ExitCode: $code3"

$results | Format-Table -AutoSize
$failCount = @($results | Where-Object Result -eq 'FAIL').Count
if ($failCount -gt 0) { exit 1 }
exit 0
