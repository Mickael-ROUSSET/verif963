param([string]$InstallDir="C:\Users\Public\SupervisionMairie\Surveillance_963")
$ErrorActionPreference="Stop"; New-Item $InstallDir -ItemType Directory -Force | Out-Null
$repo="Mickael-ROUSSET/verif963"; $tag=(Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers @{"User-Agent"="verif963-installer"}).tag_name
if(-not $tag){throw "Aucune Release publiée."}; $tmp=Join-Path $env:TEMP "verif963-install.zip"; $dir=Join-Path $env:TEMP "verif963-install"
Invoke-WebRequest "https://github.com/$repo/archive/refs/tags/$tag.zip" -OutFile $tmp; Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue; Expand-Archive $tmp $dir -Force
$src=Get-ChildItem $dir -Directory|Select-Object -First 1; Copy-Item (Join-Path $src.FullName "verif963.py") $InstallDir -Force; Copy-Item (Join-Path $src.FullName "requirements.txt") $InstallDir -Force; Copy-Item (Join-Path $src.FullName "Maj-Verif963.ps1") $InstallDir -Force
if(-not(Test-Path (Join-Path $InstallDir "surveillance_963.ini"))){Copy-Item (Join-Path $src.FullName "surveillance_963.ini.example") (Join-Path $InstallDir "surveillance_963.ini")}
& python -m pip install -r (Join-Path $InstallDir "requirements.txt"); Write-Host "Installation terminée. Complétez surveillance_963.ini puis configurez la tâche planifiée."
