import json
import math
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import anchors  # noqa: E402

NOW = datetime(2026, 10, 17, 22, 0, tzinfo=timezone.utc)
PROTOCOL = Path(__file__).resolve().parents[2] / 'protocol'


def row(label, x, y, z, ago, confidence=0.9):
    return {'label': label, 'x': x, 'y': y, 'z': z, 'confidence': confidence, 'seen_at': NOW - ago}


def stamp(value):
    return None if value is None else datetime.fromisoformat(value.replace('Z', '+00:00'))


class AnchorTests(unittest.TestCase):
    def test_each_label_gets_the_median_of_its_sightings(self):
        remembered = anchors.remember([row('Exit', -3.9, 5.2, 0.0, timedelta(hours=4)), row('exit', -4.1, 4.8, 0.1, timedelta(hours=3)),
                                       row('exit ', -4.3, 5.0, -0.1, timedelta(days=1)), row('exit', -3.7, 5.6, 0.2, timedelta(hours=2)),
                                       row('water  fountain', 2.0, 2.5, 0.3, timedelta(minutes=30))])
        self.assertEqual([t.label for t in remembered], ['exit', 'water fountain'])
        exit_, fountain = remembered
        self.assertEqual((exit_.x, exit_.y, exit_.z), (-4.0, 5.1, 0.05))
        self.assertEqual(exit_.sightings, 4)
        self.assertEqual(exit_.last_seen_at, NOW - timedelta(hours=2))
        self.assertEqual((fountain.x, fountain.y, fountain.z, fountain.sightings), (2.0, 2.5, 0.3, 1))

    def test_only_the_last_twenty_sightings_shape_the_position(self):
        rows = [row('door', float(i), 1.0, 0.0, timedelta(minutes=100 - i)) for i in range(25)]   # i = 24 is the newest
        door, = anchors.remember(rows)
        self.assertEqual(door.x, 14.5, 'median of x = 5 … 24, the newest twenty')
        self.assertEqual(door.sightings, 25)

    def test_rows_without_a_label_finite_coordinates_or_an_aware_time_are_ignored(self):
        naive = dict(row('desk', 1, 1, 0, timedelta()), seen_at=datetime(2026, 10, 17, 21, 0))
        rows = [row('  ', 0, 1, 0, timedelta()), row('chair', None, 1, 0, timedelta()), row('chair', math.nan, 1, 0, timedelta()),
                row('chair', 1, 1, 'z', timedelta()), dict(row('chair', 1, 1, 0, timedelta()), seen_at=None), naive]
        self.assertEqual(anchors.remember(rows), [])

    def test_spoken_summary_is_relative_time_and_direction_from_the_tag(self):
        remembered = anchors.remember([row('exit', -3.9, 5.2, 0.0, timedelta(hours=4)), row('exit', -4.1, 4.8, 0.1, timedelta(hours=3)),
                                       row('exit', -4.3, 5.0, -0.1, timedelta(days=1)), row('exit', -3.7, 5.6, 0.2, timedelta(hours=2)),
                                       row('water fountain', 2.0, 2.5, 0.3, timedelta(days=1)), row('water fountain', 2.2, 2.3, 0.3, timedelta(days=1))])
        self.assertEqual(anchors.spoken(remembered, NOW),
                         'Remembered here: exit about 6 meters ahead-right, seen 4 times, last 2 hours ago; '
                         'water fountain about 3 meters ahead-left, seen twice, last yesterday.')
        self.assertEqual(anchors.spoken([], NOW), 'Nothing is remembered at this tag yet.')
        once = anchors.remember([row('desk', 0.0, 0.4, 0.0, timedelta(seconds=10))])
        self.assertEqual(anchors.spoken(once, NOW), 'Remembered here: desk at the tag, seen once, last just now.')

    def test_directions_are_for_someone_standing_at_the_tag_with_their_back_to_it(self):
        cases = [((0, 3), 'ahead'), ((1, 3), 'ahead'), ((3, 3), 'ahead-left'), ((-3, 3), 'ahead-right'), ((3, 0), 'to the left'),
                 ((-3, 0.5), 'to the right'), ((3, -3), 'behind-left'), ((-3, -3), 'behind-right'), ((0, -3), 'behind')]
        for (x, y), expected in cases:
            with self.subTest(x=x, y=y):
                self.assertEqual(anchors.direction(x, y), expected)

    def test_distance_text(self):
        for metres, expected in [(0.4, 'at the tag'), (0.75, 'about 1 meter'), (1.4, 'about 1 meter'), (1.5, 'about 2 meters'), (6.3, 'about 6 meters')]:
            with self.subTest(metres=metres):
                self.assertEqual(anchors.distance_text(metres), expected)

    def test_json_round_trip_keeps_order_and_times(self):
        remembered = anchors.remember([row('exit', -4.0, 5.1, 0.05, timedelta(hours=2)), row('desk', 1.0, 2.0, 0.0, timedelta(hours=1))])
        text = anchors.to_json(remembered)
        self.assertEqual(json.loads(text)[0], {'label': 'desk', 'x': 1.0, 'y': 2.0, 'z': 0.0, 'sightings': 1, 'last_seen_at': '2026-10-17T21:00:00+00:00'})
        self.assertEqual(anchors.from_json(text), remembered)
        self.assertEqual(anchors.from_json('not json'), [])
        self.assertEqual(anchors.from_json('[{"label": "x"}]'), [])

    def test_shared_vector_matches_what_the_phone_computes(self):
        vector = json.loads((PROTOCOL / 'room-memory-v1.json').read_text())
        rows = [dict(a, seen_at=stamp(a['seen_at'])) for a in vector['anchors']]
        got = [{'label': t.label, 'x': t.x, 'y': t.y, 'z': t.z, 'sightings': t.sightings,
                'last_seen_at': t.last_seen_at.isoformat().replace('+00:00', 'Z')} for t in anchors.remember(rows)]
        self.assertEqual(got, vector['remembered'])

    def test_labels_are_normalized_like_object_names(self):
        self.assertEqual(anchors.normalize_label('  Water   Fountain '), 'water fountain')


if __name__ == '__main__':
    unittest.main()
