"""Six physical columns and the independently enforced reserved-wire boundary."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('feel_replay_harness', Path(__file__).parents[1] / 'run.py')
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


def tick(bands, t=1):
    return {'t': t, 'dropped': False,
            'phone': {'bands': list(bands), 'highlight': 255, 'state': 'live', 'frame': t},
            'firmware': {'bands': list(bands), 'highlight': 255}}


class ScoringTests(unittest.TestCase):
    def test_all_means_six_physical_columns_not_reserved_wire_slot(self):
        scenario = {'expect': [{'from': 0, 'to': 2, 'columns': 'all', 'band': 2}]}
        result = harness.score(scenario, [tick([0, 2, 2, 2, 2, 2, 2])])
        self.assertEqual(result['checks'], 6)
        self.assertEqual(result['accuracy'], 1)
        self.assertEqual(result['reservedSlotViolations'], 0)
        self.assertTrue(result['passed'])
        for invalid in ([0], [1, 1], [7], [True], []):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                harness.columns_of(invalid)

    def test_actual_physical_miss_still_fails_unmodified_accuracy_gate(self):
        scenario = {'expect': [{'from': 0, 'to': 2, 'band': 2}], 'pass': {'minAccuracy': .95}}
        result = harness.score(scenario, [tick([0, 2, 2, 0, 2, 2, 2])])
        self.assertEqual(result['missedChecks'], 1)
        self.assertFalse(result['passed'])
        self.assertIn('0.833 < 0.95', result['reasons'][0])

    def test_reserved_slot_is_enforced_on_both_sides_even_for_known_or_unlabelled_cases(self):
        for source in ('phone', 'firmware'):
            for violation in ('band', 'highlight'):
                state = tick([0, 2, 2, 2, 2, 2, 2])
                if violation == 'band': state[source]['bands'][0] = 2
                else: state[source]['highlight'] = 0
                scenario = {'expect': [{'from': 0, 'to': 2, 'band': 2}]}
                result = harness.score(scenario, [state])
                with self.subTest(source=source, violation=violation):
                    # The six valid pins agree; the independent ABI invariant fails.
                    self.assertEqual(result['accuracy'], 1)
                    self.assertEqual(result['reservedSlotViolations'], 1)
                    self.assertFalse(result['passed'])
                    self.assertEqual(harness.status(dict(scenario, result=result, knownIssue='perception limitation')), 'FAIL')
                    self.assertEqual(harness.status({'result': result}), 'FAIL')

    def test_tap_only_satisfies_its_actual_band_and_never_tracking_loss(self):
        states = [tick([0, 2, 0, 0, 0, 0, 0], 0),
                  tick([0, 0, 0, 0, 0, 0, 0], 1),
                  tick([0, 2, 0, 0, 0, 0, 0], 2)]
        for source in ('phone', 'firmware'):
            def scenario(band):
                return {'expect':[{'from':1,'to':1,'columns':[1],'band':band,'source':source}]}
            self.assertTrue(harness.score(scenario(2), states)['passed'])
            self.assertFalse(harness.score(scenario(3), states)['passed'])
            states[1]['phone']['state'] = 'trackingLost'
            self.assertFalse(harness.score(scenario(2), states)['passed'])
            states[1]['phone']['state'] = 'live'

    def test_flicker_denominator_is_six_and_fault_neutralization_is_excluded(self):
        before = tick([0, 0, 0, 0, 0, 0, 0], 0)
        after = tick([0, 2, 0, 0, 0, 0, 0], 1)
        result = harness.score({}, [before, after])
        self.assertEqual(result['bandChangesPerColumnSecond'], round(1/6, 3))
        after['phone']['state'] = 'trackingLost'
        result = harness.score({}, [before, after])
        self.assertEqual(result['bandChangesPerColumnSecond'], 0)

if __name__ == '__main__': unittest.main()
