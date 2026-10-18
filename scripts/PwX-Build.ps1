#Requires -Version 5.1
<#
.SYNOPSIS
  PwX Build Engine - PS2EXE'den bağımsız .ps1 -> .exe dönüştürücü (komut satırı).
.DESCRIPTION
  Kaynak betiği DERLEME SIRASINDA ÇALIŞTIRMADAN; yalnızca sözdizimini ayrıştırır.
  PS7   : src\PwX.BuildHost.PS7 (PowerShell SDK host) -> dotnet publish
  PS51  : src\PwX.BuildHost.PS51 (C# başlatıcı)       -> .NET Framework csc.exe
.EXAMPLE
  .\scripts\PwX-Build.ps1 -Source .\tests\samples\hello.ps1 -Output .\out\hello.exe -Target PS7 -SingleFile
.EXAMPLE
  .\scripts\PwX-Build.ps1 -Source .\app.ps1 -Target PS51 -Mode Gui -Icon .\app.ico -ProductName "Uygulamam"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,
    [string]$Output,
    [ValidateSet('PS51', 'PS7')][string]$Target = 'PS7',
    [ValidateSet('Console', 'Gui')][string]$Mode = 'Console',
    [ValidateSet('SelfContained', 'FrameworkDependent')][string]$RuntimeMode = 'SelfContained',
    [ValidateSet('win-x64', 'win-arm64')][string]$Architecture = 'win-x64',
    [switch]$SingleFile,
    [string]$Icon,
    [string]$ProductName,
    [string]$CompanyName,
    [string]$Description,
    [string]$FileVersion = '1.0.0.0',
    [string]$ProductVersion,
    [string]$PsSdkVersion = '7.4.6',   # Roadmap 4.4: sürümü doğrulayıp sabitle
    [string]$Framework = 'net8.0',     # PS SDK 7.4.x -> net8.0
    [string]$LogPath,
    [switch]$Force,
    [switch]$KeepTemp,
    [switch]$EnableTrim,
    [switch]$EnableUpx,
    [switch]$AutoInstallPrereqs   # PS7: eksik .NET SDK 8+ / NuGet kaynağını otomatik kur/düzelt
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Root  = Split-Path -Parent $PSScriptRoot
$script:Diags = New-Object System.Collections.Generic.List[object]
$script:LogFile = $null
$script:EnvSaved = $null
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Bom   = New-Object System.Text.UTF8Encoding($true)

# ---------------------------------------------------------------- yardımcılar
function Write-Log {
    param([string]$Msg, [ValidateSet('Info', 'Warning', 'Error', 'Debug')][string]$Level = 'Info')
    $line = '[{0:HH:mm:ss}] [{1}] {2}' -f (Get-Date), $Level.ToUpper(), $Msg
    if ($script:LogFile) { [IO.File]::AppendAllText($script:LogFile, $line + [Environment]::NewLine, $script:Utf8NoBom) }
    switch ($Level) {
        'Info'    { Write-Host $line }
        'Warning' { Write-Host $line -ForegroundColor Yellow }
        'Error'   { Write-Host $line -ForegroundColor Red }
        'Debug'   { }   # yalnızca günlük dosyasına
    }
}
function Add-Diag {
    param([string]$Severity, [string]$Code, [string]$Message, [int]$Line = 0, [int]$Column = 0)
    $script:Diags.Add([pscustomobject]@{ Severity = $Severity; Code = $Code; Message = $Message; SourcePath = $script:SrcPath; Line = $Line; Column = $Column })
    $loc = if ($Line -gt 0) { " (satır $Line, sütun $Column)" } else { '' }
    Write-Log "$Code $Message$loc" $Severity
}
function Stop-Build { param([string]$Code, [string]$Message, [int]$Line = 0, [int]$Column = 0)
    Add-Diag 'Error' $Code $Message $Line $Column
    throw 'PWX_BUILD_FAILED'
}
function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [string]$WorkDir)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    Push-Location -LiteralPath $WorkDir
    try {
        & $File @Arguments 2>&1 | ForEach-Object { Write-Log ([string]$_) 'Debug' }
        $code = $LASTEXITCODE
    }
    finally { Pop-Location; $ErrorActionPreference = $old }
    return $code
}
function Get-ScriptText {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $start = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $start = 3 }
    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        return $strict.GetString($bytes, $start, $bytes.Length - $start)
    }
    catch {
        Add-Diag 'Warning' 'PWX2001' 'Kaynak geçerli UTF-8 değil; Windows-1254 (Türkçe) olarak okundu. Dosyayı UTF-8 BOM ile kaydetmeniz önerilir.'
        try { $enc = [Text.Encoding]::GetEncoding(1254) } catch { $enc = [Text.Encoding]::GetEncoding(28599) }
        return $enc.GetString($bytes)
    }
}
function ConvertTo-CsLiteral { param([string]$s) if ($null -eq $s) { $s = '' }; ($s -replace '\\', '\\' -replace '"', '\"' -replace "[\r\n]+", ' ') }
function ConvertTo-XmlText   { param([string]$s) [Security.SecurityElement]::Escape($s) }

