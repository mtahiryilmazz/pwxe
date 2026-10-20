#Requires -Version 5.1
<#
.SYNOPSIS
    pwxe & PowerShell Module - NuGet & PSGallery Automated Packaging & Publishing Script.

.DESCRIPTION
    Bu betik pwxe modülünü ve paketini otomatik olarak:
    1. Doğrular (Test-ModuleManifest ve .nuspec sürüm senkronizasyonu).
    2. Paketler (nuget pack -> .nupkg).
    3. PowerShell Gallery (PSGallery) ve/veya NuGet.org üzerine yayınlar.

    API Key'ler parametre olarak verilebilir, ortam değişkenlerinden ($env:NUGET_API_KEY, $env:PSGALLERY_API_KEY)
    okunabilir ya da betik çalıştırıldığında interaktif ve güvenli olarak kullanıcıdan istenir.

.PARAMETER Target
    Hedef depo: 'All' (varsayılan), 'NuGet' veya 'PSGallery'.

.PARAMETER NuGetApiKey
    NuGet.org API Anahtarı. Belirtilmezse $env:NUGET_API_KEY veya konsol sorusu kullanılır.

.PARAMETER PSGalleryApiKey
    PowerShell Gallery API Anahtarı. Belirtilmezse $env:PSGALLERY_API_KEY veya konsol sorusu kullanılır.

.PARAMETER DryRun
    Yayınlama komutlarını çalıştırmadan sadece paketleme ve doğrulama testlerini yapar (Simülasyon).

.PARAMETER SkipValidation
    Manifest ve sürüm eşleşme kontrollerini atlar.

.PARAMETER SkipPack
    Yeniden paketleme yapmaz, var olan .nupkg paketlerini kullanır.

.PARAMETER ArtifactsDir
    Paketlerin (.nupkg) kaydedileceği klasör (Varsayılan: ./artifacts).

.EXAMPLE
    .\scripts\Publish-Package.ps1
    # İnteraktif mod: Eksik API keyleri sorar, test eder, paketler ve her iki depoya yayınlar.

.EXAMPLE
    .\scripts\Publish-Package.ps1 -DryRun
    # Test/Simülasyon modu: Depolara yükleme yapmadan paketleme ve kontrolleri doğrular.

.EXAMPLE
    .\scripts\Publish-Package.ps1 -Target NuGet -NuGetApiKey "oy2..."
    # Yalnızca NuGet.org'a doğrudan yayınlar.

.EXAMPLE
    .\scripts\Publish-Package.ps1 -Target PSGallery -PSGalleryApiKey "pg..."
    # Yalnızca PSGallery'ye yayınlar.
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

# ------------------------------------------------------------- Yollar & Dizinler
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ManifestPath = Join-Path $RepoRoot 'pwxe.psd1'
$NuspecPath = Join-Path $RepoRoot 'pwxe.nuspec'
$ArtifactsFullPath = Join-Path $RepoRoot $ArtifactsDir
$NugetExePath = Join-Path $RepoRoot 'nuget.exe'

# ------------------------------------------------------------- Yardımcı Fonksiyonlar
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

# ------------------------------------------------------------- Başlık Banner
Write-Color "================================================================" Cyan
Write-Color "      PwX Package & Release Automation (NuGet + PSGallery)      " Cyan
Write-Color "================================================================" Cyan
Write-Host "Repo Dizini  : $RepoRoot"
Write-Host "Hedef Depo   : $Target"
Write-Host "DryRun Modu  : $(if ($DryRun) { 'EVET (Simülasyon)' } else { 'HAYIR (Canlı Yayın)' })"
Write-Host "Tarih & Saat : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ------------------------------------------------------------- 1. Doğrulama ve Sürüm Kontrolleri
$ModuleVersion = ''
$NuspecVersion = ''

