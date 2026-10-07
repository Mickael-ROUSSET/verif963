# Changelog

## Prochaine version
- Installation « une commande » sur un nouveau PC Windows.
- Installation automatique de Python via winget lorsqu'il est absent.
- Installation automatique des dépendances Python.
- Création automatique de la tâche planifiée de surveillance.
- Mise à jour des dépendances lors des mises à jour.
- Conservation de la configuration locale.

## 1.0.0
- Surveillance de s2.exe.
- Alertes SMTP temporisées.
- Redémarrage automatique optionnel.
- Configuration INI locale.
- Installation et mise à jour depuis les Releases publiques.

## Corrections de la revue PR 2
- Detection Python machine, winget machine, compatibilite PowerShell 5.1.
- Environnements Python isoles, mise a jour transactionnelle et restauration.
- Tache SYSTEM actualisee sans limite de duree, activation initiale manuelle.
- Permissions protegees, configuration preservee et tests de panne.
