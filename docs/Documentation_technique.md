# Documentation technique

Python 3 + `psutil`. Configuration via `configparser`; SMTP via `smtplib`; lancement via `subprocess.Popen`; délais via `time.monotonic()`.

`verif963.py --version` affiche la version installée. `Maj-Verif963.ps1` interroge l'API publique GitHub `/releases/latest`, compare les versions, sauvegarde les fichiers applicatifs, conserve `surveillance_963.ini`, installe les dépendances et relance la tâche `Surveillance Trend 963`.

Le redémarrage automatique nécessite les droits Windows appropriés. En présence d'un problème CrypKey, conserver `restart_enabled=false` jusqu'à rétablissement d'un lancement manuel normal de Trend 963.
