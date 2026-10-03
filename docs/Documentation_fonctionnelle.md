# Documentation fonctionnelle

verif963 surveille périodiquement le processus Trend 963 `s2.exe`. En cas d'arrêt, il journalise l'incident, envoie une alerte SMTP et peut tenter un redémarrage si `restart_enabled=true`.

Les contrôles, mails et tentatives de redémarrage ont des temporisations indépendantes. Le fichier `surveillance_963.ini` reste local et n'est jamais remplacé par la mise à jour.

Le premier mail d'un nouvel arrêt est immédiat. Tant que l'arrêt persiste, les mails sont espacés de `mail_alert_interval_minutes`. Après retour du processus, les temporisations sont réinitialisées.
