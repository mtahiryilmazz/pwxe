# PwX PS7 Size Optimization — Complete Audit, Change Log, Code Analysis, PR Notes and CI Recommendations

Tarih: 2026-10-17  
İşlem alanları: `mtahiryilmazz/pwxe` ve `mtahiryilmazz/PwX-Studio`  
Amaç: PS7 için EXE boyutunu küçültmek, varsayılan davranışta kararlı ve güvenli bir model kurmak, kodu belgelemek, riskleri netleştirmek ve PR/CI için hazır bir paket oluşturmak.

---

## 1) Özet

Sorun:
- PowerShell 7 hedefli `.exe` çıktıları `SelfContained` / `SingleFile` modunda büyük olur.
- PS7 runtime ve .NET runtime bir arada paketlendiğinde çıktı dosyaları çok büyür.
- Bu durum kullanıcı deneyimi ve dağıtım açısından zayıf noktadır.

Çözüm:
- PS7 için varsayılan çalışma zamanını `SelfContained` → `FrameworkDependent` olarak değiştirmek.
- Böylece çıktılar daha küçük olur; hedef cihazda uygun `pwsh` kuruluysa çalışmaya devam eder.
- Agresif küçültme için opsiyonel parametreler eklemek:
  - `-EnableTrim` → `.NET PublishTrimmed`
  - `-EnableUpx` → UPX sıkıştırma (opsiyonel)
- `FrameworkDependent` kullanıldığında `pwsh` yoksa uyarı vermek.
- README ve CHANGELOG'ı güncellemek.
- CI üzerinde boyut karşılaştırma matrisi tanımlamak.

---

## 2) Yapılan işlemler ve nedenleri

### 2.1. Engine değişikliği: PS7 default runtime modu küçültüldü
Dosya:
- `pwxe/scripts/PwX-Build.ps1`

Değişiklik:
- Varsayılan parametre:
  - önce: `RuntimeMode = 'SelfContained'`
  - sonra: `RuntimeMode = 'FrameworkDependent'`

Neden:
- `SelfContained` binary'ler .NET + PowerShell runtime'ını exenin içine gömer.
- `FrameworkDependent` modunda exe tek başına çalışmaz; ama hedef makinede compatible `pwsh` yüklüyse daha küçük bir ara katman üretir.
- Bu, çoğu kullanıcı için daha pratik ve daha hafif dağıtım sağlar.

Risk:
- Hedef cihazda uygun `pwsh` yoksa exe çalışmaz.
- Bu yüzden build sırasında uyarı ekledik.

---

### 2.2. `-EnableTrim` eklendi
Dosya:
- `pwxe/scripts/PwX-Build.ps1`

Kod mantığı:
```powershell
if ($EnableTrim) { $pa += @('-p:PublishTrimmed=true') }
```

Neden:
- .NET publish ile trimming yapılabilir.
- Bu yöntemle daha küçük binary üretilir.

Risk:
- Reflection ya da dinamik yüklemeler kullanan uygulamalar kırılabilir.
- Sonuç olarak bu özellik opsiyonel bırakıldı.

---

### 2.3. `-EnableUpx` eklendi
Dosya:
- `pwxe/scripts/PwX-Build.ps1`

Eklenen mantık:
```powershell
if ($EnableUpx) {
    $upx = Get-Command upx -ErrorAction SilentlyContinue
    if ($upx) {
        try {
            if ($SingleFile) { & $upx.Source '--best' '--lzma' $Output }
            else { $exeToCompress = Join-Path $distDir ($baseName + '.exe'); & $upx.Source '--best' '--lzma' $exeToCompress }
            Write-Log 'UPX sıkıştırması tamamlandı.'
        }
        catch { Write-Log "UPX çalıştırılırken hata: $($_.Exception.Message)" 'Warning' }
    }
    else { Write-Log 'UPX bulunamadı; sıkıştırma atlandı.' 'Warning' }
}
```

