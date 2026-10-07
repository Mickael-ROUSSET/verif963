# Revue technique de la PR 2

Demande : commentaire 6023532705. Corrections sur `installation-automatique`, sans fusion.

| Point | Defaut initial | Correction |
|---|---|---|
| Python | Presence du nom `python` suffisante, alias Store accepte, launcher utilisateur | Verification executable/version >= 3.9, registre machine, exclusion profils/WindowsApps |
| winget | Installation sans portee machine, inaccessible potentiellement a SYSTEM | Portee machine, source explicite, mode silencieux, controle du code et redetection |
| PowerShell 5.1 | Telechargement sans basic parsing, TLS implicite | `#requires`, TLS 1.2, `UseBasicParsing`, delais reseau |
| pip | Mutation globale et aucun amorcage de pip | venv neuf au chemin definitif, ensurepip, requirements, pip check |
| Tache | Ancienne definition conservee meme obsolete, limite standard de trois jours | Definition actualisee, Python absolu, duree illimitee, SYSTEM, etat preserve |
| Premiere installation | Tache active avant configuration | Nouvelle tache desactivee, activation explicite apres configuration |
| Espaces | Plusieurs appels avec chemins positionnels | Chemins litteraux, tableau d'arguments Python, chemin du script cite dans la tache |
| INI | Conservation annoncee | Conservation octet pour octet testee, suppression du nouvel INI en cas d'echec initial |
| Mise a jour | Sauvegarde sans restauration, pip modifie avant validation | Preparation independante, arret attendu, sauvegarde fichiers/XML, restauration automatique |
| Idempotence | Mise a jour deja a jour modifie pip global | Controle sans mutation des packages, verrou simultane, pas de downgrade implicite |
| Erreurs | Arret de tache silencieux, erreur originale masqueable | Arret controle, exception originale relancee, erreur de rollback signalee |
| Permissions | Code modifiable dans Public, execute en SYSTEM | ACL administrateurs/SYSTEM du dossier dedie et contenu, refus liens/jonctions |
| Releases | Bootstrap main mais payload ancienne release | Refus explicite d'une release sans moteur format 2, consigne nouvelle publication |

## Validation effectuee

- Suite sans dependance Pester executee avec le vrai Windows PowerShell 5.1 : dix scenarios (installation neuve, mise a jour d'une tache active, tache desactivee, archive incomplete, echec pip, version incoherente, echec copie, echec enregistrement, echec redemarrage, echec enregistrement initial).
- Reexecution de la mise a jour deja a jour, chemins avec espaces, INI binaire conserve, restauration des fichiers et de la tache precedents, suppression des nouveaux fichiers apres echec initial.
- Les interfaces reseau/Python/planificateur/ACL de cette suite sont simulees : elle teste les transitions du moteur, pas une installation reelle de winget ou SYSTEM.

## Validation terrain avant deploiement

Sur VM Windows 10 vierge (PowerShell 5.1), puis Windows 11 : tester absence de Python avec/sans winget, alias Store seul, Python utilisateur seul, Python machine existant, panne reseau/requirements, chemins avec espaces et redemarrage machine. Configurer l'INI, activer la tache, verifier SMTP, logs, acces fichiers et lancement sous SYSTEM. Valider aussi le remplacement d'une ancienne installation et une dependance defectueuse dans une release de test.

La release publique actuelle v1.0.0 ne contient pas le nouveau moteur : une nouvelle release incluant les corrections est requise apres validation. Aucun tag ni release n'a ete modifie. Le tag et VERSION devront etre incrementes ensemble lors de cette publication.

Le test `--version` verifie les imports et la version ; il ne valide pas SMTP, Trend ni les valeurs de l'INI. Le rollback gere les exceptions synchrones, pas une coupure brutale ; les sauvegardes et anciens runtimes permettent une restauration manuelle. Les ACL et l'installation machine de Python ne sont pas annulees. Les dependances restent non epinglees (`psutil>=5.9`), donc les nouveaux environnements peuvent varier entre deux dates ; chaque ancien environnement reste intact pour le rollback.

## Sources techniques

- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-5.1
- https://learn.microsoft.com/en-us/windows/package-manager/winget/install
- https://docs.python.org/3/library/venv.html

Le controle natif des objets ScheduledTasks dans cette session a ete refuse par Windows (acces CIM refuse). Aucun enregistrement reel de tache ni installation winget n'a donc ete effectue sur le poste de travail.

Verification Python reelle : creation d'un venv dans un chemin avec espaces, ensurepip, installation de psutil 7.2.2 depuis requirements.txt, pip check, --version (1.0.0) et py_compile reussis avec Python 3.14. La detection machine a aussi ete executee sous PowerShell 5.1.
