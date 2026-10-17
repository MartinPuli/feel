"""The Chalk resolvers' pure parts. Skipped where chalkpy is not installed (only the Chalk
environment and chalk/feel_context/requirements.txt need it)."""
import json
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import anchors, venue_pack  # noqa: E402

try:
    from feel_context import features, queries, resolvers
except ImportError:  # pragma: no cover
    features = queries = resolvers = None

PROTOCOL = Path(__file__).resolve().parents[2] / 'protocol'


class FakeFrame:
    def __init__(self, rows):
        self.rows = rows

    def to_pyarrow(self):
        return self

    def to_pylist(self):
        return self.rows


@unittest.skipUnless(resolvers, 'chalkpy is not installed here')
class FeelContextTests(unittest.TestCase):
    def test_rows_strip_the_feature_namespace(self):
        frame = FakeFrame([{'find.place': 'desk', 'find.found_at': datetime(2026, 1, 1, tzinfo=timezone.utc)}])
        self.assertEqual(resolvers.rows(frame), [{'place': 'desk', 'found_at': datetime(2026, 1, 1, tzinfo=timezone.utc)}])

    def test_pack_from_database_rows_matches_the_pack_from_the_reviewed_file(self):
        source = json.loads((PROTOCOL / 'venue-pack-source.json').read_text())
        when = datetime(2026, 10, 17, 20, 30, tzinfo=timezone.utc)
        expected = venue_pack.build(source, when, 7)

        def stamp(value):
            return None if value is None else datetime.fromisoformat(value.replace('Z', '+00:00'))
        rows = [{'id': e['id'], 'venue_id': source['venue_id'], 'kind': e['kind'], 'name': e['name'],
                 'aliases': e.get('aliases', []), 'text': e['text'], 'source_url': e['source_url'],
                 'retrieved_at': stamp(e['retrieved_at']), 'effective_from': stamp(e.get('effective_from')),
                 'effective_until': stamp(e.get('effective_until')), 'applies_to': e.get('applies_to')} for e in source['entries']]
        built = venue_pack.build(resolvers.pack_source(source['venue_id'], source['venue_name'], rows), when, 7)
        self.assertEqual(built, expected)

    def test_room_memory_is_keyed_by_venue_and_tag_and_served_by_a_named_query(self):
        self.assertEqual(resolvers.split_room_id('harvard-yard:feel-tag-01'), ('harvard-yard', 'feel-tag-01'))
        self.assertEqual(resolvers.split_room_id('no-tag'), ('no-tag', ''))
        for name in ('room_id', 'label', 'x', 'y', 'z', 'confidence', 'seen_at', 'shared'):
            self.assertTrue(hasattr(features.Anchor, name), name)
        for name in ('anchors', 'targets', 'targets_count', 'last_seen_at', 'spoken'):
            self.assertTrue(hasattr(features.RoomMemory, name), name)
        self.assertEqual(queries.room_anchors.name, 'room_anchors')
        self.assertEqual([str(f) for f in queries.room_anchors.input], ['room_memory.id'])
        self.assertEqual([str(f) for f in queries.room_anchors.output],
                         ['room_memory.spoken', 'room_memory.targets', 'room_memory.targets_count', 'room_memory.last_seen_at'])
        self.assertIn('where shared', resolvers.ANCHOR_SQL, 'Chalk aggregates only anchors their owner chose to share')

    def test_room_targets_from_anchor_rows_match_the_shared_aggregation(self):
        when = datetime(2026, 10, 17, 20, tzinfo=timezone.utc)
        rows = [{'label': 'exit', 'x': -4.0, 'y': 5.1, 'z': 0.0, 'confidence': 0.9, 'seen_at': when},
                {'label': 'exit', 'x': -4.2, 'y': 4.9, 'z': 0.1, 'confidence': 0.8, 'seen_at': datetime(2026, 10, 17, 19)}]   # naive: read as UTC
        targets, count, last_seen_at = resolvers.room_targets(rows)
        self.assertEqual((count, last_seen_at), (1, when))
        self.assertEqual(anchors.from_json(targets), anchors.remember([dict(rows[0]), dict(rows[1], seen_at=datetime(2026, 10, 17, 19, tzinfo=timezone.utc))]))
        self.assertEqual(resolvers.room_targets([]), ('[]', 0, None))

    def test_naive_database_times_are_read_as_utc(self):
        self.assertEqual(resolvers.pack_source('v', 'V', [{'id': 'a', 'kind': 'place', 'name': 'A', 'text': 't',
                                                           'source_url': 'https://x', 'retrieved_at': datetime(2026, 1, 1, 12)}])
                         ['entries'][0]['retrieved_at'], '2026-01-01T12:00:00+00:00')


if __name__ == '__main__':
    unittest.main()
