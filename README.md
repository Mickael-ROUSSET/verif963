# verif963

Surveillance de Trend 963 sous Windows.

## Installation simple sur un nouveau PC

Ouvrir **PowerShell en tant qu'administrateur**, puis exécuter :

```powershell
irm https://raw.githubusercontent.com/Mickael-ROUSSET/verif963/main/Installer-Verif963.ps1 | iex
```

L'installateur :
- télécharge la dernière Release publique ;
- détecte Python et l'installe avec `winget` s'il manque ;
- installe automatiquement les packages de `requirements.txt` ;
- installe verif963 dans `C:\Users\Public\SupervisionMairie\Surveillance_963` ;
- crée `surveillance_963.ini` uniquement s'il n'existe pas ;
- crée la tâche planifiée `Surveillance Trend 963` si nécessaire ;
- vérifie la version installée.

Après la première installation, compléter `surveillance_963.ini`, notamment les paramètres SMTP et les chemins Trend. Le redémarrage automatique de Trend est désactivé par défaut.

## Mise à jour

Depuis PowerShell administrateur :

```powershell
& "C:\Users\Public\SupervisionMairie\Surveillance_963\Maj-Verif963.ps1"
```

Le fichier local `surveillance_963.ini` est conservé pendant les mises à jour.
