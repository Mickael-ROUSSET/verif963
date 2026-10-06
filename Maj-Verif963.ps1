param(
    [string]$InstallDir = "C:\Users\Public\SupervisionMairie\Surveillance_963",
    [string]$TaskName = "Surveillance Trend 963"
)
$ErrorActionPreference="Stop"
$Repo="Mickael-ROUSSET/verif963"

function Invoke-Python([string[]]$Arguments) {
    if (Get-Command python -ErrorAction SilentlyContinue) { & python @Arguments }
    elseif (Get-Command py -ErrorAction SilentlyContinue) { & py -3 @Arguments }
    else { throw "Python est introuvable. Relancez Installer-Verif963.ps1." }
    if ($LASTEXITCODE -ne 0) { throw "Python a retourné le code $LASTEXITCODE." }
}

Write-Host "=== Mise à jour verif963 ==="
$release=Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{"User-Agent"="verif963-updater"}
$tag=$release.tag_name
if(-not $tag){throw "Release GitHub introuvable."}
$remote=$tag.TrimStart("v")
$py=Join-Path $InstallDir "verif963.py"
$local="0.0.0"
if(Test-Path $py){ try { $local=(Invoke-Python @($py,"--version") | Out-String).Trim() } catch { $local="0.0.0" } }
Write-Host "Version installée : $local"
Write-Host "Dernière Release : $remote"
if([version]$local -ge [version]$remote){
    Write-Host "Le programme est à jour."
    Invoke-Python @("-m","pip","install","-r",(Join-Path $InstallDir "requirements.txt"))
    exit 0
}

$tmpRoot=Join-Path $env:TEMP ("verif963-update-"+[guid]::NewGuid().ToString("N"))
$zip="$tmpRoot.zip"
$backup=Join-Path $InstallDir ("backup\"+(Get-Date -Format "yyyyMMdd-HHmmss"))
$task=Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$wasRunning=$task -and $task.State -eq "Running"
try {
    Invoke-WebRequest -Uri "https://github.com/$Repo/archive/refs/tags/$tag.zip" -OutFile $zip
    Expand-Archive $zip $tmpRoot -Force
    $src=Get-ChildItem $tmpRoot -Directory|Select-Object -First 1
    New-Item $backup -ItemType Directory -Force|Out-Null
    Get-ChildItem $InstallDir -File | Where-Object {$_.Name -ne "surveillance_963.ini"} | Copy-Item -Destination $backup -Force
    if($task){Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue}
    foreach($name in @("verif963.py","requirements.txt","Maj-Verif963.ps1","surveillance_963.ini.example")){
        Copy-Item (Join-Path $src.FullName $name) (Join-Path $InstallDir $name) -Force
    }
    if(-not(Test-Path (Join-Path $InstallDir "surveillance_963.ini"))){
        Copy-Item (Join-Path $src.FullName "surveillance_963.ini.example") (Join-Path $InstallDir "surveillance_963.ini")
    }
    Invoke-Python @("-m","pip","install","-r",(Join-Path $InstallDir "requirements.txt"))
    Invoke-Python @((Join-Path $InstallDir "verif963.py"),"--version")
    if($task -and $wasRunning){Start-ScheduledTask -TaskName $TaskName}
    Write-Host "Mise à jour terminée vers $remote. Configuration locale conservée."
}
catch {
    Write-Error $_
    throw
}
finally {
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
}
