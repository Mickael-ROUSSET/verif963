# Run with powershell.exe -NoProfile -File tests\Installer.Tests.ps1
# No administrator rights, network, winget or real scheduled task mutations.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$source = Get-Content (Join-Path $repo 'Installer-Verif963.ps1') -Raw
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$functions = $ast.FindAll({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst]},$false)
foreach ($function in $functions) { Invoke-Expression $function.Extent.Text }
$body = $source.Substring($source.IndexOf("`nAssert-Administrator") + 1)
$engine = [scriptblock]::Create($body)
$testRoot = Join-Path $env:TEMP ('verif963 tests ' + [guid]::NewGuid().ToString('N'))
New-Item $testRoot -ItemType Directory | Out-Null
function Assert($condition,$message) { if (-not $condition) { throw "ASSERT: $message" } }
function Assert-Administrator {}
function Get-Python { return 'C:\Python313\python.exe' }
function Install-Python { throw 'Unexpected winget installation' }
function Set-Acl {}
function Invoke-RestMethod { return @{tag_name='v1.0.0'} }
function Invoke-WebRequest { param($Uri,$OutFile,[switch]$UseBasicParsing,$TimeoutSec) Assert $UseBasicParsing 'basic parsing required'; Set-Content -LiteralPath $OutFile 'zip' }
function Expand-Archive {
    param($LiteralPath,$DestinationPath)
    $release = Join-Path $DestinationPath 'release'
    New-Item $release -ItemType Directory -Force | Out-Null
    foreach ($name in @('verif963.py','requirements.txt','Installer-Verif963.ps1','Maj-Verif963.ps1','surveillance_963.ini.example')) {
        Microsoft.PowerShell.Management\Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $release
    }
    if ($script:fail -eq 'archive') { Remove-Item (Join-Path $release 'requirements.txt') }
}
function Invoke-Python {
    param($Executable,$Arguments)
    if ($Arguments[1] -eq 'venv') {
        $scripts = Join-Path $Arguments[2] 'Scripts'
        New-Item $scripts -ItemType Directory -Force | Out-Null
        Set-Content (Join-Path $scripts 'python.exe') 'mock'
    }
    if ($Arguments -contains 'install' -and $script:fail -eq 'pip') { throw 'pip failure' }
    if ($Arguments -contains '--version') { if ($script:fail -eq 'version') { return '9.9.9' }; return '1.0.0' }
}
function Get-ScheduledTask { return $script:task }
function Export-ScheduledTask { return 'original xml' }
function Stop-ScheduledTask { $script:task.State = 'Ready' }
function Start-ScheduledTask {
    $script:starts++
    if ($script:fail -eq 'start' -and $script:starts -eq 1) { throw 'start failure' }
    $script:task.State = 'Running'
}
function New-ScheduledTaskAction { param($Execute,$Argument,$WorkingDirectory) return @{Execute=$Execute; Arguments=$Argument; WorkingDirectory=$WorkingDirectory} }
function New-ScheduledTaskTrigger {}
function New-ScheduledTaskSettingsSet { param([switch]$StartWhenAvailable,$RestartCount,$RestartInterval,$ExecutionTimeLimit,$MultipleInstances,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) Assert ($ExecutionTimeLimit -eq [TimeSpan]::Zero) 'no three-day limit' }
function New-ScheduledTaskPrincipal { param($UserId,$LogonType,$RunLevel) Assert ($UserId -eq 'SYSTEM') 'SYSTEM principal' }
function Register-ScheduledTask {
    param($TaskName,$TaskPath,$Action,$Trigger,$Settings,$Principal,[switch]$Force,$Xml)
    if ($Xml) { $script:task = @{State='Ready'; Actions=@{Execute='old python'}}; $script:restored=$true; return }
    $script:task = @{State='Ready'; Actions=$Action}
    if ($script:fail -eq 'register') { throw 'registration failure' }
}
function Disable-ScheduledTask { $script:task.State='Disabled' }
function Unregister-ScheduledTask { param($TaskName,$TaskPath,$Confirm) $script:task=$null }
function Copy-Item {
    param($LiteralPath,$Destination,[switch]$Force)
    if ($script:fail -eq 'copy' -and $LiteralPath -like '*release\requirements.txt' -and $Destination -like '*installation space*') { throw 'copy failure' }
    Microsoft.PowerShell.Management\Copy-Item -LiteralPath $LiteralPath -Destination $Destination -Force:$Force
}
function Run-Scenario($scenarioName,$failure,$existing,$running,$disabled) {
    $InstallDir = Join-Path $testRoot ($scenarioName + ' installation space')
    $TaskName = 'Test surveillance'
    $Update = $false
    $script:fail=$failure; $script:starts=0; $script:restored=$false; $script:task=$null
    New-Item $InstallDir -ItemType Directory | Out-Null
    if ($existing) {
        Set-Content (Join-Path $InstallDir 'verif963.py') 'old script'
        [IO.File]::WriteAllBytes((Join-Path $InstallDir 'surveillance_963.ini'),[byte[]](0,1,2,255,10))
        $script:task = @{State='Ready'; Actions=@{Execute='old python'}}
        if ($running) { $script:task.State='Running' }
        if ($disabled) { $script:task.State='Disabled' }
    }
    $caught=$false
    try { . $engine } catch { $caught=$true; Write-Host "Expected failure [$scenarioName]: $_" }
    Assert ($caught -eq [bool]$failure) "$scenarioName outcome"
    if ($existing) {
        Assert (([IO.File]::ReadAllBytes((Join-Path $InstallDir 'surveillance_963.ini')) -join ',') -eq '0,1,2,255,10') "$scenarioName preserves INI bytes"
    }
    if ($failure) {
        if ($existing) {
            Assert ((Get-Content (Join-Path $InstallDir 'verif963.py') -Raw).Trim() -eq 'old script') "$scenarioName restores script"
            Assert ($script:task.Actions.Execute -eq 'old python') "$scenarioName restores task"
            if ($running) { Assert ($script:task.State -eq 'Running') "$scenarioName resumes task" }
        } else {
            Assert (-not (Test-Path (Join-Path $InstallDir 'verif963.py'))) "$scenarioName removes partial code"
            Assert (-not (Test-Path (Join-Path $InstallDir 'surveillance_963.ini'))) "$scenarioName removes new INI"
            Assert (-not $script:task) "$scenarioName removes new task"
        }
    } else {
        Assert ($script:task.Actions.Arguments -eq ('"' + (Join-Path $InstallDir 'verif963.py') + '"')) "$scenarioName quotes paths"
        Assert ($script:task.Actions.WorkingDirectory -eq $InstallDir) "$scenarioName working directory"
        if ($disabled) { Assert ($script:task.State -eq 'Disabled') "$scenarioName preserves disabled state" }
        if ($running) { Assert ($script:task.State -eq 'Running') "$scenarioName resumes task" }
        $Update=$true
        $before=(Get-Content (Join-Path $InstallDir 'installation.json') -Raw)
        . $engine
        Assert ((Get-Content (Join-Path $InstallDir 'installation.json') -Raw) -eq $before) "$scenarioName idempotent update"
    }
    Write-Host "PASS $scenarioName"
}
try {
    Run-Scenario 'fresh' '' $false $false $false
    Run-Scenario 'running' '' $true $true $false
    Run-Scenario 'disabled' '' $true $false $true
    foreach ($failure in @('archive','pip','version','copy','register','start')) { Run-Scenario $failure $failure $true $true $false }
    Run-Scenario 'fresh-register' 'register' $false $false $false
    Write-Host 'All 10 scenarios passed.'
} finally { Remove-Item -LiteralPath $testRoot -Recurse -Force }

