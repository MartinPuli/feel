"""Regression checks against a false-green source gate, using temporary repositories."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("check_sources", Path(__file__).parents[1] / "check_sources.py")
preflight = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preflight)


class SourcePresenceTests(unittest.TestCase):
    def test_empty_repository_is_blocked(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = preflight.inspect(Path(tmp))
            self.assertEqual(result["status"], "BLOCKED")
            self.assertIn("docs/PROTOCOL.md", result["missing"])

    def test_documentation_and_empty_files_do_not_count_as_implementation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for path in preflight.REQUIRED_FILES:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("")
            (root / "HANDOFF-v7.md").write_text("Historical claim: tests pass")
            result = preflight.inspect(root)
            self.assertEqual(result["status"], "BLOCKED")
            self.assertEqual(result["source_groups"]["Lantern app"], [])

    def test_presence_never_claims_release_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for path in preflight.REQUIRED_FILES:
                target = root / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("fixture only")
            for _, (directory, patterns) in preflight.SOURCE_GROUPS.items():
                target = root / directory / patterns[0].replace("*", "Example")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("fixture only")
            result = preflight.inspect(root)
            self.assertEqual(result["missing"], [])
            self.assertEqual(result["status"], "PRESENT_REVIEW_REQUIRED")


if __name__ == "__main__":
    unittest.main()
