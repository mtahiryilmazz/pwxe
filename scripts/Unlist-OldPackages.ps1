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

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== pwxe NuGet Eski Sürümleri Listeden Kaldırma (Unlist) ===" -ForegroundColor Cyan

if (-not $NuGetApiKey) {
    if ($env:NUGET_API_KEY) {
        $NuGetApiKey = $env:NUGET_API_KEY
    } else {
        $NuGetApiKey = Read-Host "Lütfen NuGet.org API Anahtarınızı giriniz"
    }
}

if (-not $NuGetApiKey) {
    Write-Host "[HATA] NuGet API Anahtarı girilmedi. İşlem iptal edildi." -ForegroundColor Red
    exit 1
}

$olderVersions = @('1.6.0', '1.6.1', '1.6.2', '1.6.3')
$protectedVersions = @('1.6.4', '1.7.0')

Write-Host "Korumaya alınan son 2 sürüm: $($protectedVersions -join ', ')" -ForegroundColor Green

foreach ($v in $olderVersions) {
    Write-Host "`n--> NuGet'ten kaldırılıyor (Unlist): pwxe $v..." -ForegroundColor Yellow
    dotnet nuget delete pwxe $v --source https://api.nuget.org/v3/index.json --api-key $NuGetApiKey --non-interactive
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] pwxe $v başarıyla listeden gizlendi (unlisted)." -ForegroundColor Green
    } else {
        Write-Host "[UYARI] pwxe $v kaldırılamadı (zaten gizlenmiş veya hata kodu: $LASTEXITCODE)." -ForegroundColor Yellow
    }
}

Write-Host "`nİşlem tamamlandı. Yalnızca 1.7.0 ve 1.6.4 sürümleri listelenmektedir." -ForegroundColor Green
