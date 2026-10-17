"""Operational regressions: fail closed on missing input and clean up timed-out jobs."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location("run_v2_checks", Path(__file__).parents[1] / "run_v2_checks.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerTests(unittest.TestCase):
    def test_missing_production_source_does_not_execute_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            marker = directory / "should-not-exist"
            command = [sys.executable, "-c", f"open({str(marker)!r}, 'w').write('ran')"]
            result = runner.run_check("blocked", command, directory,
                                      files=(str(directory / "missing-source.cpp"),))
            self.assertEqual(result["status"], "BLOCKED")
            self.assertFalse(marker.exists())

    def test_failed_command_retains_output_and_exit(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = runner.run_check("failed", [sys.executable, "-c", "print('compiler error'); raise SystemExit(7)"], Path(tmp))
            self.assertEqual(result["status"], "FAIL")
            self.assertEqual(result["exit_code"], 7)
            self.assertIn("compiler error", Path(result["log"]).read_text())

    @unittest.skipUnless(os.name == "posix", "Linux/macOS process-group cleanup")
    def test_timeout_also_stops_build_descendants(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            marker = directory / "orphan-wrote-after-timeout"
            child = f"import time; time.sleep(0.8); open({str(marker)!r}, 'w').write('orphan')"
            parent = f"import subprocess,sys,time; subprocess.Popen([sys.executable,'-c',{child!r}]); print('child started',flush=True); time.sleep(5)"
            result = runner.run_check("timeout", [sys.executable, "-c", parent], directory, timeout=0.25)
            self.assertEqual(result["status"], "FAIL")
            self.assertIn("Exceeded", result["error"])
            self.assertIn("child started", Path(result["log"]).read_text())
            time.sleep(0.9)
            self.assertFalse(marker.exists(), "timed-out child kept running")


if __name__ == "__main__":
    unittest.main()
