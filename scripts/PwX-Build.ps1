#Requires -Version 5.1
<#
.SYNOPSIS
  PwX Build Engine - Standalone .ps1 -> .exe converter (CLI).
.DESCRIPTION
  Parses source script syntax WITHOUT EXECUTING it during compilation.
  PS7   : src\PwX.BuildHost.PS7 (PowerShell SDK host) -> dotnet publish
  PS51  : src\PwX.BuildHost.PS51 (C# launcher)        -> .NET Framework csc.exe
.EXAMPLE
  .\scripts\PwX-Build.ps1 -Source .\tests\samples\hello.ps1 -Output .\out\hello.exe -Target PS7 -SingleFile
.EXAMPLE
  .\scripts\PwX-Build.ps1 -Source .\app.ps1 -Target PS51 -Mode Gui -Icon .\app.ico -ProductName "MyApp"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,
    [string]$Output,
    [ValidateSet('PS51', 'PS7')][string]$Target = 'PS7',
    [ValidateSet('Console', 'Gui')][string]$Mode = 'Console',
    [ValidateSet('SelfContained', 'FrameworkDependent')][string]$RuntimeMode = 'SelfContained',
    [ValidateSet('win-x86', 'win-x64', 'win-arm64')][string]$Architecture = 'win-x64',
    [switch]$SingleFile,
    [string]$Icon,
    [string]$ProductName,
    [string]$CompanyName,
    [string]$Description,
    [string]$FileVersion = '1.0.0.0',
    [string]$ProductVersion,
    [string]$PsSdkVersion = '7.4.7',   # Roadmap 4.4: pinned tested version
    [string]$Framework = 'net8.0',     # PS SDK 7.4.x -> net8.0
    [string]$LogPath,
    [switch]$Force,
    [switch]$KeepTemp,
    [switch]$EnableTrim,
    [switch]$EnableUpx,
    [switch]$TestHooks,
    [switch]$AutoInstallPrereqs,  # PS7: auto-install missing .NET SDK 8+ / repair NuGet source
    [bool]$Admin = $false,
    [ValidateSet('asInvoker', 'requireAdministrator', 'highestAvailable')][string]$ExecutionLevel = 'asInvoker',
    [string]$CertificateThumbprint,
    [string]$CertificateFile,
    [string]$CertificatePassword,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
    [bool]$Utf8 = $true,
    [bool]$Unicode = $false,
    [bool]$Dpi = $false,
    [bool]$Config = $false,
    [bool]$SupportOS = $false,
    [bool]$LongPaths = $false,
    [bool]$NoOutput = $false,
    [switch]$EncryptPayload,
    [switch]$BindToMachine
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Root  = Split-Path -Parent $PSScriptRoot
$script:Diags = New-Object System.Collections.Generic.List[object]
$script:LogFile = $null
$script:EnvSaved = $null
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Bom   = New-Object System.Text.UTF8Encoding($true)

# ---------------------------------------------------------------- Helpers
function Write-Log {
    param([string]$Msg, [ValidateSet('Info', 'Warning', 'Error', 'Debug')][string]$Level = 'Info')
    $line = '[{0:HH:mm:ss}] [{1}] {2}' -f (Get-Date), $Level.ToUpperInvariant(), $Msg
    if ($script:LogFile) { [IO.File]::AppendAllText($script:LogFile, $line + [Environment]::NewLine, $script:Utf8NoBom) }
    switch ($Level) {
        'Info'    { Write-Host $line }
        'Warning' { Write-Host $line -ForegroundColor Yellow }
        'Error'   { Write-Host $line -ForegroundColor Red }
        'Debug'   { }   # Log file only
    }
}
function Add-Diag {
    param([string]$Severity, [string]$Code, [string]$Message, [int]$Line = 0, [int]$Column = 0)
    $script:Diags.Add([pscustomobject]@{ Severity = $Severity; Code = $Code; Message = $Message; SourcePath = $script:SrcPath; Line = $Line; Column = $Column })
    $loc = if ($Line -gt 0) { " (line $Line, col $Column)" } else { '' }
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
        Add-Diag 'Warning' 'PWX2001' 'Source is not valid UTF-8; reading as fallback encoding. Saving source with UTF-8 BOM is recommended.'
        try { $enc = [Text.Encoding]::GetEncoding(1252) } catch { $enc = [Text.Encoding]::Default }
        return $enc.GetString($bytes)
    }
}
function ConvertTo-CsLiteral { param([string]$s) if ($null -eq $s) { $s = '' }; ($s -replace '\\', '\\' -replace '"', '\"' -replace "[\r\n]+", ' ') }
function ConvertTo-XmlText   { param([string]$s) [Security.SecurityElement]::Escape($s) }

