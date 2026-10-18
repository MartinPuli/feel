"""The Chalk resolvers' pure parts. Skipped where chalkpy is not installed (only the Chalk
environment and chalk/feel_context/requirements.txt need it)."""
import json
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import anchors, journeys, room_map, venue_pack  # noqa: E402

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

    def test_room_structure_is_the_merge_of_shared_visits_served_by_a_named_query(self):
        for name in ('room_id', 'user_id', 'venue_id', 'tag_id', 'cell_size', 'origin_x', 'origin_y', 'width', 'height', 'cells', 'shared', 'seen_at'):
            self.assertTrue(hasattr(features.RoomMap, name), name)
        for name in ('maps', 'structure', 'structure_visits'):
            self.assertTrue(hasattr(features.RoomMemory, name), name)
        self.assertEqual(queries.room_structure.name, 'room_structure')
        self.assertEqual([str(f) for f in queries.room_structure.input], ['room_memory.id'])
        self.assertEqual([str(f) for f in queries.room_structure.output], ['room_memory.structure', 'room_memory.structure_visits'])
        self.assertIn('where shared', resolvers.MAP_SQL, 'Chalk merges only visits their owner chose to share')
        self.assertIn(f'limit {room_map.KEEP}', resolvers.MAP_SQL)
        vector = json.loads((PROTOCOL / 'room-map-v1.json').read_text())
        # Rows as the join hands them over, oldest first here: the merge must not care about their order.
        rows = [dict(visit, id=str(i), shared=True, seen_at=datetime(2026, 10, 17, 12 + i, tzinfo=timezone.utc)) for i, visit in enumerate(vector['visits'])]
        structure, visits = resolvers.room_structure(rows + [{'id': 'bad', 'cell_size': 0.1, 'origin_x': 0.0, 'origin_y': 0.0, 'width': 1, 'height': 1, 'cells': '2f'}])
        self.assertEqual(visits, 3, 'a row that does not validate is not a visit')
        want = vector['merged']
        self.assertEqual(room_map.from_json(structure),
                         room_map.RoomMap(want['cell_size'], want['origin_x'], want['origin_y'], want['width'], want['height'], want['cells']))
        self.assertEqual(resolvers.room_structure([]), (None, 0))

    def test_only_the_newest_shared_visits_vote_on_the_structure(self):
        def row(i, cells, hours):
            return {'id': str(i), 'cell_size': 0.1, 'origin_x': 0.0, 'origin_y': 0.0, 'width': 1, 'height': 1, 'cells': cells,
                    'seen_at': datetime(2026, 10, 1, tzinfo=timezone.utc) + timedelta(hours=hours) if hours is not None else None}
        rows = [row(i, '1b', i) for i in range(room_map.KEEP)] + [row(99, '1f', 100), row(98, '1f', None)]   # the newest is free; one row has no time
        structure, visits = resolvers.room_structure(rows)
        self.assertEqual(visits, room_map.KEEP, 'the oldest blocked visit and the timeless one fall off')
        self.assertEqual(room_map.from_json(structure).cells, '1b', 'one free visit among fifty is not half')
        structure, visits = resolvers.room_structure(rows[-1:] + rows[:1])
        self.assertEqual((visits, room_map.from_json(structure).cells), (2, '1b'), 'a tie goes to blocked; a row without a time still votes, as the oldest')

    def test_journeys_feed_the_world_map_and_the_path_is_served_by_named_queries(self):
        for name in ('room_id', 'user_id', 'venue_id', 'tag_id', 'session_id', 'target_label', 'started_at', 'arrived_at', 'arrival_distance_m',
                     'steps', 'obstacles', 'cue_latency_ms', 'shared'):
            self.assertTrue(hasattr(features.Journey, name), name)
        for name in ('journeys', 'world_map', 'world_map_journeys'):
            self.assertTrue(hasattr(features.RoomMemory, name), name)
        for name in ('venue_id', 'tag_id', 'from_x', 'from_y', 'label', 'room_id', 'room', 'polyline', 'progress_points', 'length_m', 'status'):
            self.assertTrue(hasattr(features.Path, name), name)
        self.assertEqual(str(features.Path.room.world_map), 'path.room.world_map', 'the planner reads the room through the has-one join')
        self.assertEqual([str(f) for f in queries.path.input], ['path.id'])
        self.assertEqual([str(f) for f in queries.path.output], ['path.polyline', 'path.progress_points', 'path.length_m', 'path.status'])
        self.assertEqual([str(f) for f in queries.progress_points.output], ['path.progress_points', 'path.status'])
        self.assertEqual(queries.world_map.name, 'world_map')
        self.assertEqual([str(f) for f in queries.world_map.output], ['room_memory.world_map', 'room_memory.world_map_journeys'])
        self.assertIn('where shared', resolvers.JOURNEY_SQL, 'Chalk reads only journeys their owner chose to share')
        self.assertIn('steps::text', resolvers.JOURNEY_SQL, 'the JSON columns travel as text')
        self.assertIn('where shared', resolvers.ROOMS_SQL)

    def test_path_ids_carry_the_pose_and_the_label(self):
        self.assertEqual(resolvers.split_path_id('harvard-yard:feel-tag-01:-0.3,0.3:exit'), ('harvard-yard', 'feel-tag-01', -0.3, 0.3, 'exit'))
        self.assertEqual(resolvers.split_path_id('v:t:1,2: Water  Fountain ')[4], 'water fountain')
        for bad in ['harvard-yard:feel-tag-01:exit', 'v:t:0.3:exit', 'v:t:a,b:exit', 'v:t:0,0:', 'v::0,0:exit', 'v:t:0,0:a:b', 'v:t:200,0:exit']:
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    resolvers.split_path_id(bad)

    def test_world_map_and_path_from_rows_match_the_shared_vector(self):
        vector = json.loads((PROTOCOL / 'journey-v1.json').read_text())
        now = datetime.fromisoformat(vector['now'].replace('Z', '+00:00'))
        structure = room_map.validate(**vector['world_map']['structure']).to_json()
        # Rows as the join hands them over: JSON columns as text, a naive time, and one row that does not validate.
        rows = [dict(journey, steps=json.dumps(journey['steps']), obstacles=json.dumps(journey['obstacles']), cue_latency_ms=json.dumps(journey['cue_latency_ms']),
                     started_at=datetime.fromisoformat(journey['started_at'].replace('Z', '')), id=str(i), shared=True)
                for i, journey in enumerate(vector['journeys'])]
        rows += [vector['stale_journey'], {'id': 'bad', 'steps': 'nope'}]
        world, count = resolvers.room_world_map(structure, rows, now)
        want = vector['world_map']
        self.assertEqual(count, want['journeys'], 'the stale journey and the unusable row are not in the map')
        self.assertEqual(room_map.from_json(world), room_map.RoomMap(want['cell_size'], want['origin_x'], want['origin_y'], want['width'], want['height'], want['cells']))
        self.assertEqual(resolvers.room_world_map(None, [], now), (None, 0))
        self.assertEqual(room_map.from_json(resolvers.room_world_map(structure, [], now)[0]).cells, want['structure']['cells'], 'without journeys the world map is the structure')
        targets = anchors.to_json([anchors.Remembered('exit', -4.0, 5.1, 0.05, 4, now), anchors.Remembered('water fountain', 2.0, 2.5, 0.3, 2, now)])
        case = vector['path']
        got = resolvers.suggested_path(case['from'][0], case['from'][1], 'exit', world, targets)
        self.assertEqual(got['status'], 'ok')
        self.assertEqual(json.loads(got['polyline']), case['polyline'])
        self.assertEqual(json.loads(got['progress_points']), case['progress_points'])
        self.assertEqual(got['length_m'], case['length_m'])
        self.assertEqual(resolvers.suggested_path(0.0, 0.0, 'stairs', world, targets), {'polyline': '[]', 'progress_points': '[]', 'length_m': 0.0, 'status': 'no target'})
        self.assertEqual(resolvers.suggested_path(0.0, 0.0, 'exit', None, targets)['status'], 'no map')
        self.assertEqual(resolvers.suggested_path(0.0, 0.0, 'exit', world, None)['status'], 'no target')
        self.assertEqual(resolvers.suggested_path(0.0, 0.0, 'exit', 'not a map', targets)['status'], 'no map')
        boxed = room_map.RoomMap(0.5, -0.5, -0.5, 3, 3, '4b1f4b').to_json()
        self.assertEqual(resolvers.suggested_path(0.25, 0.25, 'exit', boxed, targets)['status'], 'no path')
        self.assertEqual(journeys.WINDOW_DAYS, 60)


if __name__ == '__main__':
    unittest.main()
