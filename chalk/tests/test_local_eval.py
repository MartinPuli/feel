import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import where_is_eval as runner  # noqa: E402
from feel_chalk.config import Settings  # noqa: E402
from feel_chalk.gateway import Completion, GatewayError  # noqa: E402

FOUND = '{"found": true, "label": "exit sign", "box": [0.55, 0.40, 0.95, 0.80], "confidence": 0.9}'
NOT_FOUND = '{"found": false, "label": "", "box": null, "confidence": 0}'
SETTINGS = Settings(api_host='https://api.example.test', router_api_key='k', environment_id='env', model='openai/configured')


def jpeg() -> bytes:
    from PIL import Image
    out = io.BytesIO()
    Image.new('RGB', (32, 24), (120, 120, 120)).save(out, format='JPEG')
    return out.getvalue()


class LocalEvaluationTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        for name in ('a.jpg', 'b.jpg', 'c.jpg'):
            (self.dir / name).write_bytes(jpeg())
        self.labels = self.dir / 'labels.jsonl'
        self.labels.write_text('\n'.join(json.dumps(row) for row in [
            {'image': 'a.jpg', 'question': 'Where is the exit sign?', 'box': [0.5, 0.4, 0.9, 0.8]},
            {'image': 'b.jpg', 'question': 'Where is the exit sign?', 'box': [0.0, 0.0, 0.2, 0.2]},
            {'image': 'c.jpg', 'question': 'Where is the exit sign?', 'box': None}]) + '\n')
        self.report = self.dir / 'report.json'

    def run_local(self, completion, *extra):
        with mock.patch.object(runner, 'COMPLETION', completion), mock.patch.object(runner, 'settings', lambda: SETTINGS):
            code = runner.main([str(self.labels), '--local', '--output', str(self.report), *extra])
        return code, json.loads(self.report.read_text())

    def test_local_run_scores_rows_with_the_hosted_scorers_and_shape(self):
        bodies = []

        def completion(config, body, timeout):
            bodies.append(body)
            self.assertEqual(timeout, 12)
            reply = FOUND if len(bodies) < 3 else NOT_FOUND
            return Completion(reply, 'openai/resolved', {'prompt_tokens': 100, 'completion_tokens': 20, 'total_tokens': 120})
        code, report = self.run_local(completion, '--model', 'openai/override')
        self.assertEqual(code, 0)
        self.assertEqual(report['execution_mode'], 'local')
        self.assertEqual(report['execution_status'], 'succeeded')
        self.assertEqual(report['quality_status'], 'NOT_ASSESSED')
        self.assertEqual(report['model'], 'openai/override')
        self.assertEqual(bodies[0]['model'], 'openai/override')
        metrics = report['metrics']
        self.assertEqual(metrics['present_localization'], {'numerator': 1.0, 'denominator': 2, 'rate': 0.5})
        self.assertEqual(metrics['false_found'], {'numerator': 0.0, 'denominator': 1, 'rate': 0.0})
        self.assertEqual(metrics['well_formed']['rate'], 1.0)
        self.assertEqual(report['usage']['total_tokens'], 360)
        self.assertEqual(report['resolved_models'], ['openai/resolved'])
        self.assertEqual([row['status'] for row in report['rows']], ['ok', 'ok', 'ok'])
        self.assertNotIn('dataset_id', report, 'nothing is uploaded in local mode')

    def test_gateway_error_leaves_the_run_incomplete_without_provider_text(self):
        def completion(config, body, timeout):
            if 'exit' in body['messages'][-1]['content'][0]['text'] and not completion.failed:
                completion.failed = True
                raise GatewayError('HTTP 500 from /chat/completions: secret provider detail', 500)
            return Completion(NOT_FOUND, 'openai/resolved', None)
        completion.failed = False
        code, report = self.run_local(completion)
        self.assertEqual(code, 1)
        self.assertEqual(report['execution_status'], 'incomplete')
        self.assertIn('error', [row['status'] for row in report['rows']])
        self.assertNotIn('secret provider detail', self.report.read_text())

    def test_missing_settings_fail_before_any_gateway_call(self):
        calls = []
        with mock.patch.object(runner, 'COMPLETION', lambda *a, **k: calls.append(1)), \
             mock.patch.object(runner, 'settings', lambda: Settings('https://api.example.test', None, None, None)):
            code = runner.main([str(self.labels), '--local', '--output', str(self.report)])
        self.assertEqual(code, 1)
        self.assertEqual(calls, [])
        self.assertEqual(json.loads(self.report.read_text())['execution_status'], 'failed')


if __name__ == '__main__':
    unittest.main()
