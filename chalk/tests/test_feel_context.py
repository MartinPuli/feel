"""The Chalk resolvers' pure parts. Skipped where chalkpy is not installed (only the Chalk
environment and chalk/feel_context/requirements.txt need it)."""
import json
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import venue_pack  # noqa: E402

try:
    from feel_context import resolvers
except ImportError:  # pragma: no cover
    resolvers = None

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

    def test_naive_database_times_are_read_as_utc(self):
        self.assertEqual(resolvers.pack_source('v', 'V', [{'id': 'a', 'kind': 'place', 'name': 'A', 'text': 't',
                                                           'source_url': 'https://x', 'retrieved_at': datetime(2026, 1, 1, 12)}])
                         ['entries'][0]['retrieved_at'], '2026-01-01T12:00:00+00:00')


if __name__ == '__main__':
    unittest.main()