function New-AppManifest {
    param([string]$Path, [string]$ExecutionLevel = 'asInvoker', [bool]$DpiAware = $false, [bool]$OsSupport = $false, [bool]$LongPathAware = $false)
    $windows = if ($DpiAware -or $LongPathAware) {
        $dpiNode = if ($DpiAware) { '<dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware><dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>' } else { '' }
        $longNode = if ($LongPathAware) { '<longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>' } else { '' }
        '<application xmlns="urn:schemas-microsoft-com:asm.v3"><windowsSettings>' + $dpiNode + $longNode + '</windowsSettings></application>'
    } else { '' }
    $compat = if ($OsSupport) { '<compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1"><application><supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/><supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}"/></application></compatibility>' } else { '' }
    $xml = '<?xml version="1.0" encoding="utf-8" standalone="yes"?><assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0"><assemblyIdentity version="1.0.0.0" processorArchitecture="*" name="PwXApp" type="win32"/><trustInfo xmlns="urn:schemas-microsoft-com:asm.v3"><security><requestedPrivileges><requestedExecutionLevel level="{0}" uiAccess="false" /></requestedPrivileges></security></trustInfo>{1}{2}</assembly>' -f $ExecutionLevel, $windows, $compat
    [IO.File]::WriteAllText($Path, $xml, $script:Utf8NoBom)
}
function New-AppConfig {
    param([string]$Path)
    $xml = '<?xml version="1.0" encoding="utf-8"?><configuration><startup useLegacyV2RuntimeActivationPolicy="true"><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.0"/></startup></configuration>'
    [IO.File]::WriteAllText($Path, $xml, $script:Utf8NoBom)
}

function Invoke-CodeSign {
    param(
        [string]$TargetExe,
        [string]$Thumbprint,
        [string]$CertFile,
        [string]$CertPassword,
        [string]$Timestamp
    )
    if (-not $Thumbprint -and -not $CertFile) { return }

    Write-Log 'Signing executable...'
    $cert = $null
    $cleanThumb = $null
    if ($Thumbprint) {
        $cleanThumb = ($Thumbprint -replace '\s+', '').ToUpperInvariant()
        $cert = Get-ChildItem -Path Cert:\CurrentUser\My, Cert:\LocalMachine\My -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $cleanThumb } | Select-Object -First 1
        if (-not $cert) {
            Stop-Build 'PWX5001' "Code signing certificate with thumbprint '$Thumbprint' not found in Cert:\CurrentUser\My or Cert:\LocalMachine\My."
        }
    }
    elseif ($CertFile) {
        $fullCertPath = (Resolve-Path -LiteralPath $CertFile -ErrorAction SilentlyContinue).Path
        if (-not $fullCertPath -or -not (Test-Path -LiteralPath $fullCertPath)) {
            Stop-Build 'PWX5001' "Code signing certificate file not found: $CertFile"
        }
        try {
            if ($CertPassword) {
                $secPass = if ($CertPassword -is [System.Security.SecureString]) { $CertPassword } else { ConvertTo-SecureString $CertPassword -AsPlainText -Force }
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($fullCertPath, $secPass, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
            } else {
                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($fullCertPath)
            }
        }
        catch {
            Stop-Build 'PWX5001' "Failed to load certificate from $CertFile : $($_.Exception.Message)"
        }
    }

    # 1. Try signtool.exe if available (best RFC 3161 timestamping)
    $signtool = $null
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { $signtool = $cmd.Source }
    else {
        $kitsBin = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
        if (Test-Path -LiteralPath $kitsBin) {
            $cands = @(Get-ChildItem -LiteralPath $kitsBin -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'x64' })
            if ($cands.Count -gt 0) { $signtool = $cands[0].FullName }
        }
    }

    $signed = $false
    if ($signtool) {
        Write-Log "Using signtool: $signtool" 'Debug'
        $stArgs = New-Object System.Collections.Generic.List[string]
        $stArgs.Add('sign'); $stArgs.Add('/fd'); $stArgs.Add('SHA256')
        if ($Timestamp) {
            $stArgs.Add('/tr'); $stArgs.Add($Timestamp); $stArgs.Add('/td'); $stArgs.Add('SHA256')
        }
        if ($cleanThumb) {
            $stArgs.Add('/sha1'); $stArgs.Add($cleanThumb)
        }
        elseif ($CertFile) {
            $stArgs.Add('/f'); $stArgs.Add($fullCertPath)
            if ($CertPassword) { $stArgs.Add('/p'); $stArgs.Add($CertPassword) }
        }
        $stArgs.Add($TargetExe)
        $code = Invoke-Native $signtool $stArgs.ToArray() (Split-Path -Parent $TargetExe)
        if ($code -eq 0) {
            $signed = $true
            Write-Log 'Binary successfully signed with signtool.'
        }
        else {
            Write-Log "signtool failed (exit code $code), attempting fallback to Set-AuthenticodeSignature..." 'Warning'
        }
    }

    if (-not $signed) {
        try {
            $signArgs = @{
                FilePath      = $TargetExe
                Certificate   = $cert
                HashAlgorithm = 'SHA256'
            }
            if ($Timestamp) { $signArgs.TimestampServer = $Timestamp }
            $sigResult = Set-AuthenticodeSignature @signArgs
            if ($sigResult.Status -eq 'Valid' -or $sigResult.Status -eq 'UnknownError') {
                Write-Log "Binary signed with Set-AuthenticodeSignature (Status: $($sigResult.Status))."
            }
            else {
                Write-Log "Set-AuthenticodeSignature returned status: $($sigResult.Status) - $($sigResult.StatusMessage)" 'Warning'
            }
        }
        catch {
            Stop-Build 'PWX5001' "Code signing failed: $($_.Exception.Message)"
        }
    }
}

