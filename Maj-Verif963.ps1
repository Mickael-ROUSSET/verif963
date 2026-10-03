param([string]$InstallDir="C:\Users\Public\SupervisionMairie\Surveillance_963",[string]$TaskName="Surveillance Trend 963")
$ErrorActionPreference="Stop"; $Repo="Mickael-ROUSSET/verif963"
Write-Host "Mise à jour verif963 - dépôt public $Repo"
$release=Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers @{"User-Agent"="verif963-updater"}
$tag=$release.tag_name; if(-not $tag){throw "Release GitHub introuvable."}
$local="0.0.0"; $py=Join-Path $InstallDir "verif963.py"
if(Test-Path $py){try{$local=(& python $py --version 2>$null).Trim()}catch{}}
$remote=$tag.TrimStart("v"); Write-Host "Version installée : $local"; Write-Host "Dernière release : $remote"
if([version]$local -ge [version]$remote){Write-Host "Aucune mise à jour nécessaire."; exit 0}
$tmp=Join-Path $env:TEMP "verif963-$remote.zip"; $unpack=Join-Path $env:TEMP "verif963-$remote"
Invoke-WebRequest -Uri "https://github.com/$Repo/archive/refs/tags/$tag.zip" -OutFile $tmp
Remove-Item $unpack -Recurse -Force -ErrorAction SilentlyContinue; Expand-Archive $tmp -DestinationPath $unpack -Force
$src=Get-ChildItem $unpack -Directory | Select-Object -First 1
New-Item $InstallDir -ItemType Directory -Force | Out-Null
$backup=Join-Path $InstallDir ("backup\"+(Get-Date -Format "yyyyMMdd-HHmmss")); New-Item $backup -ItemType Directory -Force | Out-Null
Get-ChildItem $InstallDir -File | Where-Object {$_.Name -ne "surveillance_963.ini"} | Copy-Item -Destination $backup -Force
try{Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue}catch{}
foreach($name in @("verif963.py","requirements.txt","Maj-Verif963.ps1")){Copy-Item (Join-Path $src.FullName $name) (Join-Path $InstallDir $name) -Force}
if(-not (Test-Path (Join-Path $InstallDir "surveillance_963.ini"))){Copy-Item (Join-Path $src.FullName "surveillance_963.ini.example") (Join-Path $InstallDir "surveillance_963.ini")}
& python -m pip install -r (Join-Path $InstallDir "requirements.txt")
try{Start-ScheduledTask -TaskName $TaskName; Write-Host "Tâche relancée."}catch{Write-Warning "Tâche non relancée : $($_.Exception.Message)"}
Write-Host "Mise à jour terminée vers $remote. Configuration locale conservée."