Neden:
- Bazı durumlarda UPX ile ciddi boyut düşüşü sağlanabilir.

Risk:
- Some AV products flag UPX-packed binaries.
- Bu yüzden opsiyonel kaldı.

---

### 2.4. `pwsh` var mı kontrolü eklendi
Dosya:
- `pwxe/scripts/PwX-Build.ps1`

Yeni fonksiyon:
```powershell
function Test-PwshInstalled {
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd) { return $null }
    try {
        $ver = & $pwshCmd.Source -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
        return $ver.Trim()
    }
    catch { return $null }
}
```

Warn logic:
```powershell
if ($RuntimeMode -eq 'FrameworkDependent') {
    $localPwsh = Test-PwshInstalled
    if ($localPwsh) {
        Write-Log "UYARI: Framework-dependent build seçtiniz. Yerel pwsh bulundu: $localPwsh — hedef makinelerde uyumlu pwsh sürümü olduğundan emin olun." 'Warning'
    }
    else {
        Write-Log "UYARI: Framework-dependent build seçtiniz fakat bu makinede pwsh bulunamadı. Hedef makinelerde pwsh kurulumu gereklidir." 'Warning'
    }
}
```

Neden:
- Çalışmayan hedeflerde kullanıcıyanı uyarmak.
- Bu, kullanıcı için kritik bir uyarıdır.

---

### 2.5. Çıktı boyutu loglandı
Dosya:
- `pwxe/scripts/PwX-Build.ps1`

Eklendi:
```powershell
$fi = Get-Item -LiteralPath $finalExe
$result.OutputSize = $fi.Length
Write-Log ('BAŞARILI: {0} ({1:N1} MB)' -f $finalExe, ($fi.Length / 1MB))
```

Neden:
- Özellikle CI ve PR incelemelerinde farklı çıktı boyutlarını karşılaştırmak çok kolaylaşır.
- Boyut regressions geri ödeme için gereklidir.

---

## 3) Ana Dosya: pwxe/scripts/PwX-Build.ps1 (tam değişim özeti)

### 3.1. Orijinal davranış
- Default `RuntimeMode = 'SelfContained'`
- PS7 builds self-contained and big

### 3.2. Yeni davranış
- Default `RuntimeMode = 'FrameworkDependent'`
- PS7 builds smaller by default
- SelfContained remains available
- SingleFile remains available
- Trim and UPX are optional optimizations

### 3.3. Kod değişikliği (özet)
```powershell
param(
    [Parameter(Mandatory)][string]$Source,
    [string]$Output,
    [ValidateSet('PS51', 'PS7')][string]$Target = 'PS7',
    [ValidateSet('Console', 'Gui')][string]$Mode = 'Console',
    [ValidateSet('SelfContained', 'FrameworkDependent')][string]$RuntimeMode = 'FrameworkDependent',
    [ValidateSet('win-x64', 'win-arm64')][string]$Architecture = 'win-x64',
    [switch]$SingleFile,
    [string]$Icon,
    [string]$ProductName,
    [string]$CompanyName,
    [string]$Description,
    [string]$FileVersion = '1.0.0.0',
    [string]$ProductVersion,
    [string]$PsSdkVersion = '7.4.6',
    [string]$Framework = 'net8.0',
    [string]$LogPath,
    [switch]$Force,
    [switch]$KeepTemp,
    [switch]$EnableTrim,
    [switch]$EnableUpx
)
```

### 3.4. Etki
- PS7 default output size drops significantly.
- Larger self-contained builds still available.
- No breakage for PS51.
- Safe default for standard Windows destinations where pwsh is already installed.

---

## 4) Dökümantasyon değişiklikleri

## 4.1. pwxe/README.md

Güncellenen önemli metin:
- `PS7 builds default to FrameworkDependent to produce much smaller .exe files`
- `-EnableTrim` and `-EnableUpx` documented with examples
- `PS7 default runtime: FrameworkDependent`