# ---------------------------------------------------------------- PS7 gereksinimleri
function Invoke-NativeLines {
    param([string]$File, [string[]]$Arguments)
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $out = @(& $File @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $old }
    [pscustomobject]@{ Code = $code; Lines = $out }
}
function Get-DotnetSdkInfo {
    # 'dotnet' komutu yalnızca runtime ile de bulunur; gerçek bir SDK (8+) aranır.
    $cands = New-Object System.Collections.Generic.List[string]
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($cmd) { $cands.Add($cmd.Source) }
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
    if ($env:LOCALAPPDATA) { $roots += (Join-Path $env:LOCALAPPDATA 'Microsoft') }
    foreach ($root in $roots) {
        if ($root) {
            $p = Join-Path $root 'dotnet\dotnet.exe'
            if (Test-Path -LiteralPath $p) { $cands.Add($p) }
        }
    }
    foreach ($c in ($cands | Select-Object -Unique)) {
        $r = Invoke-NativeLines $c @('--list-sdks')
        $vers = @($r.Lines | ForEach-Object { ($_ -split ' ')[0] } | Where-Object { $_ -match '^(\d+)\.' -and [int]$Matches[1] -ge 8 })
        if ($vers.Count -gt 0) { return [pscustomobject]@{ Path = $c; Version = $vers[$vers.Count - 1] } }
    }
    return $null
}
function Install-DotnetSdk8 {
    # 1) winget  2) yedek: Microsoft'un resmi dotnet-install.ps1 betiği (kullanıcı klasörüne, yönetici gerektirmez)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Log '.NET SDK 8 winget ile kuruluyor (yönetici onayı istenebilir, birkaç dakika sürebilir)...'
        $r = Invoke-NativeLines $winget.Source @('install', '--id', 'Microsoft.DotNet.SDK.8', '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
        foreach ($l in $r.Lines) { Write-Log $l 'Debug' }
        $info = Get-DotnetSdkInfo
        if ($info) { return $info }
        Write-Log "winget kurulumu doğrulanamadı (çıkış kodu $($r.Code)); yedek yöntem deneniyor." 'Warning'
    }
    else { Write-Log 'winget bulunamadı; yedek yöntem (dotnet-install.ps1) kullanılacak.' 'Warning' }
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'
        $tmp = Join-Path ([IO.Path]::GetTempPath()) 'dotnet-install.ps1'
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { Write-Log "TLS 1.2 etkinleştirilemedi: $($_.Exception.Message)" 'Debug' }
        Write-Log ".NET SDK 8, resmi dotnet-install.ps1 ile kullanıcı klasörüne kuruluyor: $dir"
        Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $tmp -UseBasicParsing
        $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
        $r = Invoke-NativeLines $psExe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tmp, '-Channel', '8.0', '-InstallDir', $dir)
        foreach ($l in $r.Lines) { Write-Log $l 'Debug' }
    }
    catch { Write-Log "Yedek kurulum başarısız: $($_.Exception.Message)" 'Warning' }
    return (Get-DotnetSdkInfo)
}
function Get-NuGetSources {
    param([string]$DotnetExe)
    $r = Invoke-NativeLines $DotnetExe @('nuget', 'list', 'source')
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($l in $r.Lines) {
        if ($l -match '^\s*\d+\.\s+(.+?)\s+\[(Enabled|Disabled)\]\s*$') {
            $list.Add([pscustomobject]@{ Name = $Matches[1]; Enabled = ($Matches[2] -eq 'Enabled'); Url = '' })
        }
        elseif ($list.Count -gt 0 -and $l -match '^\s+(\S.*?)\s*$') {
            $last = $list[$list.Count - 1]
            if (-not $last.Url) { $last.Url = $Matches[1] }
        }
    }
    [pscustomobject]@{ Sources = $list.ToArray(); NoneFound = (($r.Lines -join "`n") -match 'No sources found') }
}
function Test-NuGetReady {
    # Yalnızca KESİN "etkin kaynak yok" durumunda $false döner; çıktı ayrıştırılamazsa engellemez.
    param([string]$DotnetExe)
    $s = Get-NuGetSources $DotnetExe
    $enabled = @($s.Sources | Where-Object { $_.Enabled })
    if ($enabled.Count -gt 0) { return $true }
    if ($s.NoneFound -or @($s.Sources).Count -gt 0) { return $false }
    return $true
}
function Repair-NuGetSources {
    # Kullanıcı düzeyindeki NuGet.Config'e nuget.org ekler veya devre dışı nuget.org'u etkinleştirir.
    param([string]$DotnetExe)
    $s = Get-NuGetSources $DotnetExe
    $org = @($s.Sources | Where-Object { $_.Url -match 'api\.nuget\.org' }) | Select-Object -First 1
    if ($org) {
        $r = Invoke-NativeLines $DotnetExe @('nuget', 'enable', 'source', $org.Name)
    }
    else {
        $r = Invoke-NativeLines $DotnetExe @('nuget', 'add', 'source', 'https://api.nuget.org/v3/index.json', '--name', 'nuget.org')
    }
    foreach ($l in $r.Lines) { Write-Log $l 'Debug' }
    return (Test-NuGetReady $DotnetExe)
}


