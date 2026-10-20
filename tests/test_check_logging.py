"""Un log INFO par observation réelle, sans toucher aux mails ni à la cadence."""
import configparser
import importlib.util
import logging
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest import TestCase
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("logging_app", Path(__file__).resolve().parents[1] / "verif963.py")
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


class CheckLoggingTests(TestCase):
    def scenario(self, states, *, threshold=2, startup_mail=False, restart=False):
        config = configparser.ConfigParser(interpolation=None)
        config["GENERAL"] = {
            "exe_path": r"C:\Trend\s2.exe", "check_interval_seconds": "30",
            "consecutive_failures_required": str(threshold),
            "restart_enabled": str(restart), "restart_verification_delay_seconds": "10",
            "send_test_mail_on_startup": str(startup_mail),
        }
        config["SMTP"] = {"mail_to": "dest@example.test"}
        observations = iter(states)
        clock = {"now": 100.0}
        probes = []
        entries = []
        delays = []
        mails = []
        sleeps = []
        # Normal loop probes exclude the initial check; threshold=1 reuses that check.
        loop_count = len(states) - 1 + int(not states[0] and threshold == 1)
        if startup_mail:
            loop_count -= 1  # existing startup-mail probe, followed by the initial probe
        if restart:
            loop_count -= 1  # verification following the one simulated restart
        elapsed_loops = 0

        def process_list(_attributes):
            state = next(observations)
            probes.append((clock["now"], state))
            return [SimpleNamespace(info={"name": "S2.EXE"})] if state else []

        def info(message, *arguments):
            entries.append((clock["now"], message % arguments))

        def sleep(seconds):
            nonlocal elapsed_loops
            sleeps.append(seconds)
            clock["now"] += seconds
            if seconds == 30:
                delays.append(seconds)
                elapsed_loops += 1
                if elapsed_loops >= loop_count:
                    raise KeyboardInterrupt()

        with TemporaryDirectory() as directory:
            config["GENERAL"]["log_file"] = str(Path(directory) / "log.txt")
            with patch.object(app, "load_config", return_value=config), \
                 patch.object(app.psutil, "process_iter", side_effect=process_list), \
                 patch.object(app.time, "sleep", side_effect=sleep), \
                 patch.object(app.time, "monotonic", side_effect=lambda: clock["now"]), \
                 patch.object(app.logging, "basicConfig"), \
                 patch.object(app.logging, "info", side_effect=info), \
                 patch.object(app, "send_mail", side_effect=lambda s, r, subject, body: mails.append(subject)), \
                 patch.object(app.subprocess, "Popen") as popen:
                app.run()
        checks = [(tick, message) for tick, message in entries if message.startswith("Vérification ")]
        self.assertEqual(checks, [(tick, f"Vérification s2.exe : {'ACTIF' if state else 'INACTIF'}")
                                  for tick, state in probes])
        self.assertEqual(len(delays), loop_count)
        return checks, mails, popen.call_count, sleeps

    def test_active_control_logs_info_at_each_real_probe(self):
        checks, mails, _, _ = self.scenario([True, True, True, True])
        self.assertEqual([tick for tick, _ in checks], [100, 100, 130, 160])
        self.assertEqual(mails, [])

    def test_absent_controls_keep_warning_and_confirmation_separate(self):
        with patch.object(app.logging, "warning") as warning, patch.object(app.logging, "error") as error:
            checks, mails, _, _ = self.scenario([True, False, False])
        self.assertEqual(len(checks), 3)
        warning.assert_called_once()
        error.assert_called_once()
        self.assertEqual(len(mails), 1)
        self.assertIn("arrêté", mails[0])

    def test_transition_logs_both_states_and_keeps_recovery_notification(self):
        checks, mails, _, _ = self.scenario([True, False, False, True])
        self.assertTrue(checks[-1][1].endswith("ACTIF"))
        self.assertEqual(len(mails), 2)
        self.assertIn("rétabli", mails[-1])

    def test_threshold_one_cached_initial_absence_does_not_log_twice(self):
        checks, mails, _, _ = self.scenario([False], threshold=1)
        self.assertEqual(checks, [(100, "Vérification s2.exe : INACTIF")])
        self.assertEqual(len(mails), 1)

    def test_startup_mail_logs_only_the_two_existing_actual_probes(self):
        checks, mails, _, _ = self.scenario([True, True, True], startup_mail=True)
        self.assertEqual(len(checks), 3)  # mail test, initial state, first loop
        self.assertEqual(len(mails), 1)
        self.assertIn("Test verif963", mails[0])

    def test_restart_verification_is_logged_without_an_extra_probe(self):
        checks, mails, restart_count, sleeps = self.scenario([True, False, True], threshold=1, restart=True)
        self.assertEqual(len(checks), 3)
        self.assertEqual(restart_count, 1)
        self.assertEqual(sleeps, [10, 30])
        self.assertEqual(len(mails), 1)

    def test_real_utf8_log_appends_existing_file_across_runs(self):
        root = logging.getLogger()
        with TemporaryDirectory() as directory, patch.object(root, "handlers", []), \
             patch.object(root, "level", logging.WARNING):
            path = Path(directory) / "existing log.txt"
            path.write_text("Entrée existante : conservée\n", encoding="utf-8")
            initial_bytes = path.read_bytes()
            config = configparser.ConfigParser(interpolation=None)
            # Omit new/optional settings, like an existing INI installation.
            config["GENERAL"] = {"exe_path": "unused.exe", "log_file": str(path)}
            config["SMTP"] = {"mail_to": "dest@example.test"}
            try:
                for _ in range(2):
                    with patch.object(app, "load_config", return_value=config), \
                         patch.object(app.psutil, "process_iter", return_value=[SimpleNamespace(info={"name": "s2.exe"})]), \
                         patch.object(app.time, "sleep", side_effect=KeyboardInterrupt), \
                         patch.object(app, "send_mail") as mail:
                        app.run()
                    mail.assert_not_called()
                    for handler in root.handlers:
                        handler.flush()
                        handler.close()
                    # A restarted scheduled task starts without the old process's handlers.
                    root.handlers = []
                raw = path.read_bytes()
                text = raw.decode("utf-8")
                self.assertTrue(raw.startswith(initial_bytes))
                checks = [line for line in text.splitlines() if "Vérification s2.exe" in line]
                self.assertEqual(len(checks), 4)
                self.assertTrue(all(" - INFO - Vérification s2.exe : ACTIF" in line for line in checks))
                self.assertEqual(list(Path(directory).iterdir()), [path])
            finally:
                for handler in root.handlers:
                    handler.close()