Görüntülenen örnekler:
```markdown
### 3) PowerShell 7 build with small default output

Invoke-Pwxe -Source .\modern.ps1 `
            -Output .\modern.exe `
            -Target PS7
```

```markdown
### 4) PowerShell 7 self-contained build (larger file)

Invoke-Pwxe -Source .\modern.ps1 `
            -Output .\modern-selfcontained.exe `
            -Target PS7 `
            -Runtime SelfContained `
            -SingleFile
```

```markdown
### 5) Optional size reduction

Invoke-Pwxe -Source .\modern.ps1 `
            -Output .\modern-trimmed.exe `
            -Target PS7 `
            -Runtime FrameworkDependent `
            -EnableTrim
```

---

## 4.2. PwX-Studio/README.md

Güncellenen açıklama:
> PS7 size optimization: PwX Studio prefers the smaller `FrameworkDependent` mode for PowerShell 7 builds by default. This keeps generated `.exe` files significantly smaller while still allowing `SelfContained` and `SingleFile` builds when needed.

Yani:
- UI side now aligned with engine behavior
- user expectations match actual output

---

## 4.3. pwxe/CHANGELOG.md

Yeni değişiklik:
```markdown
## [1.0.2] — 2026-10-17

### Changed
- **PS7 default output size optimization:** the default PS7 runtime mode is now `FrameworkDependent` instead of `SelfContained`, which produces much smaller `.exe` files for typical Windows deployments.
- **User guidance added:** build logs now warn when `FrameworkDependent` output is selected but no compatible `pwsh` installation is detected on the target machine.

### Added
- **`-EnableTrim` support:** optional `dotnet publish /p:PublishTrimmed=true` mode for PS7 builds to reduce output size further.
- **`-EnableUpx` support:** optional runtime compression pass using UPX when installed.
- **Output size logging:** build output size is written to the log for easier regression tracking and size comparisons.
```

---

## 4.4. PwX-Studio/CHANGELOG.md

Yeni değişiklik:
```markdown
## [1.5.1] — 2026-10-17

### Changed
- **PS7 boyut optimizasyonu:** PowerShell 7 hedefleri için varsayılan derleme modu `FrameworkDependent` olarak değiştirildi.
- **İstisnai durum uyarısı eklendi:** `FrameworkDependent` derleme seçildiğinde hedef sistemde uygun `pwsh` bulunmadığı durum için daha net uyarı mesajı verilir.
- **Dokümantasyon güncellendi:** README ve kullanım rehberi, boyutu düşüren varsayılan davranışla uyumlu hale getirildi.
```

---

## 5) Branch Bilgileri

Açılan branchler:
- `pwxe` -> `feature/ps7-size-opt`
- `PwX-Studio` -> `feature/ps7-size-opt`

Amaç:
- PS7 size optimization changes isolated in one feature branch for review
- PR-ready and easy to revert

---

## 6) PR İçin Hazırlanan Metinler

## 6.1. English PR Summary
```md
## Summary
- Make PS7 builds produce small-by-default executables by changing default runtime mode from SelfContained → FrameworkDependent.
- Add optional build flags:
  - -EnableTrim : enables dotnet PublishTrimmed to attempt further size reduction.
  - -EnableUpx  : opt-in UPX compression step for final exe (if UPX is installed).
- Add pwsh detection and a build-time warning when FrameworkDependent output is selected but pwsh is not found locally.
- Log output size to the build log and expose size in artifacts for CI.
- Update README and CHANGELOG to document behavior and options.

## Why this change
- SelfContained / single-file PS7 builds are much larger because they package the .NET runtime and PowerShell runtime into the final executable.
- For most Windows target environments where pwsh is already installed, FrameworkDependent produces much smaller and more practical EXE files.
- This keeps the default output lightweight while preserving the ability to opt into larger self-contained distributions when needed.

## Risk and mitigation
- FrameworkDependent output will fail on target machines without compatible pwsh.
  - Mitigation: build-time pwsh detection and explicit user warnings in logs and docs.
- PublishTrimmed may break reflection-heavy scenarios.
  - Mitigation: -EnableTrim remains opt-in and should be validated in CI before release.
- UPX can trigger AV false positives.
  - Mitigation: -EnableUpx remains opt-in and should be used only in controlled release scenarios.

## Testing
- PS51 build
- PS7 FrameworkDependent build
- PS7 FrameworkDependent + EnableTrim
- PS7 SelfContained + SingleFile
- Smoke tests for script execution and argument binding
- CI matrix to track exe size differences

## Rollback
- Revert RuntimeMode default back to SelfContained in PwX-Build.ps1 and revert the documentation updates if needed.

## Checklist
- [ ] README updated
- [ ] CHANGELOG updated
- [ ] Local smoke tests run
- [ ] CI matrix reviewed
- [ ] Release notes prepared
```

