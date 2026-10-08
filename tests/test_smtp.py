"""Tests unitaires sans connexion SMTP réelle : python -m unittest discover -s tests -p 'test_*.py'"""
import configparser
import importlib.util
from pathlib import Path
from unittest import TestCase
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("verif963", Path(__file__).resolve().parents[1] / "verif963.py")
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class SmtpTests(TestCase):
    def settings(self, **kwargs):
        c = configparser.ConfigParser()
        c["SMTP"] = {"server": "smtp.example.test", "port": "587",
                     "username": "user@example.test", "password": "test secret",
                     "mail_to": "dest@example.test", **kwargs}
        return c["SMTP"]

    def test_legacy_starttls(self):
        self.assertEqual(app.smtp_security(self.settings(use_tls="true")), "starttls")

    def test_legacy_no_tls(self):
        self.assertEqual(app.smtp_security(self.settings(use_tls="false")), "none")

    def test_explicit_ssl_overrides_legacy(self):
        self.assertEqual(app.smtp_security(self.settings(security="ssl", use_tls="true")), "ssl")

    def test_invalid_security(self):
        with self.assertRaises(ValueError):
            app.smtp_security(self.settings(security="bogus"))

    def test_ssl_uses_smtp_ssl_without_starttls(self):
        with patch.object(app.smtplib, "SMTP_SSL") as factory:
            settings = self.settings(security="ssl", port="465")
            app.send_mail(settings, ["dest@example.test"], "test", "body")
            factory.assert_called_once()
            instance = factory.return_value.__enter__.return_value
            instance.starttls.assert_not_called()
            instance.login.assert_called_once_with("user@example.test", "testsecret")
            instance.sendmail.assert_called_once()

    def test_starttls_uses_smtp(self):
        with patch.object(app.smtplib, "SMTP") as factory:
            app.send_mail(self.settings(security="starttls"), ["dest@example.test"], "test", "body")
            instance = factory.return_value.__enter__.return_value
            instance.starttls.assert_called_once()
            instance.login.assert_called_once()
