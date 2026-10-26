# .NET Standard 2.0 In-Process Hybrid Prototipi (PwX.Hybrid)

Bu dizin, `pwxe` ve `PwX-Studio` ana modüllerinden tamamen yalıtılmış olarak çalışan deneysel **In-Process Hibrit Model** prototipini içerir.

## Mimari Amaç ve Kapsam
1. **Ana Modüle Dokunmama Prensibi:**
   - Resmi `pwxe` CLI ve `PwX-Studio` derleme zinciri (`src/PwX.BuildHost.PS51` ve `src/PwX.BuildHost.PS7`) dış süreç çağırma (`powershell.exe` / `pwsh.exe`) mimarisiyle stabil kalır.
   - Bu prototip, gelecekte (v1.9.0/v2.0.0) dış süreç çağırma ihtiyacını ortadan kaldırarak betikleri doğrudan .NET süreci içinde (in-memory runspace) çalıştırma fizibilitesini araştırmak için kurulmuştur.

2. **Hedef Standart (`netstandard2.0`):**
   - `netstandard2.0` hedeflenerek hem Windows PowerShell 5.1 (`.NET Framework 4.6.1+` / `4.8`) hem de PowerShell 7+ (`.NET Core 2.0+` / `.NET 8`) ortamlarında ortak ikili (binary) uyumluluğu amaçlanır.
   - `PowerShellStandard.Library` (5.1.1) referansı kullanılarak her iki platformun `System.Management.Automation` API yüzeyine köprü kurulur.

## Proje Yapısı
- `PwX.Hybrid.Prototype.csproj`: `netstandard2.0` SDK projesi.
- `HybridScriptRunner.cs`: `InitialSessionState`, `Runspace` ve `PowerShell.Create()` ile bellek içi çalıştırma motoru.
- `Tests/`: Prototip doğrulama testleri.

## Derleme ve Doğrulama
```powershell
dotnet build src/PwX.Hybrid.Prototype/PwX.Hybrid.Prototype.csproj -c Release
```
