param(
    [string]$Name = 'none',
    [switch]$Loud,
    [switch]$Native,
    [switch]$NoExit,
    [switch]$Throw,
    [int]$Code = 0,
    [string]$Out
)

if ($Out) { Set-Content -LiteralPath $Out -Value ('{0}|{1}|{2}' -f $Name, $Loud.IsPresent, $Code) -Encoding UTF8 }
if ($Loud) { Write-Error 'non-terminating error' }
if ($Native) {
    if ($env:OS -eq 'Windows_NT') { & cmd.exe /c 'exit 4' } else { & sh -c 'exit 4' }
}
if ($Throw) { throw 'boom' }
if ($NoExit) { return }   # acik exit yok: normal bitis
exit $Code
