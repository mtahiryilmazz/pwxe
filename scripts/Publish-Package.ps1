#Requires -Version 5.1
<#
.SYNOPSIS
    pwxe & PowerShell Module - NuGet & PSGallery Automated Packaging & Publishing Script.

.DESCRIPTION
    Bu betik pwxe modulunu ve paketini otomatik olarak:
    1. Dogrular (Test-ModuleManifest ve .nuspec surum senkronizasyonu).
    2. Paketler (nuget pack -> .nupkg).
    3. PowerShell Gallery (PSGallery) ve/veya NuGet.org uzerine yayinlar.

.PARAMETER Target
    Hedef depo: 'All' (varsayilan), 'NuGet' veya 'PSGallery'.

.PARAMETER NuGetApiKey
    NuGet.org API Anahtari. Belirtilmezse $env:NUGET_API_KEY veya konsol sorusu kullanilir.

.PARAMETER PSGalleryApiKey
    PowerShell Gallery API Anahtari. Belirtilmezse $env:PSGALLERY_API_KEY veya konsol sorusu kullanilir.

.PARAMETER DryRun
    Yayinlama komutlarini calistirmadan sadece paketleme ve dogrulama testlerini yapar (Simulasyon).

.PARAMETER SkipValidation
    Manifest ve surum eslesme kontrollerini atlar.

.PARAMETER SkipPack
    Yeniden paketleme yapmaz, var olan .nupkg paketlerini kullanir.

.PARAMETER ArtifactsDir
    Paketlerin (.nupkg) kaydedilecegi klasor (Varsayilan: ./artifacts).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('All', 'NuGet', 'PSGallery')]
    [string]$Target = 'All',

    [string]$NuGetApiKey,

    [string]$PSGalleryApiKey,

    [switch]$DryRun,

    [switch]$SkipValidation,

    [switch]$SkipPack,

    [string]$ArtifactsDir = 'artifacts'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 yerlesik SSL/TLS hatasi vermesin diye sistemde PowerShell 7 (pwsh) varsa otomatik devret
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd) {
        Write-Host "[BILGI] Windows PowerShell 5.1 algilandi. SSL/TLS sorunlarini onlemek icin PowerShell 7 (pwsh) ile calistiriliyor...`n" -ForegroundColor Cyan
        $cliArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        foreach ($k in $PSBoundParameters.Keys) {
            $val = $PSBoundParameters[$k]
            # API anahtarlari komut satirinda gorunmesin: ortam degiskeni olarak cocuk surece devredilir
            if ($k -eq 'NuGetApiKey') { $env:NUGET_API_KEY = "$val"; continue }
            if ($k -eq 'PSGalleryApiKey') { $env:PSGALLERY_API_KEY = "$val"; continue }
            if ($val -is [switch]) {
                if ($val.IsPresent) { $cliArgs += "-$k" }
            } else {
                $cliArgs += "-$k"
                $cliArgs += "$val"
            }
        }
        & $pwshCmd.Source @cliArgs
        exit $LASTEXITCODE
    }
}

# Konsol cikti kodlamasini ayarla
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# PSGallery ve modern HTTPS API'leri icin TLS 1.2'yi zorunlu kil
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
} catch { }

# ------------------------------------------------------------- Yollar & Dizinler
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ManifestPath = Join-Path $RepoRoot 'pwxe.psd1'
$NuspecPath = Join-Path $RepoRoot 'pwxe.nuspec'
$ArtifactsFullPath = Join-Path $RepoRoot $ArtifactsDir
$NugetExePath = Join-Path $RepoRoot 'nuget.exe'

# ------------------------------------------------------------- Yardimci Fonksiyonlar
function Write-Color {
    param([string]$Text, [ConsoleColor]$Color = [ConsoleColor]::White)
    Write-Host $Text -ForegroundColor $Color
}

function Write-Step {
    param([string]$Text)
    Write-Color "`n====> $Text" Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Color "[OK] $Text" Green
}

function Write-Warn {
    param([string]$Text)
    Write-Color "[UYARI] $Text" Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Color "[HATA] $Text" Red
}

