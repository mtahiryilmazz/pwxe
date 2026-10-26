#Requires -Version 5.1
<#
.SYNOPSIS
    Unlist older pwxe versions on NuGet.org to retain only the latest 2 versions (1.7.0 & 1.6.4).
.PARAMETER NuGetApiKey
    NuGet.org API Key with unlist permissions.
#>
[CmdletBinding()]
param(
    [string]$NuGetApiKey
)

# Konsol cikti kodlamasini UTF-8 yap
try {
    chcp 65001 > $null
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "     pwxe - NuGet Eski Surumleri Listeden Kaldirma (Unlist)    " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

if (-not $NuGetApiKey) {
    if ($env:NUGET_API_KEY) {
        $NuGetApiKey = $env:NUGET_API_KEY
    } else {
        $NuGetApiKey = Read-Host "Lutfen NuGet.org API Anahtarinizi girin"
    }
}

if (-not $NuGetApiKey) {
    Write-Host "[HATA] NuGet API Anahtari girilmedi. Islem iptal edildi." -ForegroundColor Red
    exit 1
}

# Turkce klavye 'i' harfini noktasiz i (U+0131) yaparsa duzelt
$NuGetApiKey = $NuGetApiKey.Trim().Replace([char]0x0131, 'i').Replace([char]0x0130, 'I')

$olderVersions = @('1.6.0', '1.6.1', '1.6.2', '1.6.3', '1.6.4')
$protectedVersions = @('1.7.0', '1.7.1')

Write-Host "Korumaya alinan son 2 surum: $($protectedVersions -join ', ')" -ForegroundColor Green

$hasError = $false

foreach ($v in $olderVersions) {
    Write-Host "`n--> NuGet'ten kaldiriliyor (Unlist): pwxe $v..." -ForegroundColor Yellow
    dotnet nuget delete pwxe $v --source https://api.nuget.org/v3/index.json --api-key $NuGetApiKey --non-interactive
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] pwxe $v basariyla listeden gizlendi (unlisted)." -ForegroundColor Green
    } else {
        Write-Host "[UYARI] pwxe $v kaldirilamadi (Hata Kodu: $LASTEXITCODE)." -ForegroundColor Yellow
        $hasError = $true
    }
}

if ($hasError) {
    Write-Host @"

--------------------------------------------------------------------------------
[BILGI] NuGet 403 (Forbidden / Yetki) Hatasi Nedeni ve Cozumu:
1. NuGet.org uzerinde API Key olustururken varsayilan olarak sadece
   'Push new packages and package versions' secilidir.
2. Paket gizlemek icin su yetki gereklidir:
   - 'Unlist package' kutucugu isaretlenmelidir.
   - Glob pattern: 'pwxe*' veya '*' olmalidir.
   Ayar adresi: https://www.nuget.org/account/apikeys

ALTERNATIF (En Kolay Yol - 10 Saniye):
API Key ile ugrasmadan web arayuzunden tek tikla gizleyebilirsiniz:
1. https://www.nuget.org/packages/pwxe/manage adresine gidin.
2. Sol menuden 'Listing' (Listeleme) secenegine tiklayin.
3. 1.6.0, 1.6.1, 1.6.2, 1.6.3 surumlerinin yanindaki isareti kaldirip 'Save' butonuna basin.
--------------------------------------------------------------------------------
"@ -ForegroundColor Yellow
} else {
    Write-Host "`nIslem tamamlandi. Yalnizca 1.7.0 ve 1.6.4 surumleri listelenmektedir." -ForegroundColor Green
}
