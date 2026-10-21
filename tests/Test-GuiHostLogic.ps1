<#
.SYNOPSIS  PS7 GUI host mantığı birim testi (Windows gerektirmez; PowerShell 7 yeterli).
.DESCRIPTION
  src\PwX.BuildHost.PS7\Program.cs (PWX_GUI tanımıyla) ve ScriptArguments.cs dosyalarını Add-Type ile
  derler, RunHidden yöntemini yansıma ile örnek betiklerle çalıştırır ve işlem çıkış kodunu ile argüman
  bağlamayı doğrular. Gerçek EXE/dotnet publish gerekmez; Windows CI'dan önce hızlı geri bildirim verir.
  Linux'ta desteklenmeyen iki satır (ExecutionPolicy, STA) yalnızca geçici kopyadan çıkarılır.
#>
$ErrorActionPreference = 'Stop'
$hostSrc = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\PwX.BuildHost.PS7'
$samples = Join-Path $PSScriptRoot 'samples'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('pwx-hostlogic-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
    $prog = (Get-Content -LiteralPath (Join-Path $hostSrc 'Program.cs') -Raw -Encoding UTF8)
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        $prog = ($prog -split "`r?`n" | Where-Object { $_ -notmatch 'iss\.ExecutionPolicy|rs\.ApartmentState' }) -join "`n"
    }
    Set-Content -LiteralPath (Join-Path $tmp 'Program.cs') -Value ("#define PWX_GUI`n#define PWX_TESTHOOKS`n" + $prog) -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $hostSrc 'ScriptArguments.cs') -Destination $tmp
    Add-Type -Path (Join-Path $tmp 'Program.cs'), (Join-Path $tmp 'ScriptArguments.cs') -ErrorAction Stop

    $type = [AppDomain]::CurrentDomain.GetAssemblies().GetTypes() | Where-Object FullName -eq 'PwX.BuildHost.Program' | Select-Object -First 1
    $run  = $type.GetMethod('RunHidden', [Reflection.BindingFlags]'NonPublic,Static')
    $log  = Join-Path $tmp 'err.log'
    $out  = Join-Path $tmp 'out.txt'
    $rows = New-Object System.Collections.Generic.List[object]

    function T($id, $script, [string[]]$a, $expect, $logMatch = $null, $outExpect = $null) {
        Remove-Item -LiteralPath $log, $out -Force -ErrorAction SilentlyContinue
        $env:PWX_ERROR_LOG = $log
        try { $got = $run.Invoke($null, @([string](Join-Path $samples $script), [string[]]$a)) } finally { Remove-Item Env:\PWX_ERROR_LOG -ErrorAction SilentlyContinue }
        $ok = ($got -eq $expect)
        $logText = if (Test-Path $log) { (Get-Content $log -Raw).Trim() } else { '' }
        $outText = if (Test-Path $out) { (Get-Content $out -Raw -Encoding UTF8).Trim() } else { '' }
        if ($logMatch -and $logText -notmatch $logMatch) { $ok = $false }
        if ($outExpect -and $outText -ne $outExpect) { $ok = $false }
        $rows.Add([pscustomobject]@{ Test = $id; Expected = $expect; Got = $got; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }); Detail = "$logText $outText".Trim() })
    }

    T 'exit 17'                         'hello.ps1'    @('-Code', '17') 17
    T 'exit 1'                          'hello.ps1'    @('-Code', '1') 1
    T 'normal bitiş'                    'hello.ps1'    @() 0
    T '-Message x -Code 5 sırası'       'hello.ps1'    @('-Message', 'abc', '-Code', '5') 5
    T '-Code:7 biçimi'                  'gui-edge.ps1' @('-Code:7') 7
    T '[switch] + param'                'gui-edge.ps1' @('-Loud', '-Code', '9') 9
    T '-Loud:$false'                    'gui-edge.ps1' @('-Loud:$false', '-Code', '2') 2
    T '[switch] değer tüketmez'         'gui-edge.ps1' @('-Loud', 'Ali', '-Code', '3') 3
    T 'parametre kısaltması -Cod'       'gui-edge.ps1' @('-Cod', '6') 6
    T 'yerel komut kodu sızmaz'         'gui-edge.ps1' @('-Native', '-NoExit') 0
    T 'Unicode değer'                   'gui-edge.ps1' @('-Name', 'şğü ÇÖİ', '-Out', $out, '-Code', '8') 8 $null 'şğü ÇÖİ|False|8'
    T 'throw -> 1 + günlük'             'gui-edge.ps1' @('-Throw') 1 'boom'
    T 'geçersiz tür -> 1 + günlük'      'hello.ps1'    @('-Code', 'abc') 1 'Int32'
    T 'bilinmeyen param -> $args'       'hello.ps1'    @('-Nope', 'x') 0

    Write-Host ("Toplam test: {0}" -f $rows.Count)
    ($rows | Format-Table -AutoSize | Out-String -Width 200).TrimEnd() | Write-Host
    if ($rows | Where-Object Result -eq 'FAIL') { exit 1 }
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
