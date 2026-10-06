#requires -Version 5.1
param(
    [string]$InstallDir = 'C:\Users\Public\SupervisionMairie\Surveillance_963',
    [string]$TaskName = 'Surveillance Trend 963'
)
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'Installer-Verif963.ps1'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Installateur absent. Telechargez Installer-Verif963.ps1 pour migrer cette installation.' }
& $installer -InstallDir $InstallDir -TaskName $TaskName -Update
