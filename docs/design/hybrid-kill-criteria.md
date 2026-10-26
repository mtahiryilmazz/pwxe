# In-Process Hibrit Model Karar ve Kill-Criteria Şartnamesi
**Tarih:** 2026-10-26  
**Durum:** Prototip / İzole Dal Planı (`experimental/in-process-hybrid`)  
**Sorumlu:** Antigravity & Mimari Ekip  

---

## 1. Temel İlke ve Hedef
> *"Yeni teknoloji ama çalışmayan sisteme gerek yok."*

`pwxe`'nin v1.0.0'dan bu yana başarısının temeli, Windows'un yerleşik `powershell.exe` ve `pwsh.exe` süreçlerini çağıran deterministik, asla kırılmayan ve sistem bağımlılığı minimum olan derleme modelidir.

In-Process (Süreç İçi) hibrit model, betiği dış süreç açmadan doğrudan .NET süreci içinde çalıştırmayı dener. Ancak CLR çakışmaları, modül izolasyon kayıpları ve runspace kilitlenmeleri riski büyüktür. Bu nedenle ana üretim hattına (`main`) doğrudan entegre edilmeyecek, kararsızlığı önlemek adına **tarihe ve ölçülebilir "Kill Criteria"ya (Sonlandırma Kriteri)** bağlanacaktır.

---

## 2. Geliştirme İzolasyonu
- **Git Dalı (Branch):** `experimental/in-process-hybrid`
- **Fiziksel Dizin:** `src/PwX.Hybrid.Prototype/` (ana modülden yalıtılmış)
- **Hedef Framework:** `netstandard2.0` (PowerShellStandard.Library 5.1.1)
- **Ana Ürüne Dokunmama Garantisi:** `src/PwX.BuildHost.PS51`, `src/PwX.BuildHost.PS7`, `scripts/PwX-Build.ps1` ve `pwxe.psm1` bu daldaki değişikliklerden tamamen etkilenmez.

---

## 3. Kill Criteria (Sonlandırma Kriterleri)
Aşağıdaki iki şarttan **HERHANGİ BİRİ** başarısız olursa, 6 hafta sonunda dal derhal arşivlenir (`kill`) ve ana ürün çift motorlu (`powershell.exe`/`pwsh.exe`) mimarisiyle yoluna devam eder:

### Kriter A: Çalışma Zamanı & ALC/AppDomain İzolasyonu
- PS7'nin veya PowerShell Standard'ın `netstandard2.0` tabanlı SMA kütüphanesi, **.NET Framework 4.8** altında ayrı bir AppDomain/ALC sınırında sıfır çakışma (assembly version mismatch, TypeInitializationException olmaksızın) ile başarıyla yüklenebiliyor ve runspace açabiliyor mu?
  - **Evet:** Geçer.
  - **Hayır:** 🛑 **KILL** (Dal kapatılır, konu kapatılır).

### Kriter B: 20 Kritik Cmdlet Doğrulama Matrisi
Aşağıdaki 20 yaygın ve kritik cmdlet, izole süreç içi runspace içinde hatasız, stdin/stdout/stderr akışları bozulmadan çalışıyor mu?

1. `Get-ChildItem` (Dosya sistemi navigasyonu)
2. `Invoke-RestMethod` (Ağ ve SSL/TLS stack çağrısı)
3. `ConvertTo-Json` / `ConvertFrom-Json` (Serileştirme)
4. `Import-Module` (Harici modül import etme kabiliyeti)
5. `Start-Process` (Dış süreç yönetimi)
6. `Get-Process` (Sistem sorgusu)
7. `Get-Service` (WMI/CIM/Service Controller)
8. `Get-Content` / `Set-Content` (I/O akışları)
9. `Select-Object` (Pipeline nesne dönüştürme)
10. `Where-Object` (Pipeline filtreleme)
11. `ForEach-Object` (Pipeline yineleme)
12. `Write-Output` / `Write-Host` (Akış yönlendirme)
13. `Test-Path` (Yol doğrulama)
14. `New-Item` / `Remove-Item` (Dosya/Dizin manipülasyonu)
15. `Export-Csv` / `Import-Csv` (Yapılandırılmış veri I/O)
16. `Invoke-Expression` (Dinamik kod çalıştırma)
17. `Get-Date` (Zaman / Kültür fonksiyonları)
18. `Measure-Object` (Pipeline istatistikleri)
19. `Try / Catch / Finally` ve `throw` (Hata denetimi ve sonlandırma kodları)
20. `[System.Environment]::Exit(N)` / Exit kodunun üst uygulamaya temiz aktarımı

- **20/20 PASS:** Geçer.
- **< 20 PASS:** 🛑 **KILL** (Dal kapatılır).

---

## 4. Zaman Çizelgesi
- **Başlangıç:** 26 Ekim 2026
- **Karar & Bitiş Tarihi:** 7 Aralık 2026 (6 Hafta)
- **Nihai Eylem:** Kriterler sağlanırsa v1.9.0/v2.0 için RFC hazırlanır; sağlanamazsa `git tag archive/in-process-hybrid` atılarak dal silinir.
