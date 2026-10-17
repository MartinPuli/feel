import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import history  # noqa: E402

NOW = datetime(2026, 10, 17, 21, 0, tzinfo=timezone.utc)


def row(place, ago, confidence=0.9):
    return {'place': place, 'found_at': NOW - ago, 'confidence': confidence}


class HistoryTests(unittest.TestCase):
    def test_latest_confirmed_find_wins_regardless_of_row_order(self):
        summary = history.summarize([row('front door hook', timedelta(days=2)), row('kitchen table', timedelta(hours=2)),
                                     row('lab bench', timedelta(days=9))])
        self.assertEqual(summary.last_place, 'kitchen table')
        self.assertEqual(summary.last_seen_at, NOW - timedelta(hours=2))
        self.assertEqual(summary.count, 3)

    def test_rows_without_place_or_aware_time_are_ignored(self):
        naive = {'place': 'desk', 'found_at': datetime(2026, 10, 17, 20, 59), 'confidence': 1}
        summary = history.summarize([{'place': '  ', 'found_at': NOW}, {'place': 'desk', 'found_at': None}, naive])
        self.assertEqual(summary, history.Summary(None, None, 0))

    def test_spoken_sentence_is_relative_time_and_never_a_present_claim(self):
        summary = history.summarize([row('kitchen table', timedelta(hours=2)), row('front door hook', timedelta(days=2))])
        self.assertEqual(history.spoken('Keys', summary, NOW),
                         'Keys: last confirmed at the kitchen table, 2 hours ago (2 finds on record).')
        self.assertEqual(history.spoken('water bottle', history.summarize([row('lab bench by the window', timedelta(minutes=30))]), NOW),
                         'Water bottle: last confirmed at the lab bench by the window, 30 minutes ago.')
        self.assertEqual(history.spoken('keys', history.Summary(None, None, 0), NOW), 'No confirmed find of keys is on record.')

    def test_relative_times(self):
        cases = [(timedelta(seconds=40), 'just now'), (timedelta(minutes=5), '5 minutes ago'), (timedelta(hours=1), '1 hour ago'),
                 (timedelta(hours=23), '23 hours ago'), (timedelta(days=1), 'yesterday'), (timedelta(days=3), '3 days ago'),
                 (timedelta(seconds=-30), 'just now')]
        for delta, expected in cases:
            with self.subTest(delta=delta):
                self.assertEqual(history.ago(NOW - delta, NOW), expected)

    def test_object_names_are_normalized_the_same_way_everywhere(self):
        self.assertEqual(history.normalize_object('  My   Keys '), 'my keys')


if __name__ == '__main__':
    unittest.main()