# ---------------------------------------------------------------- Payload Protection (v1.8.0)
function Protect-PwXPayload {
    param(
        [byte[]]$PlainBytes,
        [switch]$BindMachine
    )

    # Magic Header: PWXENC01 (8 bytes)
    $magic = [System.Text.Encoding]::ASCII.GetBytes("PWXENC01")
    $flag = if ($BindMachine) { [byte]1 } else { [byte]0 }

    # Generate 256-bit Key and 128-bit IV
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.GenerateKey()
    $aes.GenerateIV()

    # Encrypt Payload
    $encryptor = $aes.CreateEncryptor()
    $cipherBytes = $encryptor.TransformFinalBlock($PlainBytes, 0, $PlainBytes.Length)

    # Key Protection: If BindMachine, protect key via Windows DPAPI (CurrentUser)
    $keyBytes = $aes.Key
    if ($BindMachine) {
        $entropy = [System.Text.Encoding]::UTF8.GetBytes("PwX-Machine-Binding-Entropy-v1.8.0")
        $keyBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $keyBytes,
            $entropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
    }

    # HMAC-SHA256 over (Flag + IV + KeyBlob + CipherText) using raw AES key
    $hmac = New-Object System.Security.Cryptography.HMACSHA256 (,$aes.Key)
    $msHmac = New-Object System.IO.MemoryStream
    $msHmac.WriteByte($flag)
    $msHmac.Write($aes.IV, 0, $aes.IV.Length)
    $msHmac.Write($keyBytes, 0, $keyBytes.Length)
    $msHmac.Write($cipherBytes, 0, $cipherBytes.Length)
    $tag = $hmac.ComputeHash($msHmac.ToArray())

    # Build Final Package:
    # [Magic: 8B][Flag: 1B][IV: 16B][KeyLen: 2B (ushort, LittleEndian)][KeyBlob: NB][Tag: 32B][CipherLen: 4B (int, LittleEndian)][CipherBytes]
    $outMs = New-Object System.IO.MemoryStream
    $outMs.Write($magic, 0, $magic.Length)
    $outMs.WriteByte($flag)
    $outMs.Write($aes.IV, 0, $aes.IV.Length)

    $keyLenBytes = [System.BitConverter]::GetBytes([ushort]$keyBytes.Length)
    $outMs.Write($keyLenBytes, 0, $keyLenBytes.Length)
    $outMs.Write($keyBytes, 0, $keyBytes.Length)

    $outMs.Write($tag, 0, $tag.Length)

    $cipherLenBytes = [System.BitConverter]::GetBytes([int]$cipherBytes.Length)
    $outMs.Write($cipherLenBytes, 0, $cipherLenBytes.Length)
    $outMs.Write($cipherBytes, 0, $cipherBytes.Length)

    return $outMs.ToArray()
}

