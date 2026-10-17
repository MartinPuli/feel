"""Gateway client behavior without a network."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import gateway  # noqa: E402
from feel_chalk.config import Settings  # noqa: E402

CONFIG = Settings('https://gateway.example.test', 'key', 'env', 'openai/requested')


class GatewayTests(unittest.TestCase):
    def test_completion_returns_content_resolved_model_and_usage(self):
        reply = {'model': 'openai/resolved', 'usage': {'prompt_tokens': 5, 'completion_tokens': 1, 'total_tokens': 6},
                 'choices': [{'message': {'content': 'OK'}}]}
        with patch.object(gateway, '_request', return_value=reply):
            result = gateway.completion(CONFIG, {'model': 'openai/requested'}, timeout=3)
        self.assertEqual(result, gateway.Completion('OK', 'openai/resolved', reply['usage']))

    def test_chat_returns_only_the_reply_text(self):
        with patch.object(gateway, '_request', return_value={'choices': [{'message': {'content': 'OK'}}]}):
            self.assertEqual(gateway.chat(CONFIG, {}), 'OK')

    def test_read_timeout_becomes_gateway_error(self):
        with patch('urllib.request.urlopen', side_effect=TimeoutError('timed out')):
            with self.assertRaises(gateway.GatewayError):
                gateway.chat(CONFIG, {}, timeout=1)


if __name__ == '__main__':
    unittest.main()
