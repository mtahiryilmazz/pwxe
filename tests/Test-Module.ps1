<#
.SYNOPSIS  pwxe PowerShell modülü testleri (manifest, dışa aktarımlar, Invoke-Pwxe uçtan uca).
.DESCRIPTION
  M-001..M-004 : manifest geçerliliği, sürüm uyumu, dışa aktarılan komut/alias'lar
  M-005..M-006 : Invoke-Pwxe ile PS51 derleme + EXE çalıştırma
  M-007..M-008 : Invoke-Pwxe ile PS7 derleme (Runtime/Architecture eşlemesi) + EXE çalıştırma
  M-009        : Test-PwxeEnvironment çalışır
  -SkipPS7 ile .NET SDK gerektiren testler atlanır.
#>
[CmdletBinding()]
param([switch]$SkipPS7)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root     = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $root 'pwxe.psd1'
$sample   = Join-Path $PSScriptRoot 'samples\hello.ps1'
$outRoot  = Join-Path $root 'artifacts\test-results\module'
$rows     = New-Object System.Collections.Generic.List[object]

function Add-Row($id, $name, $ok, $detail = '') {
    $rows.Add([pscustomobject]@{ Test = $id; Name = $name; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }); Detail = $detail })
}
function Invoke-Check($id, $name, [scriptblock]$body) {
    try { $r = & $body; Add-Row $id $name ([bool]$r[0]) ([string]$r[1]) }
    catch { Add-Row $id $name $false $_.Exception.Message }
}

New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

Invoke-Check 'M-001' 'Manifest geçerli (Test-ModuleManifest)' {
    $m = Test-ModuleManifest -Path $manifest -ErrorAction Stop
    @($true, "sürüm: $($m.Version)")
}

Invoke-Check 'M-002' 'Manifest sürümü CHANGELOG ile uyumlu' {
    $v = (Test-ModuleManifest -Path $manifest).Version.ToString()
    $log = Get-Content -LiteralPath (Join-Path $root 'CHANGELOG.md') -Raw -Encoding UTF8
    @(($log -match [regex]::Escape("## [$v]")), "manifest: $v")
}

Remove-Module pwxe -ErrorAction SilentlyContinue
Import-Module $manifest -Force

Invoke-Check 'M-003' 'Invoke-Pwxe ve Test-PwxeEnvironment dışa aktarılır' {
    $cmds = (Get-Command -Module pwxe -CommandType Function).Name
    @((($cmds -contains 'Invoke-Pwxe') -and ($cmds -contains 'Test-PwxeEnvironment')), ($cmds -join ', '))
}

Invoke-Check 'M-004' "'pwxe' ve 'New-PwxeExecutable' alias'ları" {
    $a = (Get-Command -Module pwxe -CommandType Alias).Name
    @((($a -contains 'pwxe') -and ($a -contains 'New-PwxeExecutable')), ($a -join ', '))
}

# ---- PS51 uçtan uca
$ps51Exe = Join-Path $outRoot 'ps51\hello.exe'
Invoke-Check 'M-005' 'Invoke-Pwxe -Target PS51 derler' {
    $res = Invoke-Pwxe -Source $sample -Output $ps51Exe -Target PS51 -Title 'pwxe test' -FileVersion '1.2.3.4' -Force
    @(($res.Success -and (Test-Path -LiteralPath $ps51Exe)), $res.OutputPath)
}
Invoke-Check 'M-006' 'PS51 EXE çalışır, argüman + çıkış kodu' {
    $o = (& $ps51Exe -Message 'modul-test' -Code 3 | Out-String)
    $code = $LASTEXITCODE
    $ver = (Get-Item -LiteralPath $ps51Exe).VersionInfo.FileVersion
    @((($o -match 'modul-test') -and ($code -eq 3) -and ($ver -eq '1.2.3.4')), "çıkış: $code; sürüm: $ver")
}

# ---- PS7 uçtan uca (Runtime -> RuntimeMode eşlemesini doğrular)
if (-not $SkipPS7) {
    $ps7Out = Join-Path $outRoot 'ps7\hello.exe'
    $ps7Exe = $null
    Invoke-Check 'M-007' 'Invoke-Pwxe -Target PS7 -Runtime/-Architecture derler' {
        $res = Invoke-Pwxe -Source $sample -Output $ps7Out -Target PS7 -Runtime SelfContained -Architecture win-x64 -Force
        $script:ps7Exe = $res.OutputPath
        @(($res.Success -and $res.OutputPath -and (Test-Path -LiteralPath $res.OutputPath)), $res.OutputPath)
    }
    Invoke-Check 'M-008' 'PS7 EXE çalışır (yerleşik modüller yüklenir)' {
        if (-not $script:ps7Exe) { return @($false, 'EXE yok') }
        $o = (& $script:ps7Exe -Message 'ps7-modul' -Code 4 2>&1 | Out-String)
        $code = $LASTEXITCODE
        @((($o -match 'ps7-modul') -and ($o -match 'ğüşıöçĞÜŞİÖÇ') -and ($code -eq 4)), "çıkış: $code")
    }
}

Invoke-Check 'M-009' 'Test-PwxeEnvironment çalışır' {
    $null = Test-PwxeEnvironment *>&1
    @($true, '')
}

# ---- M-010 UAC ExecutionLevel
$execLevelExe = Join-Path $outRoot 'ps51\exec_level.exe'
Invoke-Check 'M-010' 'Invoke-Pwxe -ExecutionLevel highestAvailable derler' {
    $res = Invoke-Pwxe -Source $sample -Output $execLevelExe -Target PS51 -ExecutionLevel highestAvailable -Force
    @(($res.Success -and (Test-Path -LiteralPath $execLevelExe)), $res.OutputPath)
}

# ---- M-011 Code Signing
$signedExe = Join-Path $outRoot 'ps51\signed.exe'
Invoke-Check 'M-011' 'Invoke-Pwxe Authenticode ile EXE imzalar' {
    $cert = $null
    try {
        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=PwxeTestSign' -CertStoreLocation 'Cert:\CurrentUser\My'
        $res = Invoke-Pwxe -Source $sample -Output $signedExe -Target PS51 -CertificateThumbprint $cert.Thumbprint -Force
        $sig = Get-AuthenticodeSignature -FilePath $signedExe
        $hasSig = ($sig -and $sig.SignerCertificate -and ($sig.SignerCertificate.Thumbprint -eq $cert.Thumbprint))
        @(($res.Success -and $hasSig), "İmza: $($sig.Status); Sertifika: $($sig.SignerCertificate.Subject)")
    }
    finally {
        if ($cert) {
            Remove-Item (Join-Path 'Cert:\CurrentUser\My' $cert.Thumbprint) -Force -ErrorAction SilentlyContinue
        }
    }
}

Remove-Module pwxe -ErrorAction SilentlyContinue

($rows | Format-Table -AutoSize | Out-String -Width 200).TrimEnd() | Write-Host
if ($rows | Where-Object Result -eq 'FAIL') { exit 1 }
$global:LASTEXITCODE = 0
exit 0
