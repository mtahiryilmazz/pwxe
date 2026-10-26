#Requires -Version 5.1
<#
    .SYNOPSIS
        pwxe - Modern, ultra-hizli ve bagimsiz PowerShell'den EXE'ye donusturme motoru (PwX Build Engine).
    .DESCRIPTION
        PowerShell 5.1 (dahili csc.exe) ve PowerShell 7.4+ (.NET 8 SDK) calisma zamanlarini destekleyen,
        sifir dis bagimlilikla calisan CLI derleme araci ve PowerShell modulu.
#>

$script:EngineBuildScript = Join-Path $PSScriptRoot 'scripts\PwX-Build.ps1'
$script:EngineCheckScript = Join-Path $PSScriptRoot 'scripts\Check-Environment.ps1'

function Invoke-Pwxe {
    [CmdletBinding()]
    [Alias('pwxe', 'New-PwxeExecutable')]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Source,

        [Parameter(Position = 1)]
        [string]$Output,

        [Parameter()]
        [ValidateSet('PS51', 'PS7')]
        [string]$Target = 'PS51',

        [Parameter()]
        [ValidateSet('Console', 'Gui')]
        [string]$Mode = 'Console',

        [Parameter()]
        [ValidateSet('SelfContained', 'FrameworkDependent')]
        [string]$Runtime = 'SelfContained',

        [Parameter()]
        [ValidateSet('win-x64', 'win-x86', 'win-arm64')]
        [string]$Architecture = 'win-x64',

        [Parameter()]
        [switch]$SingleFile,

        [Parameter()]
        [string]$Icon,

        [Parameter()]
        [string]$Title,

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [string]$CompanyName,

        [Parameter()]
        [string]$FileVersion = '1.0.0.0',

        [Parameter()]
        [string]$ProductVersion = '1.0.0.0',

        [Parameter()]
        [switch]$Force,

        [Parameter()]
        [switch]$EnableTrim,

        [Parameter()]
        [switch]$EnableUpx,

        [Parameter()]
        [switch]$AutoInstallPrereqs,

        [Parameter()]
        [ValidateSet('asInvoker', 'requireAdministrator', 'highestAvailable')]
        [string]$ExecutionLevel = 'asInvoker',

        [Parameter()]
        [string]$CertificateThumbprint,

        [Parameter()]
        [string]$CertificateFile,

        [Parameter()]
        [string]$CertificatePassword,

        [Parameter()]
        [string]$TimestampServer = 'http://timestamp.digicert.com',

        [bool]$Admin = $false,
        [bool]$Utf8 = $true,
        [bool]$Unicode = $false,
        [bool]$Dpi = $false,
        [bool]$Config = $false,
        [bool]$SupportOS = $false,
        [bool]$LongPaths = $false,
        [bool]$NoOutput = $false
    )

    process {
        if (-not (Test-Path -LiteralPath $script:EngineBuildScript)) {
            throw "pwxe build script not found: $script:EngineBuildScript"
        }

        $resolvedSource = (Resolve-Path -LiteralPath $Source).Path
        $resolvedOutput = $Output
        if (-not $resolvedOutput) {
            $sourceDir = [System.IO.Path]::GetDirectoryName($resolvedSource)
            $sourceBase = [System.IO.Path]::GetFileNameWithoutExtension($resolvedSource)
            $resolvedOutput = Join-Path $sourceDir ($sourceBase + '.exe')
        }

        $bArgs = @{
            Source = $resolvedSource
            Output = [System.IO.Path]::GetFullPath($resolvedOutput)
            Target = $Target
            Mode   = $Mode
            Force  = $Force.IsPresent
        }

        if ($Icon) { $bArgs.Icon = (Resolve-Path -LiteralPath $Icon).Path }
        if ($Title) { $bArgs.ProductName = $Title }
        if ($Description) { $bArgs.Description = $Description }
        if ($CompanyName) { $bArgs.CompanyName = $CompanyName }
        if ($FileVersion) { $bArgs.FileVersion = $FileVersion }
        if ($ProductVersion) { $bArgs.ProductVersion = $ProductVersion }
        $bArgs.Admin = $Admin
        $bArgs.ExecutionLevel = $ExecutionLevel
        if ($CertificateThumbprint) { $bArgs.CertificateThumbprint = $CertificateThumbprint }
        if ($CertificateFile) { $bArgs.CertificateFile = $CertificateFile }
        if ($CertificatePassword) { $bArgs.CertificatePassword = $CertificatePassword }
        if ($TimestampServer) { $bArgs.TimestampServer = $TimestampServer }
        $bArgs.Utf8 = $Utf8
        $bArgs.Unicode = $Unicode
        $bArgs.Dpi = $Dpi
        $bArgs.Config = $Config
        $bArgs.SupportOS = $SupportOS
        $bArgs.LongPaths = $LongPaths
        $bArgs.NoOutput = $NoOutput
        $bArgs.Architecture = $Architecture

        if ($Target -eq 'PS7') {
            $bArgs.RuntimeMode = $Runtime
            if ($SingleFile.IsPresent) { $bArgs.SingleFile = $true }
            if ($EnableTrim.IsPresent) { $bArgs.EnableTrim = $true }
            if ($EnableUpx.IsPresent) { $bArgs.EnableUpx = $true }
            if ($AutoInstallPrereqs.IsPresent) { $bArgs.AutoInstallPrereqs = $true }
        }

        & $script:EngineBuildScript @bArgs
    }
}

function Test-PwxeEnvironment {
    [CmdletBinding()]
    param()

    if (Test-Path -LiteralPath $script:EngineCheckScript) {
        & $script:EngineCheckScript
    } else {
        [pscustomobject]@{
            PSVersion = $PSVersionTable.PSVersion.ToString()
            HasDotnet = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
            EngineScript = $script:EngineBuildScript
        }
    }
}

Export-ModuleMember -Function 'Invoke-Pwxe', 'Test-PwxeEnvironment' -Alias 'pwxe', 'New-PwxeExecutable'