# ---------------------------------------------------------------- PS7 prerequisites
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
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Log 'Installing .NET SDK 8 via winget (may require elevation, may take a few minutes)...'
        $r = Invoke-NativeLines $winget.Source @('install', '--id', 'Microsoft.DotNet.SDK.8', '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements')
        foreach ($l in $r.Lines) { Write-Log $l 'Debug' }
        $info = Get-DotnetSdkInfo
        if ($info) { return $info }
        Write-Log "winget installation could not be verified (exit code $($r.Code)); trying fallback method." 'Warning'
    }
    else { Write-Log 'winget not found; using fallback method (dotnet-install.ps1).' 'Warning' }
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('dotnet-install-' + [guid]::NewGuid().ToString('N') + '.ps1')
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { Write-Log "Could not set TLS 1.2: $($_.Exception.Message)" 'Debug' }
        Write-Log "Installing .NET SDK 8 via official dotnet-install.ps1 to user directory: $dir"
        Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $tmp -UseBasicParsing
        if (-not (Test-Path -LiteralPath $tmp) -or (Get-Item -LiteralPath $tmp).Length -lt 1000) {
            throw "Downloaded dotnet-install.ps1 is empty or corrupted."
        }
        $sig = Get-AuthenticodeSignature -FilePath $tmp -ErrorAction SilentlyContinue
        if ($sig -and $sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -notmatch 'Microsoft') {
            Write-Log "Untrusted signature on dotnet-install.ps1: $($sig.SignerCertificate.Subject)" 'Warning'
        }
        $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
        $r = Invoke-NativeLines $psExe @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tmp, '-Channel', '8.0', '-InstallDir', $dir)
        foreach ($l in $r.Lines) { Write-Log $l 'Debug' }
    }
    catch { Write-Log "Fallback installation failed: $($_.Exception.Message)" 'Warning' }
    finally {
        if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
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
    param([string]$DotnetExe)
    $s = Get-NuGetSources $DotnetExe
    $enabled = @($s.Sources | Where-Object { $_.Enabled })
    if ($enabled.Count -gt 0) { return $true }
    if ($s.NoneFound -or @($s.Sources).Count -gt 0) { return $false }
    return $true
}
function Repair-NuGetSources {
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

# ---------------------------------------------------------------- Main build pipeline
$sw = [Diagnostics.Stopwatch]::StartNew()
$workDir = $null
$result = [ordered]@{ Success = $false; OutputPath = $null; Target = $Target; Duration = $null; OutputSize = 0; LogPath = $null; Diagnostics = $script:Diags }
$script:SrcPath = $Source

try {
    # Logging setup: use repo artifacts/logs in development, or %LOCALAPPDATA%/pwxe/logs in installed environments
    if (-not $LogPath) {
        $devGit = Join-Path $script:Root '.git'
        if (Test-Path -LiteralPath $devGit) {
            $LogPath = Join-Path $script:Root ('artifacts\logs\build-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
        } else {
            $baseLogDir = if ($env:LOCALAPPDATA) {
                Join-Path $env:LOCALAPPDATA 'pwxe\logs'
            } else {
                Join-Path ([System.IO.Path]::GetTempPath()) 'pwxe\logs'
            }
            $LogPath = Join-Path $baseLogDir ('build-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
        }
    }
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) | Out-Null
    } catch {
        $LogPath = Join-Path ([System.IO.Path]::GetTempPath()) ('pwxe-build-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LogPath) -ErrorAction SilentlyContinue | Out-Null
    }
    $script:LogFile = $LogPath
    $result.LogPath = $LogPath
    Write-Log "PwX Build Engine starting. Target=$Target Mode=$Mode Runtime=$RuntimeMode"

    # 1) Source validation
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { Stop-Build 'PWX1001' "Source file not found: $Source" }
    $src = (Resolve-Path -LiteralPath $Source).ProviderPath
    $script:SrcPath = $src
    if ([IO.Path]::GetExtension($src) -ne '.ps1') { Add-Diag 'Warning' 'PWX1002' 'Source file extension is not .ps1.' }

    # 2) Output path resolution
    if (-not $Output) { $Output = [IO.Path]::ChangeExtension($src, '.exe') }
    if (-not [IO.Path]::GetExtension($Output)) { $Output += '.exe' }
    $Output = [IO.Path]::GetFullPath($(if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path (Get-Location).ProviderPath $Output }))
    if ($Output -ieq $src) { Stop-Build 'PWX1004' 'Output path cannot be identical to source file.' }
    $outDir = Split-Path -Parent $Output
    try {
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        $probe = Join-Path $outDir ('.pwx-probe-' + [guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force
    }
    catch { Stop-Build 'PWX1005' "Output directory is not writable: $outDir" }
    $baseName = [IO.Path]::GetFileNameWithoutExtension($Output)

    # 3) Metadata validation
    if ($FileVersion -notmatch '^\d+(\.\d+){1,3}$') { Stop-Build 'PWX1007' "FileVersion is invalid: $FileVersion (e.g. 1.2.3.4)" }
    if (-not $ProductVersion) { $ProductVersion = $FileVersion }
    if (-not $ProductName) { $ProductName = $baseName }
    $iconFull = $null
    if ($Icon) {
        if (-not (Test-Path -LiteralPath $Icon -PathType Leaf)) { Stop-Build 'PWX1008' "Icon file not found: $Icon" }
        $iconFull = (Resolve-Path -LiteralPath $Icon).ProviderPath
        $hdr = [IO.File]::ReadAllBytes($iconFull)
        if ($hdr.Length -lt 6 -or $hdr[0] -ne 0 -or $hdr[1] -ne 0 -or $hdr[2] -ne 1 -or $hdr[3] -ne 0) { Stop-Build 'PWX1009' 'Icon file is not a valid .ico file.' }
    }

    # 4) Syntax parsing (WITHOUT EXECUTING)
    $tokens = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$tokens, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
        foreach ($e in $errs) { Add-Diag 'Error' 'PWX1003' $e.Message $e.Extent.StartLineNumber $e.Extent.StartColumnNumber }
        throw 'PWX_BUILD_FAILED'
    }
    Write-Log 'Syntax check passed.'

    # 5) Destination safety checks
    $finalExe = $Output
    $distDir = $null
    if ($Target -eq 'PS7' -and -not $SingleFile) {
        $distDir = Join-Path $outDir $baseName
        $finalExe = Join-Path $distDir ($baseName + '.exe')
        if ((Test-Path -LiteralPath $distDir) -and -not $Force) { Stop-Build 'PWX1006' "Target folder already exists: $distDir (use -Force to overwrite)" }
        if ((Test-Path -LiteralPath $distDir) -and -not (Test-Path -LiteralPath (Join-Path $distDir '.pwx-build'))) { Stop-Build 'PWX1006' "Target folder was not created by PwX, refusing to delete: $distDir" }
    }
    elseif ((Test-Path -LiteralPath $Output) -and -not $Force) { Stop-Build 'PWX1006' "Output file already exists: $Output (use -Force to overwrite)" }

    # 6) Unique temporary workspace
    $workDir = Join-Path ([IO.Path]::GetTempPath()) ('pwx-build-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDir | Out-Null
    Write-Log "Workspace: $workDir" 'Debug'
    $manifest = $null
    if ($Admin -and $ExecutionLevel -eq 'asInvoker') { $ExecutionLevel = 'requireAdministrator' }
    if ($ExecutionLevel -ne 'asInvoker' -or $Dpi -or $SupportOS -or $LongPaths) {
        $manifest = Join-Path $workDir 'app.manifest'
        New-AppManifest $manifest $ExecutionLevel $Dpi $SupportOS $LongPaths
        Write-Log "Windows application manifest generated (ExecutionLevel=$ExecutionLevel, DPI=$Dpi, SupportOS=$SupportOS, LongPaths=$LongPaths)." 'Debug'
    }

    # 7) Payload: normalize with UTF-8 BOM, optionally encrypt (AES-256)
    $payload = Join-Path $workDir 'payload.ps1'
    $scriptContent = Get-ScriptText $src
    $plainBytes = $script:Utf8Bom.GetBytes($scriptContent)
    if ($EncryptPayload) {
        $payload = Join-Path $workDir 'payload.enc'
        $encryptedBytes = Protect-PwXPayload -PlainBytes $plainBytes -BindMachine:$BindToMachine
        [IO.File]::WriteAllBytes($payload, $encryptedBytes)
        Write-Log "Payload encrypted with AES-256-CBC + HMAC-SHA256 (BindToMachine=$BindToMachine, Size=$($encryptedBytes.Length) bytes)."
    }
    else {
        [IO.File]::WriteAllBytes($payload, $plainBytes)
    }

    $gui = ($Mode -eq 'Gui')

    if ($Target -eq 'PS7') {
        # ------------------------------------------------ PowerShell 7 backend
        if ($EnableTrim -and $RuntimeMode -ne 'SelfContained') {
            Stop-Build 'PWX3007' '-EnableTrim can only be used with -RuntimeMode SelfContained. Note: Trimming is experimental for PowerShell SDK.'
        }
        if ($RuntimeMode -eq 'FrameworkDependent') {
            $needs = if ($Mode -eq 'Gui') { '.NET 8 Desktop Runtime (Microsoft.WindowsDesktop.App 8.x)' } else { '.NET 8 Runtime (Microsoft.NETCore.App 8.x)' }
            Write-Log "WARNING: FrameworkDependent output requires $needs on target machine. pwsh is not required; PowerShell engine is included." 'Warning'
        }

        $script:EnvSaved = @{ DOTNET_CLI_UI_LANGUAGE = $env:DOTNET_CLI_UI_LANGUAGE; VSLANG = $env:VSLANG }
        $env:DOTNET_CLI_UI_LANGUAGE = 'en'; $env:VSLANG = '1033'
        $sdkInfo = Get-DotnetSdkInfo
        if (-not $sdkInfo) {
            if (-not $AutoInstallPrereqs) { Stop-Build 'PWX3005' '.NET SDK 8+ is not installed. Use -AutoInstallPrereqs or install manually: winget install Microsoft.DotNet.SDK.8' }
            Write-Log '.NET SDK 8+ not found; starting automatic installation...' 'Warning'
            $sdkInfo = Install-DotnetSdk8
            if (-not $sdkInfo) { Stop-Build 'PWX3005' '.NET SDK 8 could not be installed automatically. Install manually: winget install Microsoft.DotNet.SDK.8' }
            Write-Log ".NET SDK $($sdkInfo.Version) installed."
        }
        $dotnet = [pscustomobject]@{ Source = $sdkInfo.Path }
        Write-Log ".NET SDK $($sdkInfo.Version): $($sdkInfo.Path)" 'Debug'
        if (-not (Test-NuGetReady $sdkInfo.Path)) {
            if (-not $AutoInstallPrereqs) { Stop-Build 'PWX3006' 'No active NuGet package source; cannot restore PowerShell SDK. Use -AutoInstallPrereqs or run: dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org' }
            Write-Log 'No active NuGet source found; adding/enabling nuget.org...' 'Warning'
            if (-not (Repair-NuGetSources $sdkInfo.Path)) { Stop-Build 'PWX3006' 'Could not repair NuGet source. Run: dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org' }
        }
        $hostSrc = Join-Path $script:Root 'src\PwX.BuildHost.PS7'
        if (-not (Test-Path -LiteralPath $hostSrc)) { Stop-Build 'PWX3002' "Host project not found: $hostSrc" }
        $hostDir = Join-Path $workDir 'host'
        Copy-Item -LiteralPath $hostSrc -Destination $hostDir -Recurse
        Get-ChildItem -LiteralPath $hostDir -Include bin, obj -Recurse -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('<Project><PropertyGroup>')
        $lines.Add('<PwxPayload>' + (ConvertTo-XmlText $payload) + '</PwxPayload>')
        $lines.Add('<PwxEncrypted>' + ($EncryptPayload.IsPresent.ToString().ToLowerInvariant()) + '</PwxEncrypted>')
        $lines.Add('<PwxGui>' + $gui.ToString().ToLowerInvariant() + '</PwxGui>')
        $lines.Add('<PwxUtf8>' + (($Utf8 -or $Unicode).ToString().ToLowerInvariant()) + '</PwxUtf8>')
        $lines.Add('<PwxNoOutput>' + $NoOutput.ToString().ToLowerInvariant() + '</PwxNoOutput>')
        $lines.Add('<PwxSelfContained>' + ($RuntimeMode -eq 'SelfContained').ToString().ToLowerInvariant() + '</PwxSelfContained>')
        $lines.Add('<PwxFramework>' + (ConvertTo-XmlText $Framework) + '</PwxFramework>')
        $lines.Add('<PwxPsSdkVersion>' + (ConvertTo-XmlText $PsSdkVersion) + '</PwxPsSdkVersion>')
        if ($iconFull) { $lines.Add('<PwxIcon>' + (ConvertTo-XmlText $iconFull) + '</PwxIcon>') }
        $lines.Add('<Product>' + (ConvertTo-XmlText $ProductName) + '</Product>')
        if ($CompanyName) { $lines.Add('<Company>' + (ConvertTo-XmlText $CompanyName) + '</Company>') }
        if ($Description) { $lines.Add('<Description>' + (ConvertTo-XmlText $Description) + '</Description>') }
        if ($manifest) { $lines.Add('<PwxManifest>' + (ConvertTo-XmlText $manifest) + '</PwxManifest>') }
        if ($TestHooks) { $lines.Add('<PwxTestHooks>true</PwxTestHooks>') }
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
            Write-Log 'WARNING: -EnableTrim is experimental; verify output before distribution.' 'Warning'
            $pa += @('-p:PublishTrimmed=true')
        }

        Write-Log "dotnet publish running (PowerShell SDK packages will be downloaded on first run)..."
        $code = Invoke-Native $dotnet.Source $pa $workDir
        if ($code -ne 0) {
            $why = ''
            $logText = ''
            try { $logText = [IO.File]::ReadAllText($script:LogFile) } catch { Write-Log "Could not read log file: $($_.Exception.Message)" 'Debug' }
            if ($logText -match 'NU1301') { $why = ' Unable to reach NuGet server (check internet connection or proxy).' }
            elseif ($logText -match 'NU110[01]') { $why = ' Could not resolve NuGet packages; verify source: dotnet nuget list source' }
            Stop-Build 'PWX3003' "dotnet publish failed (exit code $code).$why See log for details: $LogPath"
        }

        $built = Join-Path $pub 'PwXApp.exe'
        if (-not (Test-Path -LiteralPath $built)) { Stop-Build 'PWX3004' 'PwXApp.exe not found in publish output.' }

        # Deploy built-in PowerShell modules ($PSHOME\Modules) to output
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

        if ($Config) {
            $configPath = if ($SingleFile) { "$Output.config" } else { Join-Path $distDir ($baseName + '.exe.config') }
            New-AppConfig $configPath
        }

        # Optional: UPX compression
        if ($EnableUpx) {
            $upx = Get-Command upx -ErrorAction SilentlyContinue
            if (-not $upx) { Write-Log 'UPX not found; compression skipped.' 'Warning' }
            elseif ($SingleFile) { Write-Log 'UPX skipped: single-file packages may become corrupted with UPX.' 'Warning' }
            else {
                $exeToCompress = Join-Path $distDir ($baseName + '.exe')
                Write-Log "Applying UPX compression: $exeToCompress"
                $r = Invoke-NativeLines $upx.Source @('--best', '--lzma', $exeToCompress)
                foreach ($l in $r.Lines) { Write-Log $l 'Debug' }
                if ($r.Code -ne 0) { Write-Log "UPX failed (exit code $($r.Code)); check output." 'Warning' }
                else { Write-Log 'UPX compression completed.' }
            }
        }
    }
    else {
        # ------------------------------------------------ Windows PowerShell 5.1 backend
        $csc = @("$env:windir\Microsoft.NET\Framework64\v4.0.30319\csc.exe", "$env:windir\Microsoft.NET\Framework\v4.0.30319\csc.exe") |
               Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $csc) { Stop-Build 'PWX3101' '.NET Framework csc.exe not found.' }
        $stubSrc = Join-Path $script:Root 'src\PwX.BuildHost.PS51\Stub.cs'
        if (-not (Test-Path -LiteralPath $stubSrc)) { Stop-Build 'PWX3102' "Stub source not found: $stubSrc" }

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
        $platform = if ($Architecture -eq 'win-x86') { 'x86' } elseif ($Architecture -eq 'win-arm64') { 'anycpu' } else { 'x64' }
        $rsp.Add('/platform:' + $platform); $rsp.Add('/optimize+'); $rsp.Add('/debug-')
        if ($Utf8 -or $Unicode) { $rsp.Add('/utf8output'); $rsp.Add('/define:PWX_UTF8_OUTPUT') }
        if ($NoOutput) { $rsp.Add('/define:PWX_NO_OUTPUT') }
        if ($gui) { $rsp.Add('/define:PWX_GUI') }
        if ($EncryptPayload) {
            $rsp.Add('/define:PWX_ENCRYPTED_PAYLOAD')
            $rsp.Add('/r:System.Security.dll')
            $rsp.Add('/resource:payload.enc,PwX.payload.enc')
        }
        else {
            $rsp.Add('/resource:payload.ps1,PwX.payload.ps1')
        }
        $rsp.Add('/out:out.exe')
        if ($iconFull) { Copy-Item -LiteralPath $iconFull -Destination (Join-Path $workDir 'icon.ico'); $rsp.Add('/win32icon:icon.ico') }
        if ($manifest) { $rsp.Add('/win32manifest:app.manifest') }
        $rsp.Add('Stub.cs'); $rsp.Add('AssemblyInfo.cs')
        [IO.File]::WriteAllText((Join-Path $workDir 'build.rsp'), ($rsp -join "`r`n"), $script:Utf8Bom)

        Write-Log 'csc.exe compiling...'
        $code = Invoke-Native $csc @('@build.rsp') $workDir
        if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $workDir 'out.exe'))) { Stop-Build 'PWX3103' "csc compilation failed (exit code $code). Details: $LogPath" }
        Copy-Item -LiteralPath (Join-Path $workDir 'out.exe') -Destination $Output -Force
        if ($Config) { New-AppConfig "$Output.config" }
    }

    # 8) Verify executable output
    if (-not (Test-Path -LiteralPath $finalExe)) { Stop-Build 'PWX4001' 'Output executable was not created.' }
    $fi = Get-Item -LiteralPath $finalExe
    $mz = [IO.File]::ReadAllBytes($finalExe)[0..1]
    if ($fi.Length -le 0 -or $mz[0] -ne 0x4D -or $mz[1] -ne 0x5A) { Stop-Build 'PWX4002' 'Output is not a valid Windows executable.' }

    # 9) Optional Authenticode code signing
    if ($CertificateThumbprint -or $CertificateFile) {
        Invoke-CodeSign $finalExe $CertificateThumbprint $CertificateFile $CertificatePassword $TimestampServer
    }

    $result.Success = $true
    $result.OutputPath = $finalExe
    $result.OutputSize = $fi.Length
    Write-Log ('SUCCESS: {0} ({1:N1} MB)' -f $finalExe, ($fi.Length / 1MB))
}
catch {
    if ($_.Exception.Message -ne 'PWX_BUILD_FAILED') { Add-Diag 'Error' 'PWX9000' ("Unexpected error: " + $_.Exception.Message) }
    Write-Log 'BUILD FAILED.' 'Error'
}
finally {
    if ($script:EnvSaved) {
        $env:DOTNET_CLI_UI_LANGUAGE = $script:EnvSaved.DOTNET_CLI_UI_LANGUAGE
        $env:VSLANG = $script:EnvSaved.VSLANG
    }
    if ($workDir -and (Test-Path -LiteralPath $workDir) -and -not $KeepTemp) {
        try { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction Stop } catch { Write-Log "Could not remove temp folder: $workDir" 'Warning' }
    }
    $sw.Stop()
    $result.Duration = $sw.Elapsed
    Write-Log ('Duration: {0:N1} s | Log: {1}' -f $sw.Elapsed.TotalSeconds, $LogPath)
}

[pscustomobject]$result
if (-not $result.Success) { exit 1 }