function Normalize-ApiKey {
    param([string]$Key)
    if ([string]::IsNullOrWhiteSpace($Key)) { return '' }
    # Turkce klavye 'i' harfini noktasiz i (U+0131) yaparsa duzelt
    $clean = $Key.Trim()
    $clean = $clean.Replace([char]0x0131, 'i').Replace([char]0x0130, 'I')
    return $clean
}

function Read-ApiKey {
    param([string]$PromptText)
    Write-Host "$PromptText" -ForegroundColor Yellow
    # Windows PowerShell 5.1 & PowerShell 7+ tam uyumlu guvenli girdi
    $secure = Read-Host -Prompt "Key" -AsSecureString
    if ($secure -and $secure.Length -gt 0) {
        $raw = (New-Object System.Net.NetworkCredential("", $secure)).Password
        return (Normalize-ApiKey $raw)
    }
    return ""
}

# ------------------------------------------------------------- Baslik Banner
Write-Color "================================================================" Cyan
Write-Color "      PwX Package & Release Automation (NuGet + PSGallery)      " Cyan
Write-Color "================================================================" Cyan
Write-Host "Repo Dizini  : $RepoRoot"
Write-Host "Hedef Depo   : $Target"
Write-Host "DryRun Modu  : $(if ($DryRun) { 'EVET (Simulasyon)' } else { 'HAYIR (Canli Yayin)' })"
Write-Host "Tarih & Saat : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ------------------------------------------------------------- 1. Dogrulama ve Surum Kontrolleri
$ModuleVersion = ''
$NuspecVersion = ''

if (-not $SkipValidation) {
    Write-Step "1. Modul ve Manifest Dogrulaniyor..."

    if (-not (Test-Path $ManifestPath)) {
        throw "Modul manifesti bulunamadi: $ManifestPath"
    }

    try {
        $manifestTest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        $ModuleVersion = $manifestTest.Version.ToString()
        Write-Success "pwxe.psd1 gecerli. Surum: $ModuleVersion"
    }
    catch {
        throw "pwxe.psd1 dogrulamasi basarisiz: $_"
    }

    if (Test-Path $NuspecPath) {
        try {
            [xml]$nuspecXml = Get-Content -Path $NuspecPath -Raw
            $NuspecVersion = $nuspecXml.package.metadata.version
            Write-Success "pwxe.nuspec bulundu. Surum: $NuspecVersion"

            if ($ModuleVersion -ne $NuspecVersion) {
                Write-Warn "SURUM UYUMSUZLUGU: pwxe.psd1 ($ModuleVersion) ile pwxe.nuspec ($NuspecVersion) surumleri eslesmiyor!"
                $choice = Read-Host "Devam etmek istiyor musunuz? (E/H)"
                if ($choice -notmatch '^[eEyY]') {
                    throw "Islem surum uyumsuzlugu sebebiyle iptal edildi."
                }
            }
        }
        catch {
            Write-Warn "pwxe.nuspec ayristirilirken hata olustu: $_"
        }
    } else {
        Write-Warn "pwxe.nuspec bulunamadi. NuGet paketlemesi icin nuspec onerilir."
    }
}

if (-not $ModuleVersion -and (Test-Path $ManifestPath)) {
    try { $ModuleVersion = [string](Import-PowerShellDataFile -Path $ManifestPath).ModuleVersion } catch { }
}

# ------------------------------------------------------------- 2. API Key Yonetimi
Write-Step "2. API Anahtarlari Kontrol Ediliyor..."

# NuGet API Key
$needNuGet = ($Target -in @('All', 'NuGet'))
if ($needNuGet) {
    if (-not $NuGetApiKey) {
        if ($env:NUGET_API_KEY) {
            $NuGetApiKey = Normalize-ApiKey $env:NUGET_API_KEY
            Write-Success "NuGet API Key ortam degiskeninden (\$env:NUGET_API_KEY) alindi."
        } elseif (-not $DryRun) {
            $inputKey = Read-ApiKey "NuGet.org API Anahtarini girin (Atlamak icin Bos Birakip Enter'a basin)"
            if ([string]::IsNullOrWhiteSpace($inputKey)) {
                Write-Warn "NuGet API Key girilmedi. NuGet yayini atlanacak."
            } else {
                $NuGetApiKey = $inputKey
                Write-Success "NuGet API Key alindi."
            }
        }
    } else {
        $NuGetApiKey = Normalize-ApiKey $NuGetApiKey
        Write-Success "NuGet API Key parametre olarak saglandi."
    }
}