if (-not $SkipValidation) {
    Write-Step "1. Modül ve Manifest Doğrulanıyor..."

    if (-not (Test-Path $ManifestPath)) {
        throw "Modül manifesti bulunamadı: $ManifestPath"
    }

    try {
        $manifestTest = Test-ModuleManifest -Path $ManifestPath -ErrorAction Stop
        $ModuleVersion = $manifestTest.Version.ToString()
        Write-Success "pwxe.psd1 geçerli. Sürüm: $ModuleVersion"
    }
    catch {
        throw "pwxe.psd1 doğrulaması başarısız: $_"
    }

    if (Test-Path $NuspecPath) {
        try {
            [xml]$nuspecXml = Get-Content -Path $NuspecPath -Raw
            $NuspecVersion = $nuspecXml.package.metadata.version
            Write-Success "pwxe.nuspec bulundu. Sürüm: $NuspecVersion"

            if ($ModuleVersion -ne $NuspecVersion) {
                Write-Warn "SÜRÜM UYUMSUZLUĞU: pwxe.psd1 ($ModuleVersion) ile pwxe.nuspec ($NuspecVersion) sürümleri eşleşmiyor!"
                $choice = Read-Host "Devam etmek istiyor musunuz? (E/H)"
                if ($choice -notmatch '^[eEyY]') {
                    throw "İşlem sürüm uyumsuzluğu sebebiyle iptal edildi."
                }
            }
        }
        catch {
            Write-Warn "pwxe.nuspec ayrıştırılırken hata oluştu: $_"
        }
    } else {
        Write-Warn "pwxe.nuspec bulunamadı. NuGet paketlemesi için nuspec önerilir."
    }
}

# ------------------------------------------------------------- 2. API Key Yönetimi
Write-Step "2. API Anahtarları Kontrol Ediliyor..."

# NuGet API Key
$needNuGet = ($Target -in @('All', 'NuGet'))
if ($needNuGet) {
    if (-not $NuGetApiKey) {
        if ($env:NUGET_API_KEY) {
            $NuGetApiKey = $env:NUGET_API_KEY
            Write-Success "NuGet API Key ortam değişkeninden (\$env:NUGET_API_KEY) alındı."
        } elseif (-not $DryRun) {
            $inputKey = Read-Host -Prompt "NuGet.org API Anahtarını girin (Atlamak için Boş Bırakın)" -MaskInput
            if ([string]::IsNullOrWhiteSpace($inputKey)) {
                Write-Warn "NuGet API Key girilmedi. NuGet yayını atlanacak."
            } else {
                $NuGetApiKey = $inputKey
                Write-Success "NuGet API Key alındı."
            }
        }
    } else {
        Write-Success "NuGet API Key parametre olarak sağlandı."
    }
}

# PSGallery API Key
$needPSGallery = ($Target -in @('All', 'PSGallery'))
if ($needPSGallery) {
    if (-not $PSGalleryApiKey) {
        if ($env:PSGALLERY_API_KEY) {
            $PSGalleryApiKey = $env:PSGALLERY_API_KEY
            Write-Success "PSGallery API Key ortam değişkeninden (\$env:PSGALLERY_API_KEY) alındı."
        } elseif (-not $DryRun) {
            $inputKey = Read-Host -Prompt "PowerShell Gallery API Anahtarını girin (Atlamak için Boş Bırakın)" -MaskInput
            if ([string]::IsNullOrWhiteSpace($inputKey)) {
                Write-Warn "PSGallery API Key girilmedi. PSGallery yayını atlanacak."
            } else {
                $PSGalleryApiKey = $inputKey
                Write-Success "PSGallery API Key alındı."
            }
        }
    } else {
        Write-Success "PSGallery API Key parametre olarak sağlandı."
    }
}

# ------------------------------------------------------------- 3. Paketleme (.nupkg Oluşturma)
if (-not (Test-Path $ArtifactsFullPath)) {
    New-Item -ItemType Directory -Path $ArtifactsFullPath -Force | Out-Null
}

$PackageFile = $null

if (-not $SkipPack) {
    Write-Step "3. NuGet Paketi (.nupkg) Oluşturuluyor..."

    # nuget.exe veya dotnet belirleme
    $packerCmd = $null
    if (Test-Path $NugetExePath) {
        $packerCmd = $NugetExePath
    } elseif (Get-Command nuget -ErrorAction SilentlyContinue) {
        $packerCmd = "nuget"
    }

    if ($packerCmd) {
        Write-Host "Paketleyici: $packerCmd"
        & $packerCmd pack $NuspecPath -OutputDirectory $ArtifactsFullPath
        if ($LASTEXITCODE -ne 0) {
            throw "Paket oluşturma başarısız oldu (Hata Kodu: $LASTEXITCODE)!"
        }
    } else {
        throw "nuget.exe ne repo dizininde ne de PATH'te bulunamadı. Lütfen nuget.exe sağlayın."
    }
}

