# Changelog

## 1.1.1
- Le seuil de 1 déclenche l'alerte dès l'observation initiale négative.
- Mail de rétablissement conservé en mémoire après échec SMTP, avec nouvelles tentatives espacées d'au moins 60 secondes (ou l'intervalle de contrôle s'il est plus long). L'attente est supprimée après succès ou remplacée par une nouvelle panne confirmée ; elle ne survit pas au redémarrage du programme.
- SMTP SSL/TLS implicite (port 465, Orange) et STARTTLS (port 587, Gmail), compatible avec l'ancien paramètre `use_tls`.
- Arrêt confirmé après deux contrôles négatifs consécutifs (seuil configurable).
- Mail de rétablissement après une panne confirmée lorsque Trend redevient actif.
- Le redémarrage automatique de Trend reste désactivé par défaut.

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
