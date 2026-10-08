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
    def scenario(self, states, threshold, recovery_failures=0, times=None):
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
            self.attempts = []
            clock = {"index": 0, "observations": 0}
            loops = len(states) - 1 + int(not states[0] and threshold == 1)
            times = times or list(range(loops))
            self.assertEqual(len(times), loops)

            def process_list(_attributes):
                running = next(observed)
                clock["observations"] += 1
                return [type("Process", (), {"info": {"name": "s2.exe"}})()] if running else []

            def capture_mail(_settings, _recipients, subject, _body):
                nonlocal recovery_failures
                self.attempts.append((subject, times[clock["index"]], clock["observations"], _body))
                if "rétabli" in subject and recovery_failures:
                    recovery_failures -= 1
                    raise OSError("SMTP temporairement indisponible")
                subjects.append(subject)

            def sleep(_seconds):
                clock["index"] += 1
                if clock["index"] >= loops:
                    raise KeyboardInterrupt()

            with patch.object(app, "load_config", return_value=config), \
                 patch.object(app.psutil, "process_iter", side_effect=process_list), \
                 patch.object(app, "send_mail", side_effect=capture_mail), \
                 patch.object(app.time, "sleep", side_effect=sleep), \
                 patch.object(app.time, "monotonic", side_effect=lambda: times[clock["index"]]), \
                 patch.object(app.logging, "basicConfig"):
                app.run()
        return subjects

    def test_threshold_one_alerts_before_second_observation(self):
        subjects = self.scenario([False, True], threshold=1)
        self.assertIn("arrêté", subjects[0])
        self.assertIn("rétabli", subjects[1])
        self.assertEqual(self.attempts[0][2], 1)

    def test_threshold_one_initial_absence_alone_sends_alert(self):
        subjects = self.scenario([False], threshold=1)
        self.assertEqual(len(subjects), 1)
        self.assertIn("arrêté", subjects[0])

    def test_recovery_retries_after_delay_and_stops_after_success(self):
        subjects = self.scenario([True, False, False, True, True, True, True],
                                 threshold=2, recovery_failures=1,
                                 times=[10, 11, 12, 30, 72, 90])
        attempts = [attempt for attempt in self.attempts if "rétabli" in attempt[0]]
        self.assertEqual([attempt[1] for attempt in attempts], [12, 72])
        self.assertEqual(attempts[0][3], attempts[1][3])
        self.assertEqual(sum("rétabli" in subject for subject in subjects), 1)

    def test_recovery_repeated_failures_remain_pending(self):
        subjects = self.scenario([True, False, False, True, True, True, True, True],
                                 threshold=2, recovery_failures=2,
                                 times=[10, 11, 12, 72, 100, 132, 150])
        attempts = [attempt for attempt in self.attempts if "rétabli" in attempt[0]]
        self.assertEqual([attempt[1] for attempt in attempts], [12, 72, 132])
        self.assertEqual(sum("rétabli" in subject for subject in subjects), 1)

    def test_startup_absent_then_restored_before_threshold(self):
        self.assertEqual(self.scenario([False, True], threshold=3), [])

    def test_startup_absent_below_high_threshold(self):
        self.assertEqual(self.scenario([False, False, False, False], threshold=5), [])

    def test_startup_absent_reaches_threshold(self):
        subjects = self.scenario([False, False], threshold=2)
        self.assertEqual(len(subjects), 1)
        self.assertIn("arrêté", subjects[0])

    def test_running_then_first_miss_is_not_outage(self):
        self.assertEqual(self.scenario([True, False], threshold=2), [])

    def test_running_then_recovery_without_confirmed_outage(self):
        # Une seule observation de panne: aucun mail de panne ni de retablissement.
        self.assertEqual(self.scenario([True, False, True], threshold=2), [])

    def test_confirmed_outage_then_recovery_emits_two_mails(self):
        subjects = self.scenario([True, False, False, True], threshold=2)
        self.assertEqual(len(subjects), 2)
        self.assertIn("arrêté", subjects[0])
        self.assertIn("rétabli", subjects[1])

    def test_startup_absent_then_recovery_emits_two_mails(self):
        subjects = self.scenario([False, False, True], threshold=2)
        self.assertEqual(len(subjects), 2)
        self.assertIn("arrêté", subjects[0])
        self.assertIn("rétabli", subjects[1])