# PSGallery API Key
$needPSGallery = ($Target -in @('All', 'PSGallery'))
if ($needPSGallery) {
    if (-not $PSGalleryApiKey) {
        if ($env:PSGALLERY_API_KEY) {
            $PSGalleryApiKey = Normalize-ApiKey $env:PSGALLERY_API_KEY
            Write-Success "PSGallery API Key ortam degiskeninden (\$env:PSGALLERY_API_KEY) alindi."
        } elseif (-not $DryRun) {
            $inputKey = Read-ApiKey "PowerShell Gallery API Anahtarini girin (Atlamak icin Bos Birakip Enter'a basin)"
            if ([string]::IsNullOrWhiteSpace($inputKey)) {
                Write-Warn "PSGallery API Key girilmedi. PSGallery yayini atlanacak."
            } else {
                $PSGalleryApiKey = $inputKey
                Write-Success "PSGallery API Key alindi."
            }
        }
    } else {
        $PSGalleryApiKey = Normalize-ApiKey $PSGalleryApiKey
        Write-Success "PSGallery API Key parametre olarak saglandi."
    }
}

# ------------------------------------------------------------- 3. Paketleme (.nupkg Olusturma)
if (-not (Test-Path $ArtifactsFullPath)) {
    New-Item -ItemType Directory -Path $ArtifactsFullPath -Force | Out-Null
}

$PackageFile = $null

# PSGallery yayini .nupkg gerektirmez (Publish-PSResource/Publish-Module kendi paketini uretir).
if ($needNuGet -and -not $SkipPack) {
    Write-Step "3. NuGet Paketi (.nupkg) Olusturuluyor..."

    $packerCmd = $null
    if (Test-Path $NugetExePath) {
        $packerCmd = $NugetExePath
    } elseif (Get-Command nuget -ErrorAction SilentlyContinue) {
        $packerCmd = "nuget"
    } else {
        Write-Host "nuget.exe bulunamadi, indiriliyor..."
        Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $NugetExePath -UseBasicParsing
        $packerCmd = $NugetExePath
    }

    if ($packerCmd) {
        Write-Host "Paketleyici: $packerCmd"
        & $packerCmd pack $NuspecPath -OutputDirectory $ArtifactsFullPath -NonInteractive
        if ($LASTEXITCODE -ne 0) {
            throw "Paket olusturma basarisiz oldu (Hata Kodu: $LASTEXITCODE)!"
        }
    } else {
        throw "nuget.exe ne repo dizininde ne de PATH'te bulunamadi."
    }
}

