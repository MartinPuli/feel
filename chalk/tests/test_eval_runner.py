"""Offline evaluation-runner contract tests. No SDK client or cloud connection."""
import contextlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import sys
import unittest
from unittest.mock import Mock, patch

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from feel_chalk import where_is_eval as runner
from feel_chalk.config import Settings
from feel_chalk.eval_data import prepare


class FakeSDK:
    def __init__(self, records=None, status='succeeded', result=True, wait_error=None):
        self.records = records if records is not None else [good_result()]
        self.functions = []
        self.secrets = []
        self.wait_arguments = None
        self.Secret = SimpleNamespace(from_local_env=self.secret)
        self.Evaluation = SimpleNamespace(create=self.create)
        self.status = status
        self.result = result
        self.wait_error = wait_error

    def secret(self, name):
        self.secrets.append(name)
        return name

    def function(self, function, **kwargs):
        self.functions.append((function.__name__, kwargs))
        return function

    def DatasetClient(self):
        return SimpleNamespace(upload=self.upload, read=lambda ref: SimpleNamespace(to_pylist=lambda: self.records))

    def upload(self, name, rows):
        self.uploaded = rows
        return SimpleNamespace(dataset_id='dataset-1', revision_id='revision-1')

    def create(self, name, **kwargs):
        self.created = kwargs
        return SimpleNamespace(id='eval-1', suite_id='suite-1', run=self.run)

    def run(self, **kwargs):
        self.metadata = kwargs['metadata']
        return SimpleNamespace(id='run-1', status=SimpleNamespace(value='running'), wait=self.wait)

    def wait(self, **kwargs):
        self.wait_arguments = kwargs
        if self.wait_error:
            raise self.wait_error
        return SimpleNamespace(id='run-1', status=SimpleNamespace(value=self.status),
                               result_dataset_id='results-1' if self.result else None,
                               result_dataset_revision_id='result-revision-1' if self.result else None,
                               result_dataset='ref' if self.result else None)


def good_result():
    return {'output': json.dumps({'status': 'ok', 'reply': '{"found":false,"label":"","box":null,"confidence":0}',
                                  'elapsed_ms': 800.0, 'model': 'test/model', 'usage': None}),
            'expected_box': 'null', 'output_error': None,
            'points_correctly_value': 1.0, 'reply_is_well_formed_value': 1.0,
            'false_found_value': 0.0}


class EvaluationRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.labels = self.root / 'labels.jsonl'
        self.photo = self.root / 'photo.png'
        Image.new('RGB', (4, 6), 'white').save(self.photo)
        self.write_labels([{'image': 'photo.png', 'question': 'Where is the chair?', 'box': None}])
        self.report = self.root / 'report.json'

    def write_labels(self, rows):
        self.labels.write_text('\n'.join(json.dumps(row) for row in rows), encoding='utf-8')

    def invoke(self, sdk=None, extra=()):
        loader = Mock(return_value=sdk or FakeSDK())
        config = Settings('https://gateway.example.test', 'TEST-SECRET-NEVER-PERSIST', 'env-1', 'test/model')
        with patch.object(runner, 'settings', return_value=config) as settings, contextlib.redirect_stdout(io.StringIO()):
            code = runner.main([str(self.labels), '--output', str(self.report), *extra], sdk_loader=loader)
        return code, json.loads(self.report.read_text()) if self.report.exists() else None, loader, settings

    def test_offline_preflight_never_reads_settings_or_sdk(self):
        code, report, loader, settings = self.invoke(extra=['--preflight'])
        self.assertEqual(code, 0)
        loader.assert_not_called()
        settings.assert_not_called()
        self.assertEqual(report['execution_status'], 'NOT_RUN')
        self.assertEqual(report['quality_status'], 'NOT_ASSESSED')
        self.assertEqual(len(report['dataset_sha256']), 64)
        self.assertEqual(len(report['prompt_sha256']), 64)
        self.assertNotIn('Where is', self.report.read_text())
        self.assertNotIn('image_b64', self.report.read_text())

    def test_dataset_hash_is_stable_and_tracks_inputs(self):
        first = prepare(self.labels)[1]['dataset_sha256']
        self.assertEqual(first, prepare(self.labels)[1]['dataset_sha256'])
        self.write_labels([{'image': 'photo.png', 'question': 'Where is the door?', 'box': None}])
        second = prepare(self.labels)[1]['dataset_sha256']
        self.assertNotEqual(first, second)
        Image.new('RGB', (4, 6), 'black').save(self.photo)
        self.assertNotEqual(second, prepare(self.labels)[1]['dataset_sha256'])

    def test_invalid_labels_fail_before_settings_and_sdk(self):
        cases = [[], [{'image': 'missing.png', 'question': 'Where?', 'box': None}],
                 [{'image': 'photo.png', 'question': '', 'box': None}],
                 [{'image': '../outside.png', 'question': 'Where?', 'box': None}],
                 [{'image': 'photo.png', 'question': 'Where?', 'box': [False, 0, 1, 1]}],
                 [{'image': 'photo.png', 'question': 'Where?', 'box': [0, 0, 1, 10**400]}],
                 [{'image': 'photo.png', 'question': 'Where?', 'box': [0, 0, 1, 1]}]]
        for rows in cases:
            with self.subTest(rows=rows):
                self.report.unlink(missing_ok=True)
                self.write_labels(rows)
                code, report, loader, settings = self.invoke()
                self.assertEqual(code, 2)
                self.assertEqual(report['preflight_status'], 'FAIL')
                self.assertIn('validation_error', report)
                loader.assert_not_called()
                settings.assert_not_called()

    def test_bad_image_fails_without_sdk(self):
        self.photo.write_bytes(b'not an image')
        code, report, loader, settings = self.invoke()
        self.assertEqual(code, 2)
        self.assertIn('Row 1', report['validation_error'])
        loader.assert_not_called()
        settings.assert_not_called()

    def test_report_never_overwrites_any_existing_file_or_symlink(self):
        self.labels.write_text('invalid json')
        for target in (self.labels, self.photo):
            before = target.read_bytes()
            with contextlib.redirect_stdout(io.StringIO()), patch.object(runner, 'settings') as settings:
                self.assertEqual(runner.main([str(self.labels), '--output', str(target)]), 2)
                settings.assert_not_called()
            self.assertEqual(target.read_bytes(), before)
        self.report.symlink_to(self.photo)
        before = self.photo.read_bytes()
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main([str(self.labels), '--output', str(self.report)]), 2)
        self.assertEqual(self.photo.read_bytes(), before)

    def test_success_propagates_host_and_persists_scores_without_quality_pass(self):
        sdk = FakeSDK()
        code, report, _, _ = self.invoke(sdk, ['--model', 'override', '--timeout', '25'])
        self.assertEqual(code, 0)
        self.assertEqual(report['execution_status'], 'succeeded')
        self.assertEqual(report['quality_status'], 'NOT_ASSESSED')
        self.assertEqual(report['metrics']['absent_accuracy']['rate'], 1.0)
        self.assertEqual(sdk.functions[0][1]['env'], {'CHALK_API_HOST': 'https://gateway.example.test', 'FEEL_CHALK_MODEL': 'override'})
        self.assertEqual(sdk.secrets, ['CHALK_ROUTER_API_KEY', 'CHALK_ENV_ID'])
        self.assertEqual(sdk.wait_arguments, {'timeout': 25, 'raise_on_failure': False})
        self.assertEqual(sdk.metadata['prompt_sha256'], report['prompt_sha256'])
        self.assertNotIn('TEST-SECRET', self.report.read_text())

    def test_failed_canceled_or_unfinished_runs_exit_nonzero_with_ids(self):
        for status in ('failed', 'canceled', 'running'):
            with self.subTest(status=status):
                self.report.unlink(missing_ok=True)
                code, report, _, _ = self.invoke(FakeSDK(status=status))
                self.assertEqual(code, 1)
                self.assertEqual(report['run_id'], 'run-1')
                self.assertEqual(report['execution_status'], status)

    def test_timeout_persists_run_identity_without_sensitive_exception(self):
        code, report, _, _ = self.invoke(FakeSDK(wait_error=TimeoutError('sensitive detail')))
        self.assertEqual(code, 1)
        self.assertEqual(report['execution_status'], 'timed_out')
        self.assertEqual(report['run_id'], 'run-1')
        self.assertNotIn('sensitive detail', self.report.read_text())

    def test_missing_result_dataset_is_incomplete(self):
        code, report, _, _ = self.invoke(FakeSDK(result=False))
        self.assertEqual(code, 1)
        self.assertEqual(report['execution_status'], 'incomplete')

    def test_failed_or_missing_rows_and_error_columns_are_incomplete(self):
        cases = [[], [dict(good_result(), output=json.dumps({'status': 'error', 'reply': None, 'error': 'private detail'}))],
                 [dict(good_result(), output='private detail')],
                 [dict(good_result(), output_error='private detail')],
                 [dict(good_result(), points_correctly_error='private detail')],
                 [dict(good_result(), points_correctly_value_error='private detail')],
                 [dict(good_result(), points_correctly_value=None)]]
        for rows in cases:
            with self.subTest(rows=rows):
                self.report.unlink(missing_ok=True)
                code, report, _, _ = self.invoke(FakeSDK(records=rows))
                self.assertEqual(code, 1)
                self.assertEqual(report['execution_status'], 'incomplete')
                self.assertNotIn('private detail', self.report.read_text())

    def test_zero_accuracy_is_completed_execution_not_quality_pass(self):
        code, report, _, _ = self.invoke(FakeSDK(records=[dict(good_result(), points_correctly_value=0.0)]))
        self.assertEqual(code, 0)
        self.assertEqual(report['metrics']['absent_accuracy']['rate'], 0)
        self.assertEqual(report['quality_status'], 'NOT_ASSESSED')


if __name__ == '__main__':
    unittest.main()
