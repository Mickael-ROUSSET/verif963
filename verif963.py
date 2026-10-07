"""Surveillance Trend 963."""
import argparse, configparser, logging, smtplib, socket, subprocess, sys, time
from datetime import datetime
from email.mime.text import MIMEText
from email.utils import formataddr
from pathlib import Path
import psutil

VERSION = "1.1.0"
SCRIPT_DIR=Path(__file__).resolve().parent
CONFIG_FILE=SCRIPT_DIR/"surveillance_963.ini"

def clean(v):
    v=v.strip()
    if (v.startswith('r"') and v.endswith('"')) or (v.startswith("r'") and v.endswith("'")): v=v[2:-1]
    elif len(v)>=2 and v[0] in "'\"" and v[-1]==v[0]: v=v[1:-1]
    return v.strip()

def load_config():
    if not CONFIG_FILE.is_file(): raise FileNotFoundError(f"Configuration introuvable : {CONFIG_FILE}")
    c=configparser.ConfigParser(interpolation=None); c.read(str(CONFIG_FILE),encoding="utf-8")
    for s in ("GENERAL","SMTP"):
        if s not in c: raise KeyError(f"Section obligatoire absente : [{s}]")
    return c

def run():
    c=load_config(); g=c["GENERAL"]; s=c["SMTP"]
    pname=clean(g.get("process_name","s2.exe")); exe=clean(g["exe_path"]); wd=clean(g.get("working_dir",str(Path(exe).parent)))
    log=clean(g.get("log_file",str(SCRIPT_DIR/"surveillance_963.log"))); check=g.getint("check_interval_seconds",30)
    mailmin=g.getint("mail_alert_interval_minutes",15); maildelay=mailmin*60; retry=g.getint("restart_retry_interval_seconds",300)
    restart=g.getboolean("restart_enabled",False); verify=g.getint("restart_verification_delay_seconds",10); test=g.getboolean("send_test_mail_on_startup",False)
    host=socket.gethostname(); recipients=[clean(x) for x in s["mail_to"].split(",") if clean(x)]
    Path(log).parent.mkdir(parents=True,exist_ok=True); logging.basicConfig(filename=log,level=logging.INFO,format="%(asctime)s - %(levelname)s - %(message)s",encoding="utf-8")
    def active():
        for p in psutil.process_iter(["name"]):
            try:
                if (p.info.get("name") or "").lower()==pname.lower(): return True
            except (psutil.NoSuchProcess,psutil.AccessDenied,psutil.ZombieProcess): pass
        return False
    def mail(subject,body):
        m=MIMEText(body,"plain","utf-8"); m["Subject"]=subject; m["From"]=formataddr(("Surveillance Trend 963",clean(s.get("mail_from",s["username"])))); m["To"]=", ".join(recipients)
        with smtplib.SMTP(clean(s["server"]),s.getint("port",587),timeout=30) as srv:
            srv.ehlo()
            if s.getboolean("use_tls",True): srv.starttls(); srv.ehlo()
            srv.login(clean(s["username"]),clean(s["password"]).replace(" ","")); srv.sendmail(clean(s.get("mail_from",s["username"])),recipients,m.as_string())
    if test:
        try: mail(f"[CHAUFFERIE] Test verif963 {VERSION} - {host}",f"verif963 {VERSION} démarre.\nÉtat {pname}: {'ACTIF' if active() else 'ARRÊTÉ'}")
        except Exception: logging.exception("Échec mail de test")
    was=active(); lastmail=0.0; lastrestart=0.0
    logging.info("verif963 %s démarré; %s=%s",VERSION,pname,"actif" if was else "arrêté")
    while True:
        try:
            ok=active(); now=time.monotonic()
            if ok:
                if not was: logging.info("%s est de nouveau actif",pname); lastmail=lastrestart=0.0
                was=True
            else:
                if was: logging.error("Arrêt détecté : %s",pname)
                was=False; attempted=False; success=False; err=None
                if restart and (lastrestart==0 or now-lastrestart>=retry):
                    attempted=True; lastrestart=now
                    try:
                        subprocess.Popen([exe],cwd=wd,creationflags=subprocess.CREATE_NEW_CONSOLE); time.sleep(verify); success=active()
                        if not success: err=f"Processus absent après {verify} secondes."
                    except Exception as e: err=str(e); logging.exception("Échec redémarrage")
                if lastmail==0 or now-lastmail>=maildelay:
                    status="redémarré avec succès" if success else ("échec du redémarrage" if attempted else "aucun redémarrage tenté")
                    body=f"ALERTE CHAUFFERIE\n\nTrend 963 est arrêté : {status}.\nPoste : {host}\nDate : {datetime.now():%d/%m/%Y %H:%M:%S}\nProcessus : {pname}\nErreur : {err or '-'}\nVersion verif963 : {VERSION}"
                    try: mail(f"[CHAUFFERIE] Trend 963 arrêté - {host}",body); lastmail=now
                    except Exception: logging.exception("Échec envoi alerte")
            time.sleep(check)
        except KeyboardInterrupt: break
        except Exception: logging.exception("Erreur boucle"); time.sleep(check)

def main():
    p=argparse.ArgumentParser(); p.add_argument("--version",action="store_true"); a=p.parse_args()
    if a.version: print(VERSION); return
    run()
if __name__=="__main__": main()
