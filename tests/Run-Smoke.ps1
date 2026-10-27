<#
.SYNOPSIS  PwX Build Engine duman testleri (T-001..T-006, T-GUI-001..009, T-009).
#>
[CmdletBinding()]
param([ValidateSet('PS51', 'PS7', 'All')][string]$Target = 'All', [switch]$SingleFile)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8
$root   = Split-Path -Parent $PSScriptRoot
$build  = Join-Path $root 'scripts\PwX-Build.ps1'
$sample = Join-Path $PSScriptRoot 'samples\hello.ps1'
$targets = if ($Target -eq 'All') { @('PS51', 'PS7') } else { @($Target) }
$rows = New-Object System.Collections.Generic.List[object]

function Add-Row($t, $id, $name, $ok, $detail = '') { $rows.Add([pscustomobject]@{ Target = $t; Test = $id; Name = $name; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }); Detail = $detail }) }

foreach ($t in $targets) {
    $dir = Join-Path $root "artifacts\test-results\$t"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $exe = Join-Path $dir 'hello.exe'
    $bargs = @{ Source = $sample; Output = $exe; Target = $t; Force = $true }
    if ($t -eq 'PS7' -and $SingleFile) { $bargs.SingleFile = $true }

    $res = & $build @bargs
    if (-not $res.Success) { Add-Row $t 'BUILD' 'Derleme' $false 'Derleme başarısız'; continue }
    $exePath = $res.OutputPath

    $o = (& $exePath | Out-String)
    Add-Row $t 'T-001' 'Varsayılan çıktı' ($o -match 'PwX Studio')

    $o = (& $exePath -Message 'abc' | Out-String)
    Add-Row $t 'T-002' 'Adlandırılmış parametre' ($o -match 'abc')

    $o = (& $exePath -Message 'iki kelime, dünya' | Out-String)
    Add-Row $t 'T-003' 'Boşluklu argüman' ($o -match 'iki kelime, dünya')

    & $exePath -Code 17 | Out-Null
    Add-Row $t 'T-004' 'Çıkış kodu 17' ($LASTEXITCODE -eq 17) "alınan: $LASTEXITCODE"

    $o = (& $exePath | Out-String)
    Add-Row $t 'T-005' 'Türkçe karakterler' ($o -match 'ğüşıöçĞÜŞİÖÇ|Ã¼|ğü')

    if ($t -eq 'PS7') {
        $o = (& $exePath 'konumsal-deger' | Out-String)
        Add-Row $t 'T-006' 'Konumsal argüman' ($o -match 'konumsal-deger')
    }
}

# PS51 In-Process Host: zero subprocess in-memory execution testleri
if ($targets -contains 'PS51') {
    $inProcDir = Join-Path $root 'artifacts\test-results\PS51-InProcess'
    New-Item -ItemType Directory -Force -Path $inProcDir | Out-Null
    $inProcExe = Join-Path $inProcDir 'hello_inproc.exe'
    $inProcRes = & $build -Source $sample -Output $inProcExe -Target PS51 -HostMode InProcess -Force
    if ($inProcRes.Success -and (Test-Path -LiteralPath $inProcExe)) {
        $o = (& $inProcExe | Out-String)
        Add-Row 'PS51-INP' 'T-INP-001' 'In-Process varsayılan çıktı' ($o -match 'PwX Studio')
        $o = (& $inProcExe -Message 'InProc-Test' | Out-String)
        Add-Row 'PS51-INP' 'T-INP-002' 'In-Process adlandırılmış parametre' ($o -match 'InProc-Test')
        $null = & $inProcExe -Code 17
        Add-Row 'PS51-INP' 'T-INP-003' 'In-Process çıkış kodu 17' ($LASTEXITCODE -eq 17) "alınan: $LASTEXITCODE"
        $o = (& $inProcExe | Out-String)
        Add-Row 'PS51-INP' 'T-INP-004' 'In-Process Türkçe karakterler' ($o -match 'ğüşıöçĞÜŞİÖÇ|Ã¼|ğü')
    } else {
        Add-Row 'PS51-INP' 'T-INP-001' 'In-Process derleme' $false 'Derleme başarısız'
    }
}

