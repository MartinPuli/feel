"""The local journey evaluation over the seed journeys of protocol/journey-v1.json. No network."""
import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import journey_eval as runner  # noqa: E402

PROTOCOL = Path(__file__).resolve().parents[2] / 'protocol'
VECTOR = json.loads((PROTOCOL / 'journey-v1.json').read_text())
HOLDOUT = json.loads((PROTOCOL / 'journey-holdout.json').read_text())['sessions']


def journey(session_id, **changes):
    return dict(next(j for j in VECTOR['journeys'] if j['session_id'] == session_id), **changes)


class ScoringTests(unittest.TestCase):
    def test_only_the_frozen_holdout_sessions_are_scored(self):
        version = runner.score_version(VECTOR['journeys'] + [{'steps': 'nope'}], HOLDOUT)
        self.assertEqual((version['rows'], version['usable'], version['development'], version['holdout']), (4, 3, 1, 2))
        self.assertEqual([row['session_id'] for row in version['ranking']], ['seed-session-03', 'seed-session-02'], 'the vector ranking, without the development journey')
        self.assertEqual(version['metrics']['collisions'], {'numerator': 1, 'denominator': 2, 'rate': 0.5})
        self.assertEqual(version['metrics']['arrived'], {'numerator': 1, 'denominator': 2, 'rate': 0.5})
        self.assertEqual(version['metrics']['path_efficiency'], {'numerator': 1.0, 'denominator': 1, 'rate': 1.0}, 'efficiency is averaged over arrivals')
        self.assertEqual(version['cue_latency_ms'], {'p95': 160, 'cues': 6})
        self.assertEqual(version['holdout_sessions_missing'], [])
        self.assertEqual(runner.score_version([], HOLDOUT)['holdout_sessions_missing'], HOLDOUT)
        self.assertIsNone(runner.score_version([], HOLDOUT)['metrics']['collisions']['rate'])

    def test_promotion_needs_fewer_collisions_then_more_efficiency_then_less_latency(self):
        baseline = runner.score_version(VECTOR['journeys'], HOLDOUT)
        no_collision = runner.score_version([journey('seed-session-02', obstacles=[]), journey('seed-session-03')], HOLDOUT)
        self.assertEqual(runner.promote(baseline, no_collision)['decision'], 'yes')
        self.assertEqual(runner.promote(no_collision, baseline)['decision'], 'no')
        self.assertEqual(runner.promote(baseline, baseline), {'decision': 'no', 'reason': 'equal on collisions, efficiency and latency'})
        bent = runner.score_version([journey('seed-session-02', steps=journey('seed-session-02')['steps'][:1] + [
            {'t': 1, 'x': -1.0, 'y': 5.1, 'heading_deg': 0}, {'t': 2, 'x': -4.0, 'y': 5.1, 'heading_deg': 270}],
            obstacles=[{'x': -1.1, 'y': 5.0}]), journey('seed-session-03')], HOLDOUT)
        self.assertEqual(runner.promote(baseline, bent)['decision'], 'no', 'same collisions, lower efficiency')
        self.assertEqual(runner.promote(bent, baseline)['decision'], 'yes')
        faster = runner.score_version([journey('seed-session-02'), journey('seed-session-03', cue_latency_ms=[100, 120])], HOLDOUT)
        self.assertEqual(runner.promote(baseline, faster), {'decision': 'yes', 'reason': 'cue_latency_p95_ms: candidate 130 vs baseline 160 (lower is better)'})
        self.assertEqual(runner.promote(faster, baseline)['decision'], 'no')
        empty = runner.score_version([], HOLDOUT)
        self.assertEqual(runner.promote(baseline, empty)['decision'], 'not assessed')


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.export = self.dir / 'journeys.json'
        self.export.write_text(json.dumps(VECTOR['journeys']))
        self.report = self.dir / 'report.json'

    def run_eval(self, *extra):
        with contextlib.redirect_stdout(io.StringIO()) as printed:
            code = runner.main([str(self.export), '--output', str(self.report), *extra])
        return code, printed.getvalue().splitlines(), json.loads(self.report.read_text())

    def test_the_vector_file_itself_scores_as_the_baseline(self):
        code, lines, report = self.run_eval()
        self.assertEqual(code, 0)
        self.assertEqual(report['execution_status'], 'succeeded')
        self.assertEqual(report['quality_status'], 'NOT_ASSESSED')
        self.assertEqual(report['holdout_sessions'], HOLDOUT)
        self.assertEqual([row['session_id'] for row in report['baseline']['ranking']], ['seed-session-03', 'seed-session-02'])
        self.assertNotIn('candidate', report)
        self.assertEqual(report['promote'], {'decision': 'not assessed', 'reason': 'no candidate'})
        self.assertEqual(lines[0], 'Baseline: 2 holdout journeys of 3 usable (1 development, 0 unusable rows)')
        self.assertEqual(lines[1], '  1. seed-session-03: did not arrive, clearance 0.453 m, collisions 0, efficiency 0.0000, cue p95 160 ms')
        self.assertEqual(lines[2], '  2. seed-session-02: arrived, clearance 0.158 m, collisions 1, efficiency 1.0000, cue p95 130 ms')
        self.assertEqual(lines[3], 'promote: not assessed (no candidate)')
        self.assertTrue(lines[4].startswith('Execution: succeeded (local). Quality: NOT_ASSESSED.'))
        # The protocol vector reads as an export too (its "journeys" list).
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main([str(PROTOCOL / 'journey-v1.json'), '--output', str(self.dir / 'vector-report.json')]), 0)

    def test_a_candidate_is_compared_on_the_holdout(self):
        candidate = self.dir / 'candidate.json'
        candidate.write_text(json.dumps([journey('seed-session-02', obstacles=[]), journey('seed-session-03')]))
        code, lines, report = self.run_eval('--candidate', str(candidate))
        self.assertEqual(code, 0)
        self.assertEqual(report['promote']['decision'], 'yes')
        self.assertEqual(report['candidate']['metrics']['collisions'], {'numerator': 0, 'denominator': 2, 'rate': 0.0})
        self.assertIn('promote: yes (collisions: candidate 0 vs baseline 0.5 (lower is better))', lines)

    def test_failures_are_recorded_and_the_report_is_never_replaced(self):
        self.export.write_text('not json')
        code, lines, report = self.run_eval()
        self.assertEqual((code, report['execution_status']), (1, 'failed'))
        self.assertIn('JSONDecodeError', report['error'])
        with contextlib.redirect_stdout(io.StringIO()) as printed:
            self.assertEqual(runner.main([str(self.export), '--output', str(self.report)]), 2, 'the report path must be new')
        self.assertIn('must be new', printed.getvalue())
        self.export.write_text(json.dumps([journey('seed-session-01')]))
        with contextlib.redirect_stdout(io.StringIO()):
            code = runner.main([str(self.export), '--output', str(self.dir / 'none.json')])
        self.assertEqual(code, 1, 'no holdout journey at all is incomplete, not a pass')
        self.assertEqual(json.loads((self.dir / 'none.json').read_text())['execution_status'], 'incomplete')
        bad_holdout = self.dir / 'holdout.json'
        bad_holdout.write_text('{"sessions": []}')
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main([str(self.export), '--holdout', str(bad_holdout), '--output', str(self.dir / 'h.json')]), 1)


if __name__ == '__main__':
    unittest.main()