# En güncel nupkg dosyasını bul
$packages = Get-ChildItem -Path $ArtifactsFullPath -Filter "*.nupkg" | Sort-Object LastWriteTime -Descending
if ($packages) {
    $PackageFile = $packages[0]
    Write-Success "Kullanılacak paket: $($PackageFile.FullName)"
} else {
    if ($needNuGet) {
        throw "Yayınlanacak .nupkg paketi bulunamadı ($ArtifactsFullPath)!"
    }
}

# ------------------------------------------------------------- 4. PSGallery Yayını (Publish-Module)
$psGalleryStatus = "Atlandı"

if ($needPSGallery) {
    Write-Step "4. PowerShell Gallery (PSGallery) Yayını..."

    if (-not $PSGalleryApiKey -and -not $DryRun) {
        Write-Warn "PSGallery API Key mevcut değil, yayın atlanıyor."
        $psGalleryStatus = "Key Yok (Atlandı)"
    } else {
        if ($DryRun) {
            Write-Color "[DRY-RUN] Publish-Module -Path `"$RepoRoot`" -NuGetApiKey `"[GIZLI]`" -WhatIf" Magenta
            $psGalleryStatus = "DryRun (Başarılı)"
        } else {
            try {
                Write-Host "PSGallery'ye yükleniyor ($RepoRoot)..."
                Publish-Module -Path $RepoRoot -NuGetApiKey $PSGalleryApiKey -Verbose -ErrorAction Stop
                Write-Success "PowerShell Gallery'ye başarıyla yayınlandı!"
                $psGalleryStatus = "Başarılı"
            }
            catch {
                Write-Err "PSGallery yayını sırasında hata: $_"
                $psGalleryStatus = "Hata: $_"
            }
        }
    }
}

# ------------------------------------------------------------- 5. NuGet Yayını (dotnet nuget push)
$nugetStatus = "Atlandı"

if ($needNuGet) {
    Write-Step "5. NuGet.org Yayını..."

    if (-not $PackageFile) {
        Write-Warn "Yayınlanacak .nupkg dosyası bulunamadı."
        $nugetStatus = "Paket Yok (Atlandı)"
    } elseif (-not $NuGetApiKey -and -not $DryRun) {
        Write-Warn "NuGet API Key mevcut değil, yayın atlanıyor."
        $nugetStatus = "Key Yok (Atlandı)"
    } else {
        if ($DryRun) {
            Write-Color "[DRY-RUN] dotnet nuget push $($PackageFile.FullName) --source https://api.nuget.org/v3/index.json --skip-duplicate" Magenta
            $nugetStatus = "DryRun (Başarılı)"
        } else {
            try {
                Write-Host "NuGet.org'a yükleniyor ($($PackageFile.Name))..."
                $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
                if ($dotnetCmd) {
                    dotnet nuget push $PackageFile.FullName --source https://api.nuget.org/v3/index.json --api-key $NuGetApiKey --skip-duplicate
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "NuGet.org'a başarıyla yayınlandı!"
                        $nugetStatus = "Başarılı"
                    } else {
                        Write-Err "dotnet nuget push başarısız (Kod: $LASTEXITCODE)!"
                        $nugetStatus = "Başarısız (Kod $LASTEXITCODE)"
                    }
                } elseif (Test-Path $NugetExePath) {
                    & $NugetExePath push $PackageFile.FullName $NuGetApiKey -Source https://api.nuget.org/v3/index.json -SkipDuplicate
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "nuget.exe ile NuGet.org'a başarıyla yayınlandı!"
                        $nugetStatus = "Başarılı"
                    } else {
                        Write-Err "nuget.exe push başarısız (Kod: $LASTEXITCODE)!"
                        $nugetStatus = "Başarısız (Kod $LASTEXITCODE)"
                    }
                } else {
                    throw "dotnet CLI veya nuget.exe bulunamadı!"
                }
            }
            catch {
                Write-Err "NuGet yayını sırasında hata: $_"
                $nugetStatus = "Hata: $_"
            }
        }
    }
}

# ------------------------------------------------------------- 6. Özet Rapor
Write-Step "6. Yayın Özeti"
$summary = [PSCustomObject]@{
    'Modül Sürümü' = $ModuleVersion
    'Paket Dosyası' = if ($PackageFile) { $PackageFile.Name } else { 'Yok' }
    'PSGallery'     = $psGalleryStatus
    'NuGet.org'     = $nugetStatus
}
$summary | Format-List

Write-Color "`nİşlem tamamlandı." Green
