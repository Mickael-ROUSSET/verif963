param(
    [string]$InstallDir = "C:\Users\Public\SupervisionMairie\Surveillance_963",
    [string]$TaskName = "Surveillance Trend 963"
)
$ErrorActionPreference = "Stop"
$Repo = "Mickael-ROUSSET/verif963"

function Get-Python {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { return "py" }
    return $null
}

function Install-Python {
    Write-Host "Python n'est pas installé. Installation automatique..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "Python est absent et winget n'est pas disponible. Installez Python 3 puis relancez l'installateur."
    }
    & winget install --id Python.Python.3.13 -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "L'installation de Python par winget a échoué (code $LASTEXITCODE)." }
    $machine = [Environment]::GetEnvironmentVariable("Path","Machine")
    $user = [Environment]::GetEnvironmentVariable("Path","User")
    $env:Path = "$machine;$user"
}

function Invoke-Python([string[]]$Arguments) {
    $python = Get-Python
    if (-not $python) { Install-Python; $python = Get-Python }
    if (-not $python) {
        $candidates = @(
            "$env:LOCALAPPDATA\Programs\Python\Python313\python.exe",
            "$env:ProgramFiles\Python313\python.exe"
        )
        $python = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if (-not $python) { throw "Python a été installé mais reste introuvable. Fermez PowerShell, rouvrez-le puis relancez." }
    if ($python -eq "py") { & py -3 @Arguments } else { & $python @Arguments }
    if ($LASTEXITCODE -ne 0) { throw "Python a retourné le code $LASTEXITCODE." }
}

Write-Host "=== Installation de verif963 ==="
New-Item $InstallDir -ItemType Directory -Force | Out-Null

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{"User-Agent"="verif963-installer"}
$tag = $release.tag_name
if (-not $tag) { throw "Aucune Release verif963 publiée." }
Write-Host "Release sélectionnée : $tag"

$tmpRoot = Join-Path $env:TEMP ("verif963-install-" + [guid]::NewGuid().ToString("N"))
$zip = "$tmpRoot.zip"
try {
    Invoke-WebRequest -Uri "https://github.com/$Repo/archive/refs/tags/$tag.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmpRoot -Force
    $src = Get-ChildItem $tmpRoot -Directory | Select-Object -First 1
    if (-not $src) { throw "Archive GitHub invalide." }

    foreach ($name in @("verif963.py","requirements.txt","Maj-Verif963.ps1","surveillance_963.ini.example")) {
        $source = Join-Path $src.FullName $name
        if (-not (Test-Path $source)) { throw "Fichier absent de la Release : $name" }
    }

    Copy-Item (Join-Path $src.FullName "verif963.py") $InstallDir -Force
    Copy-Item (Join-Path $src.FullName "requirements.txt") $InstallDir -Force
    Copy-Item (Join-Path $src.FullName "Maj-Verif963.ps1") $InstallDir -Force
    Copy-Item (Join-Path $src.FullName "surveillance_963.ini.example") $InstallDir -Force

    $ini = Join-Path $InstallDir "surveillance_963.ini"
    if (-not (Test-Path $ini)) {
        Copy-Item (Join-Path $src.FullName "surveillance_963.ini.example") $ini
        Write-Host "Configuration locale créée : $ini"
    } else {
        Write-Host "Configuration locale existante conservée."
    }

    Write-Host "Installation des packages Python..."
    Invoke-Python @("-m","pip","install","--upgrade","pip")
    Invoke-Python @("-m","pip","install","-r",(Join-Path $InstallDir "requirements.txt"))

    Write-Host "Test de verif963..."
    Invoke-Python @((Join-Path $InstallDir "verif963.py"),"--version")

    $python = Get-Python
    if ($python -eq "py") { $taskExe = (Get-Command py).Source; $taskArgs = '-3 "' + (Join-Path $InstallDir "verif963.py") + '"' }
    else { $taskExe = $python; $taskArgs = '"' + (Join-Path $InstallDir "verif963.py") + '"' }

    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Tâche planifiée existante conservée : $TaskName"
    } else {
        $action = New-ScheduledTaskAction -Execute $taskExe -Argument $taskArgs -WorkingDirectory $InstallDir
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -User "SYSTEM" | Out-Null
        Write-Host "Tâche planifiée créée : $TaskName"
    }

    Write-Host ""
    Write-Host "Installation terminée."
    Write-Host "Répertoire : $InstallDir"
    Write-Host "IMPORTANT : complétez surveillance_963.ini (SMTP, chemins), puis démarrez la tâche."
    Write-Host "Le redémarrage automatique de Trend reste désactivé par défaut."
}
finally {
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