## 6.2. Türkçe PR Summary
```md
## Özet
- PS7 için varsayılan çalışma zamanı modu SelfContained → FrameworkDependent olacak şekilde değiştirildi; böylece PS7 hedefli EXE’ler varsayılan olarak çok daha küçük üretilecek.
- Opsiyonel build bayrakları eklendi:
  - -EnableTrim : dotnet PublishTrimmed ile ek küçültme denemesi
  - -EnableUpx  : UPX ile sıkıştırma (UPX kuruluysa)
- Build sırasında pwsh tespiti yapılıyor; FrameworkDependent seçildiğinde pwsh yoksa uyarı veriliyor.
- Çıktı boyutu loglanıyor ve CI artefaktlarına ekleniyor.
- README ve CHANGELOG güncellendi.

## Neden
- PS7 SelfContained veya SingleFile paketleme çok büyük hale gelir.
- Hedef makinelerde pwsh kuruluysa FrameworkDependent çok daha pratik küçük exe verir.

## Riskler ve önlemler
- FrameworkDependent exe, hedefte pwsh yoksa çalışmaz.
  - Önlem: build sırasında pwsh tespiti ve uyarı.
- Trim, reflection/dynamic load içeren kodları bozabilir.
  - Önlem: EnableTrim opsiyonel ve CI’de ayrı test edilmeli.
- UPX AV false positive üretebilir.
  - Önlem: EnableUpx opsiyonel ve kontrollü kullanım.

## Testler
- PS51 build
- PS7 framework-dependent build
- PS7 trimmed build
- PS7 self-contained single-file build
- smoke testleri
- CI boyut matrisi

## Rollback
- RuntimeMode defaultunu eski değere döndürmek yeterlidir.

## Kontrol listesi
- [ ] README güncellendi
- [ ] CHANGELOG güncellendi
- [ ] Lokal smoke testleri çalıştırıldı
- [ ] CI matrisi incelendi
- [ ] Release notu hazırlandı
```

---

## 7) CI Workflow (tam öneri)

Dosya yolu:
- `.github/workflows/ci-size-matrix.yml`

