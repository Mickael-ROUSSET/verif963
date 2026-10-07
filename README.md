# verif963

Surveillance de Trend 963 sous Windows 10/11, avec Windows PowerShell 5.1 ou PowerShell 7.

## Installation sur un nouveau PC

Ouvrir PowerShell **en tant qu'administrateur**. Le dossier choisi doit etre local, dedie a verif963 et sans jonctions/liens. L'installation reserve ses permissions a SYSTEM et aux administrateurs, y compris les fichiers existants et les secrets SMTP. Ne pas choisir un dossier contenant d'autres applications ou documents.

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$installer = Join-Path $env:TEMP 'Installer-Verif963.ps1'
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/Mickael-ROUSSET/verif963/main/Installer-Verif963.ps1 -OutFile $installer
& $installer
```

Pour un chemin personnalise : `& $installer -InstallDir 'C:\Supervision mairie\Trend 963' -TaskName 'Surveillance Trend 963'`.

**Publication requise :** cette PR doit etre validee avant publication d'une nouvelle release contenant ces scripts (format de deploiement 2). Le script refuse les anciennes releases pour ne pas reinstaller un ancien moteur de mise a jour. Le tag `vX.Y.Z` doit correspondre a `VERSION` dans `verif963.py`. Pendant la revue, l'URL `main` ci-dessus ne contient pas encore ces corrections. Aucun tag existant n'est modifie.

L'installateur valide l'archive complete avant de modifier les fichiers actifs. Il selectionne un executable Python >= 3.9 installe pour la machine, en verifiant reellement son fonctionnement. Les alias Microsoft Store et installations dans les profils utilisateurs sont exclus car la tache utilise SYSTEM. S'il manque, winget installe `Python.Python.3.13` avec `--scope machine`. Si winget manque ou echoue, installer Python pour tous les utilisateurs puis relancer ; le message d'erreur precise la cause.

Les dependances sont installees dans un environnement `runtimes\<identifiant>` propre a chaque deploiement : `venv`, `ensurepip`, `pip install -r requirements.txt`, `pip check`, compilation du script et controle de version. Le Python global et les anciens environnements ne sont pas modifies. Les chemins avec espaces sont pris en charge.

Le fichier local `surveillance_963.ini` est cree uniquement s'il manque. Apres l'installation, ouvrir ce fichier avec un editeur administrateur, completer SMTP et les chemins Trend. La nouvelle tache est **desactivee** jusqu'a cette configuration :

```powershell
Enable-ScheduledTask -TaskName 'Surveillance Trend 963' -TaskPath '\'
Start-ScheduledTask -TaskName 'Surveillance Trend 963' -TaskPath '\'
```

La tache utilise le chemin absolu du Python isole, le dossier de travail de l'application, un declencheur au demarrage, trois tentatives de relance et aucune limite de duree d'execution. Le redemarrage automatique de Trend reste desactive dans la configuration par defaut. SYSTEM s'execute sans session graphique interactive : valider sur le poste reel avant d'activer le redemarrage de Trend.

## Mise a jour et restauration

Depuis PowerShell administrateur :

```powershell
& 'C:\Users\Public\SupervisionMairie\Surveillance_963\Maj-Verif963.ps1'
```

Passer les memes `-InstallDir` et `-TaskName` pour une installation personnalisee. L'updater utilise le meme moteur transactionnel que l'installation. Une ancienne installation sans ce moteur doit etre migree en relancant le nouvel installateur apres publication de la release.

Une mise a jour deja a jour verifie l'environnement et la version sans reinstaller les packages. Une version locale plus recente n'est pas retrogradee automatiquement. Relancer l'installateur permet de reparer ou reconfigurer une installation ; il remplace la definition de la tache geree et conserve son etat desactive ou en cours d'execution. Utiliser un nom de tache dedie.

Le telechargement et les dependances sont prepares avant l'arret de la tache. Les fichiers geres et la definition XML precedente sont sauvegardes dans `backup\<identifiant>`. En cas d'erreur apres remplacement, les fichiers, l'ancien environnement via la definition de la tache et son etat actif sont restaures. L'INI existant n'est jamais recopie ni modifie. Si la restauration echoue elle-meme, le script le signale et indique la sauvegarde ; une intervention manuelle est alors necessaire. Python installe par winget et les permissions de securite ne sont pas annules. Une coupure brutale du PC/processus peut aussi necessiter une restauration manuelle.

Les anciens environnements et sauvegardes sont conserves pour diagnostic/restauration. Les supprimer uniquement apres validation, sans supprimer l'environnement reference par `installation.json` ou une sauvegarde encore necessaire. Un verrou empeche deux deploiements simultanes du meme dossier. Les archives temporaires sont nettoyees dans tous les cas.

## Verification

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Installer.Tests.ps1
```

Les tests simulent GitHub, pip et le planificateur sans installation machine. Les validations reelles sur une VM Windows 10 vierge restent necessaires pour winget, les ACL et le lancement sous SYSTEM. Voir `docs/Revue_installation.md`.
