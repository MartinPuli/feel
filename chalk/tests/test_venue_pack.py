"""Venue pack builder: integrity hash, validation and the shared protocol vector. No network."""
import contextlib
import copy
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import venue_pack  # noqa: E402

PROTOCOL = Path(__file__).resolve().parents[2] / 'protocol'
GENERATED = datetime(2026, 10, 17, 12, tzinfo=timezone.utc)


def source():
    return json.loads((PROTOCOL / 'venue-pack-source.json').read_text())


class VenuePackTests(unittest.TestCase):
    def test_payload_hash_matches(self):
        pack = venue_pack.build(source(), GENERATED, days=7)
        self.assertEqual(pack['schema'], 1)
        self.assertEqual(pack['sha256'], hashlib.sha256(pack['payload'].encode('utf-8')).hexdigest())
        payload = json.loads(pack['payload'])
        self.assertEqual(payload['generated_at'], '2026-10-17T12:00:00Z')
        self.assertEqual(payload['expires_at'], '2026-10-24T12:00:00Z')

    def test_shared_vector_is_reproducible(self):
        expected = json.loads((PROTOCOL / 'venue-pack-v1.json').read_text())
        self.assertEqual(venue_pack.build(source(), GENERATED, days=7), expected)

    def test_invalid_sources_are_rejected(self):
        def changed(edit):
            data = copy.deepcopy(source())
            edit(data)
            return data
        entries = lambda data: data['entries']  # noqa: E731
        cases = {
            'no entries': changed(lambda d: d.update(entries=[])),
            'duplicate id': changed(lambda d: entries(d).append(copy.deepcopy(entries(d)[0]))),
            'plain http source': changed(lambda d: entries(d)[0].update(source_url='http://example.org/access')),
            'unknown kind': changed(lambda d: entries(d)[0].update(kind='rumor')),
            'empty text': changed(lambda d: entries(d)[0].update(text=' ')),
            'text too long': changed(lambda d: entries(d)[0].update(text='x' * 501)),
            'retrieved after build': changed(lambda d: entries(d)[0].update(retrieved_at='2026-10-18T00:00:00Z')),
            'restriction without target': changed(lambda d: entries(d)[2].pop('applies_to')),
            'restriction on unknown place': changed(lambda d: entries(d)[2].update(applies_to='nowhere')),
            'restriction without start': changed(lambda d: entries(d)[2].pop('effective_from')),
            'window ends before it starts': changed(lambda d: entries(d)[2].update(effective_until='2026-10-16T00:00:00Z')),
        }
        for name, data in cases.items():
            with self.subTest(name), self.assertRaises(venue_pack.VenuePackError):
                venue_pack.build(data, GENERATED, days=7)

    def test_same_second_retrieval_is_compared_before_wire_precision_truncation(self):
        data = source()
        data['entries'][0]['retrieved_at'] = '2026-10-17T12:00:00.400000+00:00'
        generated = GENERATED.replace(microsecond=600000)
        pack = venue_pack.build(data, generated, days=7)
        payload = json.loads(pack['payload'])
        self.assertEqual(payload['generated_at'], '2026-10-17T12:00:00Z')
        self.assertEqual(payload['entries'][0]['retrieved_at'], '2026-10-17T12:00:00Z')
        data['entries'][0]['retrieved_at'] = '2026-10-17T12:00:00.800000+00:00'
        with self.assertRaises(venue_pack.VenuePackError):
            venue_pack.build(data, generated, days=7)

    def test_build_clock_requires_explicit_timezone(self):
        with self.assertRaises(venue_pack.VenuePackError):
            venue_pack.build(source(), GENERATED.replace(tzinfo=None), days=7)

    def test_validity_must_be_positive(self):
        with self.assertRaises(venue_pack.VenuePackError):
            venue_pack.build(source(), GENERATED, days=0)

    def test_cli_never_overwrites_an_existing_file(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'pack.json'
            output.write_text('keep')
            with contextlib.redirect_stdout(io.StringIO()):
                code = venue_pack.main([str(PROTOCOL / 'venue-pack-source.json'), '--days', '7', '--output', str(output)])
            self.assertEqual(code, 2)
            self.assertEqual(output.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
