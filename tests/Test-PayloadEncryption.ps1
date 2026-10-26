#Requires -Version 5.1
<#
.SYNOPSIS
  Automated integration tests for pwxe v1.8.0 Payload Protection (AES-256 + HMAC-SHA256 + DPAPI).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Split-Path -Parent $scriptDir
$buildScript = Join-Path $repoRoot 'scripts\PwX-Build.ps1'
$sample = Join-Path $repoRoot 'tests\samples\hello.ps1'
$outDir = Join-Path $repoRoot 'artifacts\test-results\encryption'

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

try {
    # ---------------------------------------------------- T-ENC-01: PS51 EncryptPayload Build
    $outPs51 = Join-Path $outDir 'enc_ps51.exe'
    $bResPs51 = & $buildScript -Source $sample -Output $outPs51 -Target PS51 -EncryptPayload -Force
    Assert-Test 'T-ENC-01' 'PS51 builds with -EncryptPayload' ($bResPs51.Success -and (Test-Path -LiteralPath $outPs51)) "Size: $($bResPs51.OutputSize)"

    # ---------------------------------------------------- T-ENC-02: Plaintext Absence in PS51 Binary
    $bytesPs51 = [System.IO.File]::ReadAllBytes($outPs51)
    $strPs51 = [System.Text.Encoding]::ASCII.GetString($bytesPs51)
    $hasPlain = $strPs51.Contains('PwX Studio') -or $strPs51.Contains('Türkçe: ğüşıöçĞÜŞİÖÇ')
    Assert-Test 'T-ENC-02' 'PS51 binary contains no plaintext source' (-not $hasPlain) "PlaintextFound: $hasPlain"

    # ---------------------------------------------------- T-ENC-03: PS51 Encrypted Execution & Exit Code
    $runOutPs51 = & $outPs51 -Message "Encrypted PS51 Success" -Code 17
    $codePs51 = $LASTEXITCODE
    $passPs51 = ($codePs51 -eq 17) -and ($runOutPs51 -join ' ' -match 'Encrypted PS51 Success')
    Assert-Test 'T-ENC-03' 'PS51 encrypted binary executes with exit code' $passPs51 "ExitCode: $codePs51"

    # ---------------------------------------------------- T-ENC-04: PS51 Machine Bound (DPAPI)
    $outBound = Join-Path $outDir 'enc_bound.exe'
    $bResBound = & $buildScript -Source $sample -Output $outBound -Target PS51 -EncryptPayload -BindToMachine -Force
    $runOutBound = & $outBound -Message "DPAPI Bound Success" -Code 23
    $codeBound = $LASTEXITCODE
    $passBound = ($codeBound -eq 23) -and ($runOutBound -join ' ' -match 'DPAPI Bound Success')
    Assert-Test 'T-ENC-04' 'PS51 DPAPI machine-bound binary builds and runs' $passBound "ExitCode: $codeBound"

    # ---------------------------------------------------- T-ENC-05: PS7 EncryptPayload SingleFile Build & Execution
    $outPs7 = Join-Path $outDir 'enc_ps7.exe'
    $bResPs7 = & $buildScript -Source $sample -Output $outPs7 -Target PS7 -SingleFile -EncryptPayload -Force
    Assert-Test 'T-ENC-05' 'PS7 builds with -EncryptPayload -SingleFile' ($bResPs7.Success -and (Test-Path -LiteralPath $outPs7)) "Size: $($bResPs7.OutputSize)"

    $runOutPs7 = & $outPs7 -Message "Encrypted PS7 Success" -Code 29
    $codePs7 = $LASTEXITCODE
    $passPs7 = ($codePs7 -eq 29) -and ($runOutPs7 -join ' ' -match 'Encrypted PS7 Success')
    Assert-Test 'T-ENC-06' 'PS7 encrypted binary executes with exit code' $passPs7 "ExitCode: $codePs7"

    # ---------------------------------------------------- T-ENC-07: Plaintext Absence in PS7 Binary
    $bytesPs7 = [System.IO.File]::ReadAllBytes($outPs7)
    $strPs7 = [System.Text.Encoding]::ASCII.GetString($bytesPs7)
    $hasPlainPs7 = $strPs7.Contains('PwX Studio') -or $strPs7.Contains('Türkçe: ğüşıöçĞÜŞİÖÇ')
    Assert-Test 'T-ENC-07' 'PS7 binary contains no plaintext source' (-not $hasPlainPs7) "PlaintextFound: $hasPlainPs7"
}
catch {
    Assert-Test 'T-ENC-ERR' 'Unhandled test execution error' $false $_.Exception.Message
}

$results | Format-Table -AutoSize
$failures = @($results | Where-Object { $_.Result -eq 'FAIL' })
if ($failures.Count -gt 0) {
    Write-Error "$($failures.Count) payload encryption test(s) failed."
    exit 1
}
Write-Output "All $($results.Count) Payload Protection tests PASSED successfully."
exit 0
