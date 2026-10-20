# Documentation technique

Python >= 3.9 + `psutil`. Configuration via `configparser`, SMTP via `smtplib`, lancement via `subprocess.Popen`, delais via `time.monotonic()`.

`verif963.py --version` affiche la version et verifie les imports. `Maj-Verif963.ps1` delegue au moteur transactionnel `Installer-Verif963.ps1`. Le moteur interroge la derniere release publique, valide l'archive, prepare un environnement Python neuf, sauvegarde les fichiers geres et la definition XML de la tache, puis applique le deploiement. Les erreurs synchrones declenchent une restauration. `surveillance_963.ini` existant reste intact.

La tache utilise SYSTEM, un chemin Python absolu et aucun temps maximal d'execution. Les dossiers de l'installation sont reserves aux administrateurs et SYSTEM. Le redemarrage de Trend s'effectue hors session graphique interactive ; valider ce comportement sur le poste cible. En cas de probleme CrypKey, conserver `restart_enabled=false` jusqu'au retablissement d'un lancement manuel normal.

Voir README.md et Revue_installation.md pour les commandes, la publication d'une release compatible, les sauvegardes et les limites de validation.

La fonction active() émet une unique ligne INFO après une observation réussie de l'état. Le résultat mis en cache pour le seuil 1 n'émet pas de seconde ligne. Les appels existants du mail de test et de la vérification de redémarrage restent instrumentés sans nouvelle interrogation. Le FileHandler existant configuré par basicConfig conserve UTF-8 et le mode ajout ; aucune rotation n'est installée. Les tests couvrent états, transitions, correspondance observations/logs, délais et réouverture du fichier après fermeture des handlers.