# PS7 GUI host: tek EXE'den (gui-edge.ps1) çıkış kodu ve argüman bağlama senaryoları.
if ($targets -contains 'PS7') {
    $guiSample = Join-Path $PSScriptRoot 'samples\gui-edge.ps1'
    $guiOut = Join-Path $root 'artifacts\test-results\PS7-GUI\gui-edge.exe'
    $guiRes = & $build -Source $guiSample -Output $guiOut -Target PS7 -Mode Gui -TestHooks -Force
    if ($guiRes.Success -and (Test-Path -LiteralPath $guiRes.OutputPath)) {
        $guiExe     = $guiRes.OutputPath
        $guiDir     = Split-Path -Parent $guiExe
        $guiErrLog  = Join-Path $guiDir 'gui-error.log'
        $guiOutFile = Join-Path $guiDir 'gui-out.txt'
        Remove-Item -LiteralPath $guiErrLog, $guiOutFile -Force -ErrorAction SilentlyContinue

        # GUI (WinExe) programlari '&' ile çağrıldığında PowerShell beklemez ve $LASTEXITCODE güncellenmez.
        # Çıkış kodu yalnızca Process nesnesinden güvenilir ölçülür. Zaman aşımı, takılan bir GUI
        # sürecinin CI'ı kilitlemesini önler. PWX_ERROR_LOG, hata iletişim kutusu yerine dosyaya yazdırır.
        # Bekleme süresi CI ortamına göre MAX_GUI_WAIT_MS ortam değişkeniyle ayarlanabilir (varsayılan 60 sn).
        $guiWaitMs = 60000
        $envWait = 0
        if ($env:MAX_GUI_WAIT_MS -and [int]::TryParse($env:MAX_GUI_WAIT_MS, [ref]$envWait) -and $envWait -gt 0) { $guiWaitMs = $envWait }

        function ConvertTo-ArgString([string[]]$List) {
            ($List | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
        }
        function Get-GuiExit([string[]]$ArgList = @()) {
            $sp = @{ FilePath = $guiExe; PassThru = $true; WindowStyle = 'Hidden' }
            if ($ArgList.Count -gt 0) { $sp.ArgumentList = ConvertTo-ArgString $ArgList }   # boş ArgumentList hata verir
            $p = Start-Process @sp
            $null = $p.Handle                                                                # ExitCode'un okunabilmesi için
            if (-not $p.WaitForExit($guiWaitMs)) {                                          # -999: zaman aşımı
                try { $p.Kill() } catch { Write-Warning "Zaman aşımına uğrayan GUI süreci sonlandırılamadı: $($_.Exception.Message)" }
                return -999
            }
            return $p.ExitCode
        }

        $env:PWX_ERROR_LOG = $guiErrLog
        try {
            $e = Get-GuiExit @('-Code', '17')
            Add-Row 'PS7-GUI' 'T-GUI-001' 'GUI host betik çıkış kodunu iletir (17)' ($e -eq 17) "beklenen: 17; alınan: $e"
            $e = Get-GuiExit @('-Code', '1')
            Add-Row 'PS7-GUI' 'T-GUI-002' 'GUI host çıkış kodu 1' ($e -eq 1) "beklenen: 1; alınan: $e"
            $e = Get-GuiExit
            Add-Row 'PS7-GUI' 'T-GUI-003' 'GUI host normal bitiş 0' ($e -eq 0) "beklenen: 0; alınan: $e"
            $e = Get-GuiExit @('-Name', 'abc', '-Code', '5')
            Add-Row 'PS7-GUI' 'T-GUI-004' 'GUI host adlandırılmış parametre sırası' ($e -eq 5) "beklenen: 5; alınan: $e"
            $e = Get-GuiExit @('-Code:7')
            Add-Row 'PS7-GUI' 'T-GUI-005' 'GUI host -Param:değer biçimi' ($e -eq 7) "beklenen: 7; alınan: $e"
            $e = Get-GuiExit @('-Loud', '-Code', '9')
            Add-Row 'PS7-GUI' 'T-GUI-006' 'Açık exit, Write-Error sonrası da kazanır; [switch] değer tüketmez' ($e -eq 9) "beklenen: 9; alınan: $e"

            $e = Get-GuiExit @('-Name', 'şğü ÇÖİ', '-Out', $guiOutFile, '-Code', '0')
            $got = if (Test-Path -LiteralPath $guiOutFile) { (Get-Content -LiteralPath $guiOutFile -Encoding UTF8 -Raw).Trim() } else { '<dosya yok>' }
            Add-Row 'PS7-GUI' 'T-GUI-007' 'Unicode/boşluklu değer betiğe ulaşır' (($e -eq 0) -and ($got -eq 'şğü ÇÖİ|False|0')) "çıkış: $e; içerik: $got"

            $e = Get-GuiExit @('-Native', '-NoExit')
            Add-Row 'PS7-GUI' 'T-GUI-008' 'Açık exit yok: yerel komut kodu sızmaz (0)' ($e -eq 0) "beklenen: 0; alınan: $e"

            $e = Get-GuiExit @('-Throw')
            $errText = if (Test-Path -LiteralPath $guiErrLog) { (Get-Content -LiteralPath $guiErrLog -Raw) } else { '' }
            Add-Row 'PS7-GUI' 'T-GUI-009' 'Sonlandırıcı hata: çıkış 1, hata günlüğe yazılır' (($e -eq 1) -and ($errText -match 'boom')) "çıkış: $e; günlük: $($errText.Trim())"
        }
        finally { Remove-Item Env:\PWX_ERROR_LOG -ErrorAction SilentlyContinue }
    }
    else {
        Add-Row 'PS7-GUI' 'T-GUI-001' 'GUI host betik çıkış kodunu iletir' $false 'GUI derlemesi başarısız'
    }
}

# T-009: sözdizimi hatası -> derleme başarısız, EXE oluşmamalı
$bad = Join-Path ([IO.Path]::GetTempPath()) ('pwx-bad-' + [guid]::NewGuid().ToString('N') + '.ps1')
[IO.File]::WriteAllText($bad, "Write-Output 'x'`r`nif ($true {", (New-Object Text.UTF8Encoding($true)))
$badOut = Join-Path $root 'artifacts\test-results\bad.exe'
& $build -Source $bad -Output $badOut -Target PS51 -Force *> $null
Add-Row 'ALL' 'T-009' 'Sözdizimi hatası reddedilir' (($LASTEXITCODE -eq 1) -and -not (Test-Path $badOut))
Remove-Item $bad -Force -ErrorAction SilentlyContinue

$rows | Format-Table -AutoSize
if ($rows | Where-Object Result -eq 'FAIL') {
    exit 1
}
$global:LASTEXITCODE = 0
exit 0

