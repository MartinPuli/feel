"""Per-row timing, usage and metric denominators for the Where-is evaluation. No network."""
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import gateway, where_is, where_is_eval as runner  # noqa: E402
from feel_chalk.config import Settings  # noqa: E402
from feel_chalk.eval_report import summarize_results  # noqa: E402

FOUND = '{"found":true,"label":"door","box":[0.4,0.4,0.6,0.6],"confidence":0.9}'
NOT_FOUND = '{"found":false,"label":"","box":null,"confidence":0}'
USAGE = {'prompt_tokens': 100, 'completion_tokens': 10, 'total_tokens': 110}
DOOR = [0.3, 0.3, 0.7, 0.7]


def result_row(reply, box, status='ok', elapsed_ms=900.0, model='openai/a', usage=USAGE):
    output = json.dumps({'status': status, 'reply': reply, 'elapsed_ms': elapsed_ms, 'model': model, 'usage': usage})
    expected = json.dumps(box)
    return {'output': output, 'expected_box': expected, 'output_error': None,
            'points_correctly_value': runner.points_correctly(output, expected),
            'reply_is_well_formed_value': runner.reply_is_well_formed(output),
            'false_found_value': runner.false_found(output, expected)}


def ratio(numerator, denominator):
    return {'numerator': numerator, 'denominator': denominator, 'rate': numerator / denominator}


class MetricTests(unittest.TestCase):
    def test_false_found_rate_counts_only_absent_rows(self):
        rows = [result_row(FOUND, None), result_row(NOT_FOUND, None), result_row(FOUND, DOOR), result_row(NOT_FOUND, DOOR)]
        metrics = summarize_results(rows, 4)['metrics']
        self.assertEqual(metrics['false_found'], ratio(1, 2))
        self.assertEqual(metrics['absent_accuracy'], ratio(1, 2))
        self.assertEqual(metrics['present_localization'], ratio(1, 2))
        self.assertEqual(metrics['well_formed'], ratio(4, 4))
        self.assertEqual(metrics['missing_response'], ratio(0, 4))

    def test_late_reply_is_a_scored_missing_response(self):
        summary = summarize_results([result_row(None, DOOR, status='late', elapsed_ms=12500.0, model=None, usage=None),
                                     result_row(FOUND, DOOR)], 2)
        self.assertTrue(summary['rows_complete'])
        self.assertEqual(summary['metrics']['missing_response'], ratio(1, 2))
        self.assertEqual(summary['metrics']['present_localization'], ratio(1, 2))
        self.assertEqual(summary['metrics']['well_formed'], ratio(1, 2))

    def test_latency_usage_and_resolved_models(self):
        rows = [result_row(NOT_FOUND, None, elapsed_ms=500.0), result_row(NOT_FOUND, None, elapsed_ms=900.0),
                result_row(FOUND, DOOR, elapsed_ms=1300.0, model='openai/b'),
                result_row(None, DOOR, status='late', elapsed_ms=12500.0, model=None, usage=None)]
        summary = summarize_results(rows, 4)
        self.assertEqual(summary['latency_ms'], {'p50': 900.0, 'p95': 12500.0, 'max': 12500.0, 'rows': 4})
        self.assertEqual(summary['usage'], {'prompt_tokens': 300, 'completion_tokens': 30, 'total_tokens': 330, 'rows': 3})
        self.assertEqual(summary['resolved_models'], ['openai/a', 'openai/b'])
        self.assertEqual(summary['rows'][3]['status'], 'late')
        self.assertTrue(summary['rows'][0]['absent'])

    def test_rows_without_expected_box_are_incomplete(self):
        row = result_row(NOT_FOUND, None)
        del row['expected_box']
        summary = summarize_results([row], 1)
        self.assertFalse(summary['rows_complete'])
        self.assertIsNone(summary['metrics'])


class TaskTests(unittest.TestCase):
    config = Settings('https://gateway.example.test', 'key', 'env', 'openai/requested')

    def run_task(self, clock, reply=None, error=None):
        completion = gateway.Completion(FOUND, 'openai/resolved', USAGE) if reply is None else reply
        with patch.object(runner, 'settings', return_value=self.config), \
                patch.object(runner.time, 'monotonic', side_effect=clock), \
                patch.object(runner.gateway, 'completion', return_value=completion, side_effect=error) as call:
            output = runner.where_is_task('Where is the door?', 'QUJD')
        return output, json.loads(output), call

    def test_task_records_reply_timing_usage_and_resolved_model(self):
        output, record, call = self.run_task([10.0, 11.25])
        self.assertEqual(record, {'status': 'ok', 'reply': FOUND, 'elapsed_ms': 1250.0,
                                  'model': 'openai/resolved', 'usage': USAGE})
        self.assertEqual(call.call_args.kwargs['timeout'], where_is.DEADLINE_SECONDS)
        self.assertEqual(runner.points_correctly(output, json.dumps(DOOR)), 1.0)

    def test_reply_after_the_deadline_is_late_and_scores_zero(self):
        output, record, _ = self.run_task([0.0, where_is.DEADLINE_SECONDS + 0.5])
        self.assertEqual(record['status'], 'late')
        self.assertIsNone(record['reply'])
        self.assertEqual(runner.points_correctly(output, json.dumps(DOOR)), 0.0)
        self.assertEqual(runner.reply_is_well_formed(output), 0.0)

    def test_gateway_error_is_recorded_as_error(self):
        _, record, _ = self.run_task([0.0, 1.0], error=gateway.GatewayError('HTTP 500 from /chat/completions'))
        self.assertEqual(record['status'], 'error')
        self.assertIsNone(record['reply'])


if __name__ == '__main__':
    unittest.main()
