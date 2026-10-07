# Changelog

## 1.1.0
- Installation « une commande » sur un nouveau PC Windows.
- Installation automatique de Python via winget lorsqu'il est absent.
- Environnement virtuel Python isolé et installation automatique des dépendances.
- Création/actualisation de la tâche planifiée SYSTEM sans limite de durée.
- Conservation exacte de la configuration locale `surveillance_963.ini`.
- Mise à jour transactionnelle avec sauvegarde et restauration en cas d'échec.
- Compatibilité Windows PowerShell 5.1, TLS 1.2 et chemins contenant des espaces.
- Verrou contre les déploiements simultanés et absence de downgrade automatique.
- Tests de panne et documentation de revue d'installation.

## 1.0.0
- Surveillance de s2.exe.
- Alertes SMTP temporisées.
- Redémarrage automatique optionnel.
- Configuration INI locale.
- Installation et mise à jour depuis les Releases publiques.
