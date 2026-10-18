"""Configuration safety regressions; all inputs are synthetic and isolated."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('supabase_config.sh')

class BuildConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        (self.root / 'Config').mkdir()
        self.script = self.root / 'scripts' / SCRIPT.name
        shutil.copyfile(SCRIPT, self.script)
        self.output = self.root / 'Config' / 'Supabase.local.xcconfig'
        self.output.write_text('existing configuration\n')

    def configure(self, extra):
        source = self.root / 'fixture.env'
        source.write_text('SUPABASE_URL=https://example.supabase.co\nSUPABASE_PUBLISHABLE_KEY=sb_publishable_test_fixture\n' + extra)
        return subprocess.run(['sh', str(self.script), str(source)], capture_output=True, text=True)

    def test_signed_in_mode_excludes_demo_credential(self):
        result = self.configure('FEEL_VOICE_AUTH_MODE=supabase\nFEEL_VOICE_ENDPOINT=https://voice.example/session\nFEEL_VOICE_ACCESS_TOKEN=demo-only-secret\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        config = self.output.read_text()
        self.assertIn('FEEL_VOICE_AUTH_MODE = supabase', config)
        self.assertNotIn('FEEL_VOICE_ACCESS_TOKEN', config)
        self.assertNotIn('demo-only-secret', config)

    def test_demo_remains_default(self):
        result = self.configure('FEEL_VOICE_ENDPOINT=https://voice.example/session\nFEEL_VOICE_ACCESS_TOKEN=demo-access-code-fixture\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('FEEL_VOICE_AUTH_MODE = demo', self.output.read_text())

    def test_invalid_mode_preserves_existing_config(self):
        result = self.configure('FEEL_VOICE_AUTH_MODE=invalid\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), 'existing configuration\n')
        self.assertEqual(list((self.root / 'Config').glob('*.??????')), [])

    def test_provider_key_refused_without_partial_write(self):
        result = self.configure('FEEL_VOICE_ENDPOINT=https://voice.example/session\nFEEL_VOICE_ACCESS_TOKEN=sk-test-provider-fixture\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), 'existing configuration\n')

if __name__ == '__main__':
    unittest.main()