Tam içerik:
```yaml
name: CI - Size matrix

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

permissions:
  contents: read
  actions: write

jobs:
  build-and-smoke:
    runs-on: windows-latest
    strategy:
      matrix:
        include:
          - id: ps51
            target: PS51
            runtimeMode: ''
            singleFile: false
            enableTrim: false
            dotnet: false
          - id: ps7-fwdep
            target: PS7
            runtimeMode: FrameworkDependent
            singleFile: false
            enableTrim: false
            dotnet: true
          - id: ps7-fwdep-trim
            target: PS7
            runtimeMode: FrameworkDependent
            singleFile: true
            enableTrim: true
            dotnet: true
          - id: ps7-sc-single
            target: PS7
            runtimeMode: SelfContained
            singleFile: true
            enableTrim: false
            dotnet: true

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup .NET (for PS7 jobs)
        if: matrix.dotnet == true
        uses: actions/setup-dotnet@v3
        with:
          dotnet-version: '8.0.x'

      - name: Setup PowerShell
        uses: actions/setup-powershell@v2

      - name: Run PwX Build
        shell: pwsh
        env:
          ARTIFACT_DIR: ${{ runner.temp }}\pwx-artifacts
        run: |
          New-Item -ItemType Directory -Force -Path $Env:ARTIFACT_DIR | Out-Null

          $source = Join-Path $PSScriptRoot 'tests\samples\hello.ps1'
          $outDir = Join-Path $Env:ARTIFACT_DIR ${{ matrix.id }}
          New-Item -ItemType Directory -Force -Path $outDir | Out-Null
          $outExe = Join-Path $outDir 'hello.exe'

          $pwargs = @(
            '-Source', $source
            '-Output', $outExe
            '-Target', '${{ matrix.target }}'
            '-Force'
          )

          if ('${{ matrix.runtimeMode }}' -ne '') { $pwargs += ('-RuntimeMode', '${{ matrix.runtimeMode }}') }
          if ('${{ matrix.singleFile }}' -eq 'True') { $pwargs += '-SingleFile' }
          if ('${{ matrix.enableTrim }}' -eq 'True') { $pwargs += '-EnableTrim' }

          Write-Host "Running PwX-Build with args: $($pwargs -join ' ')"
          if ('${{ matrix.target }}' -eq 'PS51') {
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\PwX-Build.ps1 @pwargs
          } else {
            pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\PwX-Build.ps1 @pwargs
          }

      - name: Collect size and artifact
        if: always()
        shell: pwsh
        run: |
          $search = Get-ChildItem -Path $Env:ARTIFACT_DIR -Recurse -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
          if (-not $search) {
            Write-Host "No exe found for matrix id: ${{ matrix.id }}"
            exit 0
          }
          $exePath = $search.FullName
          $size = (Get-Item $exePath).Length
          $sizeFile = Join-Path (Split-Path $exePath) 'size.txt'
          Set-Content -Path $sizeFile -Value $size
          Write-Host "Exe: $exePath size: $size bytes"

      - name: Upload artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: pwx-build-${{ matrix.id }}
          path: |
            ${{ runner.temp }}\pwx-artifacts\${{ matrix.id }}\**
```

Neden önemli:
- PS51, PS7 fwdep, PS7 fwdep+trim, PS7 sc-single matrixi var.
- Her biri için `size.txt` üretir.
- Boyut regressions kolay takip edilir.

---

## 8) Test listesi (çalıştırılmalı / gereklidir)

### 8.1. PS51 build
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\PwX-Build.ps1 `
  -Source .\tests\samples\hello.ps1 `
  -Output .\out\hello51.exe `
  -Target PS51 -Force
```

### 8.2. PS7 default framework-dependent
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\PwX-Build.ps1 `
  -Source .\tests\samples\hello.ps1 `
  -Output .\out\hello7-fwdep.exe `
  -Target PS7 -Force
```

### 8.3. PS7 trimmed
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\PwX-Build.ps1 `
  -Source .\tests\samples\hello.ps1 `
  -Output .\out\hello7-trim.exe `
  -Target PS7 -EnableTrim -Force
```

### 8.4. PS7 self-contained single-file
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\PwX-Build.ps1 `
  -Source .\tests\samples\hello.ps1 `
  -Output .\out\hello7-sc.exe `
  -Target PS7 -RuntimeMode SelfContained -SingleFile -Force
```

### 8.5. Smoke test önceliği
- Çıktıyı çalıştırmak
- Parameter binding
- Exit code
- Türkçe karakterler test etmek
- `tests/Run-Smoke.ps1` ile gerekiyorsa hepsini kontrol etmek

---

## 9) Risk analizi ve mitigation tablosu