# En guncel nupkg dosyasini bul
if ($needNuGet) {
    $packages = @()
    if ($ModuleVersion) {
        $packages = @(Get-ChildItem -Path $ArtifactsFullPath -Filter "pwxe.$ModuleVersion.nupkg" -ErrorAction SilentlyContinue)
    }
    if ($packages.Count -eq 0) {
        $packages = @(Get-ChildItem -Path $ArtifactsFullPath -Filter "*.nupkg" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    }
    if ($packages.Count -gt 0) {
        $PackageFile = $packages[0]
        Write-Success "Kullanilacak paket: $($PackageFile.FullName)"
    } else {
        throw "Yayinlanacak .nupkg paketi bulunamadi ($ArtifactsFullPath)!"
    }
}

# ------------------------------------------------------------- 4. PSGallery Yayini
$psGalleryStatus = "Atlandi"

if ($needPSGallery) {
    Write-Step "4. PowerShell Gallery (PSGallery) Yayini..."

    if (-not $PSGalleryApiKey -and -not $DryRun) {
        Write-Warn "PSGallery API Key mevcut degil, yayin atlaniyor."
        $psGalleryStatus = "Key Yok (Atlandi)"
    } else {
        $hasPSResource = [bool](Get-Command Publish-PSResource -ErrorAction SilentlyContinue)
        $hasPublishModule = [bool](Get-Command Publish-Module -ErrorAction SilentlyContinue)

        if ($DryRun) {
            $toolName = if ($hasPSResource) { 'Publish-PSResource' } else { 'Publish-Module' }
            Write-Color "[DRY-RUN] $toolName -Path <staging\pwxe> -ApiKey [GIZLI] (Repository: PSGallery)" Magenta
            $psGalleryStatus = "DryRun (Basarili)"
        } else {
            # Modul klasoru adi modul adiyla ('pwxe') ayni olmali; bu yuzden temiz bir staging dizini kullanilir.
            $stageParent = Join-Path ([System.IO.Path]::GetTempPath()) "pwxe_stage_$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
            $stageDir = Join-Path $stageParent 'pwxe'
            $savedLang = @{ D = $env:DOTNET_CLI_UI_LANGUAGE; V = $env:VSLANG }
            $savedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            $savedUICulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
            try {
                # PowerShellGet ve NuGet parserlarinda Turkce i/I hatasini onlemek icin kulturu Invariant yap
                $inv = [System.Globalization.CultureInfo]::InvariantCulture
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $inv
                [System.Threading.Thread]::CurrentThread.CurrentUICulture = $inv
                $env:DOTNET_CLI_UI_LANGUAGE = 'en'
                $env:VSLANG = '1033'

                Write-Host "Modul staging dizini hazirlaniyor: $stageDir..."
                New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
                Copy-Item (Join-Path $RepoRoot 'pwxe.psd1') -Destination $stageDir
                Copy-Item (Join-Path $RepoRoot 'pwxe.psm1') -Destination $stageDir
                Copy-Item (Join-Path $RepoRoot 'README.md') -Destination $stageDir -ErrorAction SilentlyContinue
                Copy-Item (Join-Path $RepoRoot 'LICENSE') -Destination $stageDir -ErrorAction SilentlyContinue
                if (Test-Path (Join-Path $RepoRoot 'scripts')) {
                    Copy-Item (Join-Path $RepoRoot 'scripts') -Destination $stageDir -Recurse
                }
                if (Test-Path (Join-Path $RepoRoot 'src')) {
                    Copy-Item (Join-Path $RepoRoot 'src') -Destination $stageDir -Recurse
                }
                # Yerel derlemelerden kalan bin/obj klasorlerini pakete alma
                Get-ChildItem -Path $stageDir -Include bin, obj -Recurse -Directory -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

                # Staging'deki manifesti son kez dogrula
                $null = Test-ModuleManifest -Path (Join-Path $stageDir 'pwxe.psd1') -ErrorAction Stop

                $published = $false
                $lastErr = $null

                # 1. Oncelik: Publish-PSResource (Modern PSResourceGet)
                if ($hasPSResource) {
                    try {
                        Write-Host "PSGallery'ye yukleniyor (Publish-PSResource): $stageDir"
                        Publish-PSResource -Path $stageDir -Repository PSGallery -ApiKey $PSGalleryApiKey -Verbose -ErrorAction Stop
                        $published = $true
                    }
                    catch {
                        $lastErr = $_
                        Write-Warn "Publish-PSResource basarisiz oldu: $($_.Exception.Message)"
                        if ($hasPublishModule) {
                            Write-Host "Alternatif olarak klasik 'Publish-Module' (PowerShellGet) deneniyor..." -ForegroundColor Yellow
                        }
                    }
                }

                # 2. Oncelik / Fallback: Publish-Module (Klasik PowerShellGet)
                if (-not $published -and $hasPublishModule) {
                    try {
                        Write-Host "PSGallery'ye yukleniyor (Publish-Module): $stageDir"
                        Publish-Module -Path $stageDir -NuGetApiKey $PSGalleryApiKey -Verbose -ErrorAction Stop
                        $published = $true
                    }
                    catch {
                        $lastErr = $_
                        throw $lastErr
                    }
                } elseif (-not $published -and $lastErr) {
                    throw $lastErr
                }

                Write-Success "PowerShell Gallery'ye basariyla yayinlandi!"
                $psGalleryStatus = "Basarili"
            }
            catch {
                $errText = $_.Exception.Message
                Write-Err "PSGallery yayini basarisiz: $errText"
                Write-Host $_.Exception.ToString()
                if ($errText -match '403|Forbidden|API key|ApiKey|permission|izin') {
                    Write-Warn @"
--------------------------------------------------------------------------------
PSGallery 403 (Forbidden / Yetki) Hatasi Cozum Rehberi:
1. NuGet.org API Key ile PSGallery API Key AYNI DEGILDIR!
   - PowerShell Gallery icin ayri bir hesap ve API Key gerekir: https://www.powershellgallery.com/account/apikeys
2. API Key Yetkisi (Scope):
   - 'pwxe' paketi PSGallery'de henuz HIC YAYINLANMADI (yeni paket).
   - API Key olustururken 'Push new packages and package versions' secilmelidir!
   - 'Push new package versions only' seciliyse yeni paket yuklenemez (403 verir).
3. Glob Pattern:
   - Glob pattern alani '*' veya 'pwxe*' olmalidir.
--------------------------------------------------------------------------------
"@
                }
                $psGalleryStatus = "Hata: $errText"
            }
            finally {
                $env:DOTNET_CLI_UI_LANGUAGE = $savedLang.D; $env:VSLANG = $savedLang.V
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture
                [System.Threading.Thread]::CurrentThread.CurrentUICulture = $savedUICulture
                Remove-Item -Path $stageParent -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# ------------------------------------------------------------- 5. NuGet Yayini (dotnet nuget push)
$nugetStatus = "Atlandi"

if ($needNuGet) {
    Write-Step "5. NuGet.org Yayini..."

    if (-not $PackageFile) {
        Write-Warn "Yayinlanacak .nupkg dosyasi bulunamadi."
        $nugetStatus = "Paket Yok (Atlandi)"
    } elseif (-not $NuGetApiKey -and -not $DryRun) {
        Write-Warn "NuGet API Key mevcut degil, yayin atlaniyor."
        $nugetStatus = "Key Yok (Atlandi)"
    } else {
        if ($DryRun) {
            Write-Color "[DRY-RUN] dotnet nuget push $($PackageFile.FullName) --source https://api.nuget.org/v3/index.json --api-key [GIZLI]" Magenta
            $nugetStatus = "DryRun (Basarili)"
        } else {
            try {
                Write-Host "NuGet.org'a yukleniyor ($($PackageFile.Name))..."
                $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
                if ($dotnetCmd) {
                    dotnet nuget push $PackageFile.FullName --source https://api.nuget.org/v3/index.json --api-key $NuGetApiKey
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "NuGet.org'a basariyla yayinlandi!"
                        $nugetStatus = "Basarili"
                    } else {
                        Write-Err "dotnet nuget push basarisiz (Kod: $LASTEXITCODE)!"
                        $nugetStatus = "Basarisiz (Kod $LASTEXITCODE)"
                    }
                } elseif (Test-Path $NugetExePath) {
                    & $NugetExePath push $PackageFile.FullName $NuGetApiKey -Source https://api.nuget.org/v3/index.json
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "nuget.exe ile NuGet.org'a basariyla yayinlandi!"
                        $nugetStatus = "Basarili"
                    } else {
                        Write-Err "nuget.exe push basarisiz (Kod: $LASTEXITCODE)!"
                        $nugetStatus = "Basarisiz (Kod $LASTEXITCODE)"
                    }
                } else {
                    throw "dotnet CLI veya nuget.exe bulunamadi!"
                }
            }
            catch {
                Write-Err "NuGet yayini sirasinda hata: $_"
                $nugetStatus = "Hata: $_"
            }
        }
    }
}

# ------------------------------------------------------------- 6. Ozet Rapor
Write-Step "6. Yayin Ozeti"
$summary = [PSCustomObject]@{
    'Modul Surumu' = $ModuleVersion
    'Paket Dosyasi' = if ($PackageFile) { $PackageFile.Name } else { 'Yok' }
    'PSGallery'     = $psGalleryStatus
    'NuGet.org'     = $nugetStatus
}
$summary | Format-List

$failed = ($psGalleryStatus -match '^(Hata|Basarisiz)') -or ($nugetStatus -match '^(Hata|Basarisiz)')
if ($failed) {
    Write-Color "`nIslem HATALARLA tamamlandi." Red
    exit 1
}
Write-Color "`nIslem Tamamlandi." Green