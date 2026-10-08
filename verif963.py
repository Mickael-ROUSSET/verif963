"""Surveillance Trend 963."""
import argparse
import configparser
import logging
import smtplib
import socket
import ssl
import subprocess
import time
from datetime import datetime
from email.mime.text import MIMEText
from email.utils import formataddr
from pathlib import Path

import psutil

VERSION = "1.1.1"
SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_FILE = SCRIPT_DIR / "surveillance_963.ini"


def clean(value):
    value = value.strip()
    if (value.startswith('r"') and value.endswith('"')) or (value.startswith("r'") and value.endswith("'")):
        value = value[2:-1]
    elif len(value) >= 2 and value[0] in ("\'", '"') and value[-1] == value[0]:
        value = value[1:-1]
    return value.strip()


def load_config():
    if not CONFIG_FILE.is_file():
        raise FileNotFoundError(f"Configuration introuvable : {CONFIG_FILE}")
    config = configparser.ConfigParser(interpolation=None)
    config.read(str(CONFIG_FILE), encoding="utf-8")
    for section in ("GENERAL", "SMTP"):
        if section not in config:
            raise KeyError(f"Section obligatoire absente : [{section}]")
    return config


def smtp_security(settings):
    """Compatibilite avec use_tls des configurations existantes."""
    explicit = clean(settings.get("security", "")).lower()
    if explicit:
        if explicit not in ("ssl", "starttls", "none"):
            raise ValueError("SMTP security doit etre ssl, starttls ou none")
        return explicit
    return "starttls" if settings.getboolean("use_tls", True) else "none"


def send_mail(settings, recipients, subject, body):
    mode = smtp_security(settings)
    port = settings.getint("port", 465 if mode == "ssl" else 587)
    message = MIMEText(body, "plain", "utf-8")
    sender = clean(settings.get("mail_from", settings["username"]))
    message["Subject"] = subject
    message["From"] = formataddr(("Surveillance Trend 963", sender))
    message["To"] = ", ".join(recipients)
    server = clean(settings["server"])
    context = ssl.create_default_context()
    if mode == "ssl":
        connection = smtplib.SMTP_SSL(server, port, timeout=30, context=context)
    else:
        connection = smtplib.SMTP(server, port, timeout=30)
    with connection as smtp:
        smtp.ehlo()
        if mode == "starttls":
            smtp.starttls(context=context)
            smtp.ehlo()
        smtp.login(clean(settings["username"]), clean(settings["password"]).replace(" ", ""))
        smtp.sendmail(sender, recipients, message.as_string())


def run():
    config = load_config()
    general, smtp = config["GENERAL"], config["SMTP"]
    process_name = clean(general.get("process_name", "s2.exe"))
    executable = clean(general["exe_path"])
    workdir = clean(general.get("working_dir", str(Path(executable).parent)))
    logfile = clean(general.get("log_file", str(SCRIPT_DIR / "surveillance_963.log")))
    interval = general.getint("check_interval_seconds", 30)
    mail_delay = general.getint("mail_alert_interval_minutes", 15) * 60
    restart_delay = general.getint("restart_retry_interval_seconds", 300)
    restart_enabled = general.getboolean("restart_enabled", False)
    verify_delay = general.getint("restart_verification_delay_seconds", 10)
    startup_mail = general.getboolean("send_test_mail_on_startup", False)
    failures_required = general.getint("consecutive_failures_required", 2)
    if interval <= 0 or mail_delay <= 0 or restart_delay <= 0 or verify_delay < 0 or failures_required < 1:
        raise ValueError("Intervalles et seuil de detection invalides")
    recipients = [clean(item) for item in smtp["mail_to"].split(",") if clean(item)]
    host = socket.gethostname()
    Path(logfile).parent.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=logfile, level=logging.INFO,
                        format="%(asctime)s - %(levelname)s - %(message)s", encoding="utf-8")

    def active():
        for proc in psutil.process_iter(["name"]):
            try:
                if (proc.info.get("name") or "").lower() == process_name.lower():
                    return True
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                pass
        return False

    def mail(subject, body):
        send_mail(smtp, recipients, subject, body)

    if startup_mail:
        try:
            mail(f"[CHAUFFERIE] Test verif963 {VERSION} - {host}",
                 f"verif963 {VERSION} démarre.\nÉtat {process_name}: {'ACTIF' if active() else 'ARRÊTÉ'}")
        except Exception:
            logging.exception("Échec mail de test")

    running = active()
    confirmed_outage = False
    failures = 0 if running else 1
    last_mail = 0.0
    last_restart = 0.0
    logging.info("verif963 %s démarré; %s=%s", VERSION, process_name,
                 "actif" if running else "arrêté")

    while True:
        try:
            is_running = active()
            now = time.monotonic()
            if is_running:
                failures = 0
                if confirmed_outage:
                    logging.info("%s est de nouveau actif", process_name)
                    try:
                        mail(f"[CHAUFFERIE] Trend 963 rétabli - {host}",
                             f"RETOUR À LA NORMALE\n\nProcessus : {process_name}\n"
                             f"Poste : {host}\nDate : {datetime.now():%d/%m/%Y %H:%M:%S}\n"
                             f"Version verif963 : {VERSION}")
                    except Exception:
                        logging.exception("Échec envoi mail de rétablissement")
                    last_mail = last_restart = 0.0
                confirmed_outage = False
            else:
                failures += 1
                if not confirmed_outage and failures < failures_required:
                    logging.warning("%s absent : contrôle %s/%s", process_name,
                                    failures, failures_required)
                else:
                    if not confirmed_outage:
                        logging.error("Arrêt confirmé : %s (%s contrôles)", process_name, failures)
                        confirmed_outage = True
                    attempted, success, error = False, False, None
                    if restart_enabled and (last_restart == 0 or now - last_restart >= restart_delay):
                        attempted = True
                        last_restart = now
                        try:
                            subprocess.Popen([executable], cwd=workdir,
                                             creationflags=subprocess.CREATE_NEW_CONSOLE)
                            time.sleep(verify_delay)
                            success = active()
                            if not success:
                                error = f"Processus absent après {verify_delay} secondes."
                        except Exception as exc:
                            error = str(exc)
                            logging.exception("Échec redémarrage")
                    if last_mail == 0 or now - last_mail >= mail_delay:
                        status = ("redémarré avec succès" if success else
                                  "échec du redémarrage" if attempted else "aucun redémarrage tenté")
                        body = (f"ALERTE CHAUFFERIE\n\nTrend 963 est arrêté : {status}.\n"
                                f"Poste : {host}\nDate : {datetime.now():%d/%m/%Y %H:%M:%S}\n"
                                f"Processus : {process_name}\nErreur : {error or '-'}\n"
                                f"Version verif963 : {VERSION}")
                        try:
                            mail(f"[CHAUFFERIE] Trend 963 arrêté - {host}", body)
                            last_mail = now
                        except Exception:
                            logging.exception("Échec envoi alerte")
            time.sleep(interval)
        except KeyboardInterrupt:
            break
        except Exception:
            logging.exception("Erreur boucle")
            time.sleep(interval)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", action="store_true")
    args = parser.parse_args()
    if args.version:
        print(VERSION)
        return
    run()


if __name__ == "__main__":
    main()