# ---------------------------------------------------------------- ana akış
$sw = [Diagnostics.Stopwatch]::StartNew()
$workDir = $null
$result = [ordered]@{ Success = $false; OutputPath = $null; Target = $Target; Duration = $null; OutputSize = 0; LogPath = $null; Diagnostics = $script:Diags }
$script:SrcPath = $Source

try {
    # günlük
    if (-not $LogPath) { $LogPath = Join-Path $script:Root ('artifacts\logs\build-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)) }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
    $script:LogFile = $LogPath
    $result.LogPath = $LogPath
    Write-Log "PwX Build Engine başlıyor. Hedef=$Target Mod=$Mode Runtime=$RuntimeMode"

    # 1) kaynak
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { Stop-Build 'PWX1001' "Kaynak dosya bulunamadı: $Source" }
    $src = (Resolve-Path -LiteralPath $Source).ProviderPath
    $script:SrcPath = $src
    if ([IO.Path]::GetExtension($src) -ne '.ps1') { Add-Diag 'Warning' 'PWX1002' 'Kaynak dosyanın uzantısı .ps1 değil.' }

    # 2) çıktı yolu
    if (-not $Output) { $Output = [IO.Path]::ChangeExtension($src, '.exe') }
    if (-not [IO.Path]::GetExtension($Output)) { $Output += '.exe' }
    $Output = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path (Get-Location).ProviderPath $Output }))
    if ($Output -ieq $src) { Stop-Build 'PWX1004' 'Çıktı yolu kaynak dosyayla aynı olamaz.' }
    $outDir = Split-Path -Parent $Output
    try { New-Item -ItemType Directory -Force -Path $outDir | Out-Null
          $probe = Join-Path $outDir ('.pwx-probe-' + [guid]::NewGuid().ToString('N')); [IO.File]::WriteAllText($probe, 'x'); Remove-Item -LiteralPath $probe -Force }
    catch { Stop-Build 'PWX1005' "Çıktı klasörü yazılabilir değil: $outDir" }
    $baseName = [IO.Path]::GetFileNameWithoutExtension($Output)

    # 3) metaveri doğrulama
    if ($FileVersion -notmatch '^\d+(\.\d+){1,3}$') { Stop-Build 'PWX1007' "FileVersion geçersiz: $FileVersion (örn. 1.2.3.4)" }
    if (-not $ProductVersion) { $ProductVersion = $FileVersion }
    if (-not $ProductName) { $ProductName = $baseName }
    $iconFull = $null
    if ($Icon) {
        if (-not (Test-Path -LiteralPath $Icon -PathType Leaf)) { Stop-Build 'PWX1008' "İkon bulunamadı: $Icon" }
        $iconFull = (Resolve-Path -LiteralPath $Icon).ProviderPath
        $hdr = [IO.File]::ReadAllBytes($iconFull)
        if ($hdr.Length -lt 6 -or $hdr[0] -ne 0 -or $hdr[1] -ne 0 -or $hdr[2] -ne 1 -or $hdr[3] -ne 0) { Stop-Build 'PWX1009' 'İkon geçerli bir .ico dosyası değil.' }
    }

    # 4) sözdizimi (ÇALIŞTIRMADAN)
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$tokens, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
        foreach ($e in $errs) { Add-Diag 'Error' 'PWX1003' $e.Message $e.Extent.StartLineNumber $e.Extent.StartColumnNumber }
        throw 'PWX_BUILD_FAILED'
    }
    Write-Log 'Sözdizimi kontrolü başarılı.'

    # 5) mevcut çıktıyı koru
    $finalExe = $Output
    $distDir = $null
    if ($Target -eq 'PS7' -and -not $SingleFile) {
        $distDir = Join-Path $outDir $baseName
        $finalExe = Join-Path $distDir ($baseName + '.exe')
        if ((Test-Path -LiteralPath $distDir) -and -not $Force) { Stop-Build 'PWX1006' "Hedef klasör zaten var: $distDir (üzerine yazmak için -Force)" }
        if ((Test-Path -LiteralPath $distDir) -and -not (Test-Path -LiteralPath (Join-Path $distDir '.pwx-build'))) { Stop-Build 'PWX1006' "Hedef klasör PwX tarafından oluşturulmamış, silinm[...]" }
    }
    elseif ((Test-Path -LiteralPath $Output) -and -not $Force) { Stop-Build 'PWX1006' "Çıktı dosyası zaten var: $Output (üzerine yazmak için -Force)" }

    # 6) benzersiz geçici çalışma alanı
    $workDir = Join-Path ([IO.Path]::GetTempPath()) ('pwx-build-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDir | Out-Null
    Write-Log "Çalışma alanı: $workDir" 'Debug'

    # 7) payload: UTF-8 BOM ile normalize et (Türkçe karakter güvenliği)
    $payload = Join-Path $workDir 'payload.ps1'
    [IO.File]::WriteAllText($payload, (Get-ScriptText $src), $script:Utf8Bom)

    $gui = ($Mode -eq 'Gui')

    if ($Target -eq 'PS7') {
        # ------------------------------------------------ PowerShell 7 backend
        # Mod doğrulamaları
        if ($EnableTrim -and $RuntimeMode -ne 'SelfContained') {
            Stop-Build 'PWX3007' '-EnableTrim yalnızca -RuntimeMode SelfContained ile kullanılabilir (trimming self-contained gerektirir). Not: PowerShell SDK reflection kullandığı için trimming deneyseldir.'
        }
        if ($RuntimeMode -eq 'FrameworkDependent') {
            $needs = if ($Mode -eq 'Gui') { '.NET 8 Desktop Runtime (Microsoft.WindowsDesktop.App 8.x)' } else { '.NET 8 Runtime (Microsoft.NETCore.App 8.x)' }
            Write-Log "UYARI: FrameworkDependent çıktı, çalışacağı bilgisayarda $needs gerektirir. pwsh gerekmez; PowerShell motoru çıktıya dahildir." 'Warning'
        }

        # PS7 hedefi gereksinimleri: gerçek bir .NET SDK (8+) ve etkin bir NuGet paket kaynağı.
        $script:EnvSaved = @{ DOTNET_CLI_UI_LANGUAGE = $env:DOTNET_CLI_UI_LANGUAGE; VSLANG = $env:VSLANG }
        $env:DOTNET_CLI_UI_LANGUAGE = 'en'; $env:VSLANG = '1033'   # ayrıştırılabilir, kodlama sorunsuz çıktı
        $sdkInfo = Get-DotnetSdkInfo
        if (-not $sdkInfo) {
            if (-not $AutoInstallPrereqs) { Stop-Build 'PWX3005' '.NET SDK 8+ kurulu değil (yalnızca runtime yetmez). Otomatik kurulum için -AutoInstallPrereqs kullanın veya: winget install Microsoft.DotNet.SDK.8' }
            Write-Log '.NET SDK 8+ bulunamadı; otomatik kurulum başlatılıyor...' 'Warning'
            $sdkInfo = Install-DotnetSdk8
            if (-not $sdkInfo) { Stop-Build 'PWX3005' '.NET SDK 8 otomatik kurulamadı. Elle kurun: winget install Microsoft.DotNet.SDK.8 (veya https://aka.ms/dotnet/download)' }
            Write-Log ".NET SDK $($sdkInfo.Version) kuruldu."
        }
        $dotnet = [pscustomobject]@{ Source = $sdkInfo.Path }
        Write-Log ".NET SDK $($sdkInfo.Version): $($sdkInfo.Path)" 'Debug'
        if (-not (Test-NuGetReady $sdkInfo.Path)) {
            if (-not $AutoInstallPrereqs) { Stop-Build 'PWX3006' 'Etkin bir NuGet paket kaynağı yok; PowerShell SDK paketleri indirilemez. Otomatik düzeltme için -AutoInstallPrereqs kullanın veya: dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org' }
            Write-Log 'Etkin NuGet kaynağı yok; nuget.org ekleniyor/etkinleştiriliyor (kullanıcı düzeyi ayar)...' 'Warning'
            if (-not (Repair-NuGetSources $sdkInfo.Path)) { Stop-Build 'PWX3006' 'NuGet kaynağı düzeltilemedi. Elle: dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org' }
        }
        $hostSrc = Join-Path $script:Root 'src\PwX.BuildHost.PS7'
        if (-not (Test-Path -LiteralPath $hostSrc)) { Stop-Build 'PWX3002' "Host projesi bulunamadı: $hostSrc" }
        $hostDir = Join-Path $workDir 'host'
        Copy-Item -LiteralPath $hostSrc -Destination $hostDir -Recurse
        Get-ChildItem -LiteralPath $hostDir -Include bin, obj -Recurse -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('<Project><PropertyGroup>')
        $lines.Add('<PwxPayload>' + (ConvertTo-XmlText $payload) + '</PwxPayload>')
        $lines.Add('<PwxGui>' + $gui.ToString().ToLower() + '</PwxGui>')
        $lines.Add('<PwxSelfContained>' + ($RuntimeMode -eq 'SelfContained').ToString().ToLower() + '</PwxSelfContained>')
        $lines.Add('<PwxFramework>' + (ConvertTo-XmlText $Framework) + '</PwxFramework>')
        $lines.Add('<PwxPsSdkVersion>' + (ConvertTo-XmlText $PsSdkVersion) + '</PwxPsSdkVersion>')
        if ($iconFull) { $lines.Add('<PwxIcon>' + (ConvertTo-XmlText $iconFull) + '</PwxIcon>') }
        $lines.Add('<Product>' + (ConvertTo-XmlText $ProductName) + '</Product>')
        if ($CompanyName) { $lines.Add('<Company>' + (ConvertTo-XmlText $CompanyName) + '</Company>') }
        if ($Description) { $lines.Add('<Description>' + (ConvertTo-XmlText $Description) + '</Description>') }
        $lines.Add('<AssemblyVersion>' + $FileVersion + '</AssemblyVersion>')
        $lines.Add('<FileVersion>' + $FileVersion + '</FileVersion>')
        $lines.Add('<InformationalVersion>' + (ConvertTo-XmlText $ProductVersion) + '</InformationalVersion>')
        $lines.Add('</PropertyGroup></Project>')
        [IO.File]::WriteAllText((Join-Path $hostDir 'pwx.props'), ($lines -join "`r`n"), $script:Utf8Bom)

        $pub = Join-Path $workDir 'publish'
        $pa = @('publish', (Join-Path $hostDir 'PwX.BuildHost.PS7.csproj'), '-c', 'Release', '-r', $Architecture, '-o', $pub,
                '--nologo', '-v', 'minimal', '-p:DebugType=none', '-p:DebugSymbols=false')
        $pa += $(if ($RuntimeMode -eq 'SelfContained') { @('--self-contained', 'true') } else { @('--self-contained', 'false') })
        if ($SingleFile) { $pa += @('-p:PublishSingleFile=true', '-p:IncludeNativeLibrariesForSelfExtract=true', '-p:IncludeAllContentForSelfExtract=true') }
        if ($EnableTrim) {
            Write-Log 'UYARI: -EnableTrim deneyseldir; PowerShell reflection kullandığından çıktıyı mutlaka test edin.' 'Warning'
            $pa += @('-p:PublishTrimmed=true')
        }

        Write-Log "dotnet publish çalışıyor (ilk çalıştırmada PowerShell SDK indirilir; birkaç dakika sürebilir)..."
        $code = Invoke-Native $dotnet.Source $pa $workDir
        if ($code -ne 0) {
            $why = ''
            $logText = ''
            try { $logText = [IO.File]::ReadAllText($script:LogFile) } catch { Write-Log "Günlük dosyası okunamadı (hata nedeni çıkarımı atlandı): $($_.Exception.Message)" 'Debug' }
            if ($logText -match 'NU1301') { $why = ' NuGet sunucusuna ulaşılamadı (internet, proxy veya güvenlik duvarını kontrol edin).' }
            elseif ($logText -match 'NU110[01]') { $why = ' NuGet paketleri çözümlenemedi (etkin paket kaynağı yok ya da kaynakta paket bulunamadı); kontrol: dotnet nuget list source' }
            Stop-Build 'PWX3003' "dotnet publish başarısız (çıkış kodu $code).$why Ayrıntı için günlüğe bakın: $LogPath"
        }

        $built = Join-Path $pub 'PwXApp.exe'
        if (-not (Test-Path -LiteralPath $built)) { Stop-Build 'PWX3004' 'Yayın çıktısında PwXApp.exe bulunamadı.' }

        # PowerShell SDK Core yerleşik modüllerini ($PSHOME\Modules) yayın çıktısına yerleştir
        $runtimesMod = Join-Path $pub "runtimes\win\lib\$Framework\Modules"
        if (-not (Test-Path -LiteralPath $runtimesMod)) {
            $runtimesMod = Join-Path $pub "runtimes\win\lib\net8.0\Modules"
        }
        $targetMod = Join-Path $pub 'Modules'
        if ((Test-Path -LiteralPath $runtimesMod) -and -not (Test-Path -LiteralPath $targetMod)) {
            Copy-Item -LiteralPath $runtimesMod -Destination $targetMod -Recurse -Force
        }

        if ($SingleFile) {
            Copy-Item -LiteralPath $built -Destination $Output -Force
        }
        else {
            if (Test-Path -LiteralPath $distDir) { Remove-Item -LiteralPath $distDir -Recurse -Force }
            New-Item -ItemType Directory -Path $distDir | Out-Null
            Copy-Item -Path (Join-Path $pub '*') -Destination $distDir -Recurse -Force
            Rename-Item -LiteralPath (Join-Path $distDir 'PwXApp.exe') -NewName ($baseName + '.exe')
            [IO.File]::WriteAllText((Join-Path $distDir '.pwx-build'), "PwX Build Engine`r`n", $script:Utf8NoBom)
        }

        # Opsiyonel (deneysel): UPX sıkıştırma
        if ($EnableUpx) {
            $upx = Get-Command upx -ErrorAction SilentlyContinue
            if (-not $upx) { Write-Log 'UPX bulunamadı; sıkıştırma atlandı.' 'Warning' }
            elseif ($SingleFile) { Write-Log 'UPX atlandı: tek-dosya (single-file) paketler UPX ile bozulabilir.' 'Warning' }
            else {
                $exeToCompress = Join-Path $distDir ($baseName + '.exe')
                Write-Log "UPX (deneysel) uygulanıyor: $exeToCompress"
                $r = Invoke-NativeLines $upx.Source @('--best', '--lzma', $exeToCompress)
                foreach ($l in $r.Lines) { Write-Log $l 'Debug' }
                if ($r.Code -ne 0) { Write-Log "UPX başarısız (çıkış kodu $($r.Code)); çıktıyı kontrol edin." 'Warning' }
                else { Write-Log 'UPX sıkıştırması tamamlandı.' }
            }
        }
    }
    else {
        # ------------------------------------------------ Windows PowerShell 5.1 backend
        $csc = @("$env:windir\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:windir\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
               Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $csc) { Stop-Build 'PWX3101' '.NET Framework csc.exe bulunamadı.' }
        $stubSrc = Join-Path $script:Root 'src\PwX.BuildHost.PS51\Stub.cs'
        if (-not (Test-Path -LiteralPath $stubSrc)) { Stop-Build 'PWX3102' "Stub kaynağı bulunamadı: $stubSrc" }

        Copy-Item -LiteralPath $stubSrc -Destination (Join-Path $workDir 'Stub.cs')
        $asmInfo = @"
using System.Reflection;
[assembly: AssemblyTitle("$(ConvertTo-CsLiteral $(if ($Description) { $Description } else { $ProductName }))")]
[assembly: AssemblyCompany("$(ConvertTo-CsLiteral $CompanyName)")]
[assembly: AssemblyProduct("$(ConvertTo-CsLiteral $ProductName)")]
[assembly: AssemblyVersion("$FileVersion")]
[assembly: AssemblyFileVersion("$FileVersion")]
[assembly: AssemblyInformationalVersion("$(ConvertTo-CsLiteral $ProductVersion)")]
"@
        [IO.File]::WriteAllText((Join-Path $workDir 'AssemblyInfo.cs'), $asmInfo, $script:Utf8Bom)

        $rsp = New-Object System.Collections.Generic.List[string]
        $rsp.Add('/nologo'); $rsp.Add($(if ($gui) { '/target:winexe' } else { '/target:exe' }))
        $rsp.Add('/platform:anycpu'); $rsp.Add('/optimize+'); $rsp.Add('/debug-'); $rsp.Add('/utf8output')
        if ($gui) { $rsp.Add('/define:PWX_GUI') }
        $rsp.Add('/out:out.exe')
        $rsp.Add('/resource:payload.ps1,PwX.payload.ps1')
        if ($iconFull) { Copy-Item -LiteralPath $iconFull -Destination (Join-Path $workDir 'icon.ico'); $rsp.Add('/win32icon:icon.ico') }
        $rsp.Add('Stub.cs'); $rsp.Add('AssemblyInfo.cs')
        [IO.File]::WriteAllText((Join-Path $workDir 'build.rsp'), ($rsp -join "`r`n"), $script:Utf8Bom)

        Write-Log 'csc.exe çalışıyor...'
        $code = Invoke-Native $csc @('@build.rsp') $workDir
        if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $workDir 'out.exe'))) { Stop-Build 'PWX3103' "csc derlemesi başarısız (çıkış kodu $code). Ayrıntı: $LogPath" }
        Copy-Item -LiteralPath (Join-Path $workDir 'out.exe') -Destination $Output -Force
    }

    # 8) çıktıyı doğrula
    if (-not (Test-Path -LiteralPath $finalExe)) { Stop-Build 'PWX4001' 'Çıktı dosyası oluşmadı.' }
    $fi = Get-Item -LiteralPath $finalExe
    $mz = [IO.File]::ReadAllBytes($finalExe)[0..1]
    if ($fi.Length -le 0 -or $mz[0] -ne 0x4D -or $mz[1] -ne 0x5A) { Stop-Build 'PWX4002' 'Çıktı geçerli bir Windows yürütülebilir dosyası değil.' }

    $result.Success = $true
    $result.OutputPath = $finalExe
    $result.OutputSize = $fi.Length
    Write-Log ('BAŞARILI: {0} ({1:N1} MB)' -f $finalExe, ($fi.Length / 1MB))
}
catch {
    if ($_.Exception.Message -ne 'PWX_BUILD_FAILED') { Add-Diag 'Error' 'PWX9000' ("Beklenmeyen hata: " + $_.Exception.Message) }
    Write-Log 'DERLEME BAŞARISIZ.' 'Error'
}
finally {
    if ($script:EnvSaved) {
        $env:DOTNET_CLI_UI_LANGUAGE = $script:EnvSaved.DOTNET_CLI_UI_LANGUAGE
        $env:VSLANG = $script:EnvSaved.VSLANG
    }
    if ($workDir -and (Test-Path -LiteralPath $workDir) -and -not $KeepTemp) {
        try { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction Stop } catch { Write-Log "Geçici klasör silinemedi: $workDir" 'Warning' }
    }
    $sw.Stop()
    $result.Duration = $sw.Elapsed
    Write-Log ('Süre: {0:N1} sn | Günlük: {1}' -f $sw.Elapsed.TotalSeconds, $LogPath)
}

[pscustomobject]$result
if (-not $result.Success) { exit 1 }
