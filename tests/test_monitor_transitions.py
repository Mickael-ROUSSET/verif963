"""Scenarios de surveillance simules sans Trend ni reseau."""
import configparser
import importlib.util
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import TestCase
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("verif963", Path(__file__).resolve().parents[1] / "verif963.py")
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class MonitorTransitionsTests(TestCase):
    def scenario(self, states, threshold):
        """states: observation initiale, puis une observation par passage de boucle."""
        config = configparser.ConfigParser()
        with TemporaryDirectory() as directory:
            config["GENERAL"] = {
                "exe_path": r"C:\Trend\s2.exe",
                "log_file": str(Path(directory) / "verif963.log"),
                "check_interval_seconds": "1",
                "consecutive_failures_required": str(threshold),
                "restart_enabled": "false",
                "send_test_mail_on_startup": "false",
            }
            config["SMTP"] = {
                "server": "example.test", "username": "x@example.test",
                "password": "no-password-used", "mail_to": "dest@example.test",
            }
            observed = iter(states)
            subjects = []

            def process_list(_attributes):
                running = next(observed)
                return [type("Process", (), {"info": {"name": "s2.exe"}})()] if running else []

            def capture_mail(_settings, _recipients, subject, _body):
                subjects.append(subject)

            with patch.object(app, "load_config", return_value=config), \
                 patch.object(app.psutil, "process_iter", side_effect=process_list), \
                 patch.object(app, "send_mail", side_effect=capture_mail), \
                 patch.object(app.time, "sleep", side_effect=KeyboardInterrupt), \
                 patch.object(app.logging, "basicConfig"):
                app.run()
        return subjects

    def test_startup_absent_then_restored_before_threshold(self):
        self.assertEqual(self.scenario([False, True], threshold=3), [])

    def test_startup_absent_below_high_threshold(self):
        self.assertEqual(self.scenario([False, False], threshold=5), [])

    def test_startup_absent_reaches_threshold(self):
        subjects = self.scenario([False, False], threshold=2)
        self.assertEqual(len(subjects), 1)
        self.assertIn("arrêté", subjects[0])

    def test_running_then_first_miss_is_not_outage(self):
        self.assertEqual(self.scenario([True, False], threshold=2), [])

    def test_running_then_recovery_without_confirmed_outage(self):
        # Une seule observation de panne: aucun mail de panne ni de retablissement.
        self.assertEqual(self.scenario([True, False], threshold=2), [])
