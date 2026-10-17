"""Connection diagnostics must not silently invoke paid inference."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_connection
from feel_chalk.config import Settings


class ConnectionTests(unittest.TestCase):
    def setUp(self):
        check_connection.results.clear()
        self.config = Settings('https://example.invalid', 'test-key', 'test-env', 'test-model')

    def check(self, chat, models):
        with patch.object(check_connection, 'settings', return_value=self.config), \
                patch.object(check_connection.gateway, 'list_models', return_value=models), \
                patch.object(check_connection.gateway, 'chat', return_value='OK') as request, \
                patch('builtins.print'):
            check_connection.check_gateway(chat)
            return request.call_count

    def test_missing_model_never_infers_without_explicit_flag(self):
        self.assertEqual(self.check(False, []), 0)
        self.assertIn(('BLOCKED', 'model'), [(s, n) for s, n, _ in check_connection.results])

    def test_listed_model_never_infers_without_explicit_flag(self):
        self.assertEqual(self.check(False, ['test-model']), 0)

    def test_explicit_flag_sends_one_call_with_or_without_listing(self):
        for models in ([], ['test-model']):
            with self.subTest(models=models):
                self.assertEqual(self.check(True, models), 1)

    def test_missing_credentials_never_infers_even_with_flag(self):
        self.config = Settings('https://example.invalid', None, None, 'test-model')
        self.assertEqual(self.check(True, []), 0)
