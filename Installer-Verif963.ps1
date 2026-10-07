#requires -Version 5.1
param(
    [string]$InstallDir = 'C:\Users\Public\SupervisionMairie\Surveillance_963',
    [string]$TaskName = 'Surveillance Trend 963',
    [switch]$Update
)
$ErrorActionPreference = 'Stop'
$DeploymentFormat = 2
function Assert-Administrator {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Ouvrez PowerShell en tant qu''administrateur.' }
}
function Invoke-Python([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Python en echec ($LASTEXITCODE) : $($Arguments -join ' ')" }
}
function Get-Python {
    $candidates = @()
    foreach ($root in @('HKLM:\SOFTWARE\Python\PythonCore','HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')) {
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $install = Get-Item -LiteralPath ($key.PSPath + '\InstallPath') -ErrorAction SilentlyContinue
            if ($install -and $install.GetValue('')) { $candidates += Join-Path $install.GetValue('') 'python.exe' }
        }
    }
    $cmd = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    $candidates += Join-Path $env:ProgramFiles 'Python313\python.exe'
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        # SYSTEM must not depend on per-user Python or Microsoft Store aliases.
        if ($candidate -match '\\Users\\|\\WindowsApps\\') { continue }
        try {
            $actual = (Invoke-Python $candidate @('-c','import sys; assert sys.version_info >= (3,9); print(sys.executable)') | Out-String).Trim()
            if ($actual -and (Test-Path -LiteralPath $actual -PathType Leaf) -and $actual -notmatch '\\Users\\|\\WindowsApps\\') { return $actual }
        } catch { Write-Verbose "Python inutilisable : $candidate" }
    }
    return $null
}
function Install-Python {
    $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $winget) { throw 'Python machine absent et winget indisponible. Installez Python >= 3.9 pour tous les utilisateurs puis relancez.' }
    & $winget.Source install --id Python.Python.3.13 --exact --source winget --scope machine --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw "Installation winget en echec ($LASTEXITCODE). Installez Python pour tous les utilisateurs puis relancez." }
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
function Wait-TaskStopped([string]$Name) {
    Stop-ScheduledTask -TaskName $Name -TaskPath '\'
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-ScheduledTask -TaskName $Name -TaskPath '\').State -eq 'Running') {
        if ((Get-Date) -ge $deadline) { throw "La tache $Name ne s'arrete pas." }
        Start-Sleep -Milliseconds 200
    }
}
Assert-Administrator
if ([string]::IsNullOrWhiteSpace($TaskName) -or $TaskName -match '[\\/\*\?]') { throw 'Nom de tache invalide.' }
$InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
if ($InstallDir -eq [IO.Path]::GetPathRoot($InstallDir).TrimEnd('\') -or $InstallDir.StartsWith('\\')) { throw 'Choisissez un dossier local dedie.' }
# Never operate recursively through a junction/symlink or a redirected ancestor.
$ancestor = $InstallDir
while ($ancestor) {
    if (Test-Path -LiteralPath $ancestor) {
        if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Les chemins rediriges (jonctions/liens) ne sont pas acceptes.' }
    }
    $ancestor = Split-Path $ancestor -Parent
}
if (Test-Path -LiteralPath $InstallDir) {
    foreach ($item in Get-ChildItem -LiteralPath $InstallDir -Recurse -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Lien/ jonction dans le dossier d''installation : choisissez un dossier dedie sans liens.' }
    }
}
if ($Update -and -not (Test-Path -LiteralPath (Join-Path $InstallDir 'verif963.py'))) { throw 'Installation absente. Executez Installer-Verif963.ps1.' }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$hash = [Security.Cryptography.SHA256]::Create()
$lockName = 'Global\verif963-' + ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($InstallDir.ToLowerInvariant())))).Replace('-','')
$hash.Dispose()
$mutex = New-Object Threading.Mutex($false,$lockName)
$locked = $false
$tmpRoot = Join-Path $env:TEMP ('verif963-' + [guid]::NewGuid().ToString('N'))
$zip = "$tmpRoot.zip"
$backup = $null
$changed = $false
$taskChanged = $false
$createdIni = $false
$oldXml = $null
$wasRunning = $false
$wasDisabled = $false
$stopped = $false
$files = @('verif963.py','requirements.txt','Installer-Verif963.ps1','Maj-Verif963.ps1','surveillance_963.ini.example','installation.json')
try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw 'Une installation/mise a jour est deja en cours.' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Mickael-ROUSSET/verif963/releases/latest' -Headers @{'User-Agent'='verif963-installer'} -TimeoutSec 60
    $tag = [string]$release.tag_name
    $version = $null
    if (-not [version]::TryParse(($tag -replace '^v',''),[ref]$version)) { throw "Tag de release invalide : $tag" }
    $oldTask = Get-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction SilentlyContinue
    if ($oldTask) {
        $oldXml = Export-ScheduledTask -TaskName $TaskName -TaskPath '\'
        $wasRunning = $oldTask.State -eq 'Running'
        $wasDisabled = $oldTask.State -eq 'Disabled'
    }
    $manifest = Join-Path $InstallDir 'installation.json'
    if ($Update -and (Test-Path -LiteralPath $manifest)) {
        $state = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        if ([version]$state.version -gt $version) { Write-Host 'Version locale plus recente : aucun downgrade automatique.'; return }
        if ([version]$state.version -eq $version -and $oldTask -and $oldTask.Actions.Execute -eq $state.python -and (Test-Path -LiteralPath $state.python)) {
            Invoke-Python $state.python @('-m','pip','check') | Out-Host
            $actual = (Invoke-Python $state.python @((Join-Path $InstallDir 'verif963.py'),'--version') | Out-String).Trim()
            if ($actual -eq $version.ToString()) { Write-Host 'Installation deja a jour et verifiee.'; return }
        }
    }
    $encodedTag = [Uri]::EscapeDataString($tag)
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/Mickael-ROUSSET/verif963/archive/refs/tags/$encodedTag.zip" -OutFile $zip -TimeoutSec 120
    Expand-Archive -LiteralPath $zip -DestinationPath $tmpRoot
    $roots = @(Get-ChildItem -LiteralPath $tmpRoot -Directory)
    if ($roots.Count -ne 1) { throw 'Archive GitHub invalide.' }
    $src = $roots[0].FullName
    foreach ($name in $files | Where-Object { $_ -ne 'installation.json' }) {
        if (-not (Test-Path -LiteralPath (Join-Path $src $name) -PathType Leaf)) { throw "Fichier absent de la release : $name" }
    }
    if ((Get-Content -LiteralPath (Join-Path $src 'Installer-Verif963.ps1') -Raw) -notmatch '(?m)^\$DeploymentFormat = 2\s*$') {
        throw 'Release incompatible avec le deploiement transactionnel. Publiez une nouvelle release contenant les scripts corriges.'
    }
    $python = Get-Python
    if (-not $python) { Install-Python; $python = Get-Python }
    if (-not $python) { throw 'Python machine introuvable apres installation.' }
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
    # Protect code executed as SYSTEM and the SMTP configuration.
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $InstallDir -AclObject $acl
    # Existing explicit permissions must not allow modification of SYSTEM code.
    foreach ($item in Get-ChildItem -LiteralPath $InstallDir -Recurse -Force) {
        if ($item.PSIsContainer) { Set-Acl -LiteralPath $item.FullName -AclObject $acl }
        else {
            $fileAcl = New-Object Security.AccessControl.FileSecurity
            $fileAcl.SetAccessRuleProtection($true,$false)
            foreach ($sid in @('S-1-5-18','S-1-5-32-544')) {
                $fileAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','Allow')))
            }
            Set-Acl -LiteralPath $item.FullName -AclObject $fileAcl
        }
    }
    # venvs are created at the final path, never moved or modified in place.
    $runtime = Join-Path $InstallDir ('runtimes\' + [guid]::NewGuid().ToString('N'))
    Invoke-Python $python @('-m','venv',$runtime) | Out-Host
    $runtimePython = Join-Path $runtime 'Scripts\python.exe'
    Invoke-Python $runtimePython @('-m','ensurepip','--upgrade') | Out-Host
    Invoke-Python $runtimePython @('-m','pip','install','--disable-pip-version-check','-r',(Join-Path $src 'requirements.txt')) | Out-Host
    Invoke-Python $runtimePython @('-m','pip','check') | Out-Host
    $actual = (Invoke-Python $runtimePython @((Join-Path $src 'verif963.py'),'--version') | Out-String).Trim()
    if ($actual -ne $version.ToString()) { throw "Version du script ($actual) differente du tag ($version)." }
    Invoke-Python $runtimePython @('-m','py_compile',(Join-Path $src 'verif963.py')) | Out-Host
    $backup = Join-Path $InstallDir ('backup\' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $backup -ItemType Directory -Force | Out-Null
    foreach ($name in $files) {
        $path = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $backup }
    }
    if ($oldXml) { [IO.File]::WriteAllText((Join-Path $backup 'task.xml'),$oldXml) }
    if ($oldTask) { $stopped = $true; Wait-TaskStopped $TaskName }
    $changed = $true
    foreach ($name in $files | Where-Object { $_ -ne 'installation.json' }) {
        Copy-Item -LiteralPath (Join-Path $src $name) -Destination (Join-Path $InstallDir $name) -Force
    }
    $ini = Join-Path $InstallDir 'surveillance_963.ini'
    if (-not (Test-Path -LiteralPath $ini)) {
        $createdIni = $true
        Copy-Item -LiteralPath (Join-Path $src 'surveillance_963.ini.example') -Destination $ini
    }
    $action = New-ScheduledTaskAction -Execute $runtimePython -Argument ('"' + (Join-Path $InstallDir 'verif963.py') + '"') -WorkingDirectory $InstallDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $taskChanged = $true
    Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    if ($wasDisabled -or -not $oldTask) { Disable-ScheduledTask -TaskName $TaskName -TaskPath '\' | Out-Null }
    @{version=$version.ToString(); tag=$tag; python=$runtimePython} | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding UTF8
    if ($wasRunning) { Start-ScheduledTask -TaskName $TaskName -TaskPath '\' }
    Write-Host "Installation terminee : $version. Configuration conservee. Sauvegarde : $backup"
    Write-Host "Completez $ini puis activez et demarrez la tache $TaskName."
} catch {
    $failure = $_
    try {
        if ($taskChanged) {
            $current = Get-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction SilentlyContinue
            if ($current) { Wait-TaskStopped $TaskName }
        }
        if ($changed) {
            foreach ($name in $files) {
                $saved = Join-Path $backup $name
                $target = Join-Path $InstallDir $name
                if (Test-Path -LiteralPath $saved) { Copy-Item -LiteralPath $saved -Destination $target -Force }
                elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
            }
            if ($createdIni -and (Test-Path -LiteralPath (Join-Path $InstallDir 'surveillance_963.ini'))) { Remove-Item -LiteralPath (Join-Path $InstallDir 'surveillance_963.ini') -Force }
        }
        if ($taskChanged) {
            if ($oldXml) { Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -Xml $oldXml -Force | Out-Null }
            else { Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\' -Confirm:$false }
        }
        if ($wasRunning -and $stopped) { Start-ScheduledTask -TaskName $TaskName -TaskPath '\' }
    } catch { Write-Warning "Rollback incomplet : $_. Sauvegarde : $backup" }
    throw $failure
} finally {
    foreach ($temporary in @($zip,$tmpRoot)) {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # Keep previous and failed runtimes for diagnosis/manual rollback.
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