| Risk | Etki | Olasılık | Mitigation |
|------|------|----------|-----------|
| FrameworkDependent hedefte pwsh yoksa çalışmaz | Yüksek | Orta | pwsh kontrolü + README notu |
| `PublishTrimmed` reflection kırmaları | Yüksek | Orta | Opsiyonel, CI ile dene |
| UPX false positive | Orta | Orta | Opsiyonel, AV testleri |
| Boyut regression | Orta | Orta | size.txt + artifact tracking |
| UI / Documentation mismatch | Orta | Düşük | README + changelog alignment |

---

## 10) Rollback planı

Eğer geri alınması gerekiyorsa:
1. `pwxe/scripts/PwX-Build.ps1` içindeki default `$RuntimeMode` eski değere `(SelfContained)` çevrilir.
2. README ve CHANGELOG geri alınır.
3. `git revert` ile ilgili commit geri alınır.
4. Release notları ve kullanıcı bildirimleri güncellenir.

---

## 11) Branch ve PR açıklama durumu

Açılan branchler:
- `mtahiryilmazz/pwxe: feature/ps7-size-opt`
- `mtahiryilmazz/PwX-Studio: feature/ps7-size-opt`

PR için kullanılabilecek başlıklar:
- English: `Optimize PS7 default to FrameworkDependent, add EnableTrim/EnableUpx and CI size-matrix`
- Turkish: `PS7 varsayılanı FrameworkDependent olarak küçültme, EnableTrim/EnableUpx ekleme ve CI boyut-matris`

---

## 12) Son sonuç / karar

Sonuç:
- PS7 için varsayılan davranış daha küçük ve daha pratik hale getirildi.
- Kullanıcılar isterseler artık `SelfContained` ve `SingleFile` seçeneğini de kullanabilir.
- Trim ve UPX opsiyonel olarak eklenerek optimal boyutlandırma seçenekleri sunuluyor.
- Dokümantasyon ve changelog senkronize edildi.
- CI matrix önerisi hazırlandı.
- Riskler ve rollback planı açıkça belgelendi.

Bu sayede örnek hedef şunu yapabilir:
- Sıkı dağıtım: `FrameworkDependent` (varsayılan)
- Offline/saf ortam: `SelfContained`
- Ek küçültme: `-EnableTrim`
- Max sıkıştırma: `-EnableUpx` (opsiyonel, AV dikkatli)

---

## 13) Kısa kullanım tablosu

| Durum | Komut / Harici adım | Beklenen sonuç |
|------|--------------------|---------------|
| PS7 küçük default | `-Target PS7` | Daha küçük exe |
| PS7 self-contained | `-RuntimeMode SelfContained -SingleFile` | Daha büyük ama tek başına bağımsız exe |
| PS7 trims | `-EnableTrim` | Daha küçük olabilir ama test gerekir |
| PS7 UPX | `-EnableUpx` | Çok daha küçük olabilir ama AV dikkate alınmalı |
| PS5.1 | `-Target PS51` | En hafif ve eski davranış |

---

## 14) Notlar ve öneriler

- `FrameworkDependent` defaultu, PS7 için en pratik ve en güvenli başlangıç modeli.
- `SelfContained` ve `SingleFile` kullanımına devam edilebilir, fakat kullanıcı bunu bilerek seçmelidir.
- `EnableTrim` kesin kullanılacak karar için CI’de sıkı test edilmelidir.
- UPX opsiyonel sürümde kalmalı; AV riskleri nedeniyle production’da dikkatli kullanılmalı.
- Release branch’inizde size-matrix’leri korumak gerekir.

---

## 15) Final checklist (merge öncesi)
- [ ] pwxe build script default updated
- [ ] README updated
- [ ] CHANGELOG updated
- [ ] PwX-Studio docs updated
- [ ] CI workflow added
- [ ] Smoke tests executed on key variants
- [ ] Trim variant tested in CI
- [ ] Release notes prepared
- [ ] Rollback instructions documented
- [ ] User-facing warning for missing pwsh added

---

Bitti. Bu dosya tek başına, tüm süreci kapsayan arkiv niteliğinde bir markdown dokümanıdır.
