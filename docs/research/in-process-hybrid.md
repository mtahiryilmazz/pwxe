# Deneysel: Süreç İçi Hibrit (In-Process Hybrid)

> **Durum:** Deneysel / Ar-Ge. Ana ürünü etkilemez.  
> **Kill criteria:** 6 hafta içinde aşağıdaki iki kriterden biri sağlanmazsa dal arşivlenir.

## Amaç
PowerShell 7'nin `netstandard2.0` hedefli `System.Management.Automation.dll`'ini,
.NET Framework 4.8 tabanlı bir ana süreç içinde **ayrı AssemblyLoadContext (ALC)**
kullanarak yüklemek; böylece PS 5.1 ile aynı EXE içinde (süreç içi) barındırmak.

## Neden Bakir Alan
Sektördeki tüm araçlar (PSEBuilder, PS2EXE.Core, PowerShell Pro Tools) süreç dışı
(alt süreç) hibrit kullanıyor. Süreç içi izolasyonu ürünleştiren yok.

## Başarı Kriterleri (6 hafta)
- [ ] PS7 SMA'sı .NET Framework 4.8 altında yükleniyor (ALC + binding redirect)
- [ ] En az 20 yaygın cmdlet çalışıyor:
  Get-ChildItem, Get-Content, Set-Content, Invoke-RestMethod, Invoke-WebRequest,
  ConvertTo-Json, ConvertFrom-Json, Import-Module, Start-Process, Stop-Process,
  Get-Process, Test-Path, New-Item, Remove-Item, Copy-Item, Move-Item,
  Write-Host, Write-Output, Select-Object, Where-Object
- [ ] PS 5.1 aynı süreçte varsayılan AppDomain'de çalışmaya devam ediyor
- [ ] Bilinen kırılganlıklar dokümante edildi (Span/Memory bağımlı cmdlet'ler)

## Bilinen Riskler
- `Span<T>` / `Memory<T>` bağımlı cmdlet'ler .NET Framework altında patlayabilir
- Assembly binding redirect çakışmaları (Newtonsoft.Json vb.)
- AppDomain/ALC izolasyonu .NET Core tarafında sınırlı; PS7 kendi ALC'sini kurar

## Karar
Kriterler sağlanırsa → `pwxe` v2.x için "süreç içi hibrit" modu düşünülür.  
Sağlanmazsa → dal arşivlenir, ana ürün süreç dışı hibritte kalır.
