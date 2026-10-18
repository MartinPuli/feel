import json
import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import room_map  # noqa: E402

PROTOCOL = Path(__file__).resolve().parents[2] / 'protocol'

# The three visits of protocol/room-map-v1.json, by hand: a 6 x 6 room with a chair and a far wall, the same room seen
# two cells farther left without the chair, and a smaller third view.
VISIT_1 = room_map.RoomMap(0.1, 0.0, 0.0, 6, 6, '14f2b4f2b8f6b')
VISIT_2 = room_map.RoomMap(0.1, -0.2, 0.0, 8, 6, '40f2u6b')
VISIT_3 = room_map.RoomMap(0.1, 0.1, 0.1, 4, 5, '9f1u1b5f4b')


def grid(cell_size, origin_x, origin_y, rows):
    """A map from rows written in +y order, each a string of u/f/b, for readable tests."""
    return room_map.RoomMap(cell_size, origin_x, origin_y, len(rows[0]), len(rows), room_map.encode(''.join(rows)))


class EncodingTests(unittest.TestCase):
    def test_cells_are_run_length_encoded_over_the_row_major_array(self):
        states = list('ffbuuuff')
        self.assertEqual(room_map.encode(states), '2f1b3u2f')
        self.assertEqual(room_map.decode('2f1b3u2f', 8), states)
        self.assertEqual(room_map.decode('2f2f', 4), list('ffff'), 'split runs decode; the encoding is canonical')
        self.assertEqual(room_map.encode(room_map.decode('2f2f', 4)), '4f')
        self.assertEqual(room_map.encode([]), '')

    def test_malformed_runs_decode_to_nothing(self):
        for text, count in [('2f1b3u2f', 7), ('2f1b3u2f', 9), ('2x', 2), ('0f1f', 1), ('f', 1), ('1f 1f', 2), ('-1f', 1), ('1F', 1), ('', 1)]:
            with self.subTest(text=text, count=count):
                self.assertIsNone(room_map.decode(text, count))
        self.assertEqual(room_map.decode('', 0), [])


class MapTests(unittest.TestCase):
    def test_a_map_knows_its_cells_by_index(self):
        self.assertEqual((VISIT_2.min_ix, VISIT_2.min_iy), (-2, 0))
        self.assertEqual(VISIT_1.state(2, 2), 'b')
        self.assertEqual(VISIT_1.state(0, 0), 'f')
        self.assertEqual(VISIT_1.state(0, 5), 'b')
        self.assertEqual(VISIT_1.state(6, 0), 'u', 'outside the map is unknown')
        self.assertEqual(VISIT_2.state(-2, 5), 'u')
        self.assertEqual(VISIT_2.state(-2, 4), 'f')
        self.assertEqual(VISIT_1.observed, 36)
        self.assertEqual(VISIT_2.observed, 46)
        self.assertEqual(VISIT_1.blocked, 10)

    def test_validation_refuses_what_the_phone_could_never_hold(self):
        good = dict(cell_size=0.1, origin_x=-0.2, origin_y=0.0, width=8, height=6, cells='40f2u6b')
        self.assertEqual(room_map.validate(**good), VISIT_2)
        bad = [dict(good, cell_size=0), dict(good, cell_size=math.nan), dict(good, cell_size=1.5), dict(good, width=0), dict(good, height=0),
               dict(good, width=600, height=600, cells='360000f'), dict(good, origin_x=-0.25), dict(good, origin_y=math.inf),
               dict(good, origin_x=-101.0), dict(good, cells='40f2u5b'), dict(good, cells='40f2u7b'), dict(good, cells='40f2u6x'),
               dict(good, width=8.5), dict(good, width='8'), dict(good, cells=None), dict(good, cell_size='0.1')]
        for row in bad:
            with self.subTest(row=row):
                self.assertIsNone(room_map.validate(**row))

    def test_json_round_trip_uses_the_table_column_names(self):
        text = VISIT_2.to_json()
        self.assertEqual(json.loads(text), {'schema': 1, 'cell_size': 0.1, 'origin_x': -0.2, 'origin_y': 0.0, 'width': 8, 'height': 6, 'cells': '40f2u6b'})
        self.assertEqual(room_map.from_json(text), VISIT_2)
        for malformed in ['not json', '[]', '{"schema": 2, "cell_size": 0.1, "origin_x": 0, "origin_y": 0, "width": 1, "height": 1, "cells": "1f"}',
                          '{"cell_size": 0.1, "origin_x": 0, "origin_y": 0, "width": 1, "height": 1}',
                          '{"schema": 1, "cell_size": 0.1, "origin_x": 0, "origin_y": 0, "width": 1, "height": 1, "cells": "2f"}']:
            with self.subTest(malformed=malformed):
                self.assertIsNone(room_map.from_json(malformed))

    def test_database_rows_become_maps_and_unusable_rows_are_ignored(self):
        rows = [{'id': 'a', 'cell_size': 0.1, 'origin_x': 0.0, 'origin_y': 0.0, 'width': 6, 'height': 6, 'cells': '14f2b4f2b8f6b', 'shared': True},
                {'id': 'b', 'cell_size': 0.1, 'origin_x': -0.2, 'origin_y': 0.0, 'width': 8, 'height': 6, 'cells': '40f2u6b'},
                {'id': 'c', 'cell_size': 0.1, 'origin_x': -0.2, 'origin_y': 0.0, 'width': 8, 'height': 6, 'cells': '40f2u5b'},
                {'id': 'd', 'cell_size': None, 'origin_x': 0.0, 'origin_y': 0.0, 'width': 1, 'height': 1, 'cells': '1f'},
                {'id': 'e', 'origin_x': 0.0, 'origin_y': 0.0, 'width': 1, 'height': 1, 'cells': '1f'},
                {'id': 'f', 'cell_size': 0.1, 'origin_x': 0.0, 'origin_y': 0.0, 'width': True, 'height': 1, 'cells': '1f'}]
        self.assertEqual(room_map.usable(rows), [VISIT_1, VISIT_2])


class MergeTests(unittest.TestCase):
    def test_one_visit_merges_to_itself(self):
        self.assertEqual(room_map.merge([VISIT_1]), VISIT_1)

    def test_blocked_needs_at_least_half_of_the_visits_that_saw_the_cell(self):
        seen_blocked = grid(0.1, 0.0, 0.0, ['b'])
        seen_free = grid(0.1, 0.0, 0.0, ['f'])
        self.assertEqual(room_map.merge([seen_blocked, seen_free]).cells, '1b', 'a tie goes to blocked')
        self.assertEqual(room_map.merge([seen_blocked, seen_free, seen_free]).cells, '1f', 'one visit in three is not half')
        self.assertEqual(room_map.merge([seen_blocked, seen_blocked, seen_free, seen_free]).cells, '1b')
        self.assertEqual(room_map.merge([seen_blocked, seen_free, seen_free, seen_free]).cells, '1f')
        unseen = grid(0.1, 0.0, 0.0, ['u'])
        self.assertEqual(room_map.merge([seen_blocked, unseen, unseen]).cells, '1b', 'visits that did not see the cell do not vote')
        self.assertIsNone(room_map.merge([unseen, unseen]), 'nothing observed is nothing remembered')

    def test_merge_keeps_the_wall_and_drops_the_transient_obstacle(self):
        merged = room_map.merge([VISIT_1, VISIT_2, VISIT_3])
        self.assertEqual(merged, room_map.RoomMap(0.1, -0.2, 0.0, 8, 6, '28f2b10f2u6b'))
        self.assertEqual([merged.state(x, 5) for x in range(-2, 6)], list('uubbbbbb'), 'the far wall, wherever a visit saw it')
        self.assertEqual([merged.state(x, 2) for x in range(2, 4)], ['f', 'f'], 'the chair seen once in three visits is gone')
        self.assertEqual(merged.state(2, 3), 'b', 'blocked once, free once, unseen once: a tie stays blocked')
        self.assertEqual(merged.state(3, 3), 'b', 'the bag seen twice in three visits stays')

    def test_merge_covers_the_union_of_what_was_observed(self):
        left = grid(0.1, -0.3, 0.2, ['fb'])
        right = grid(0.1, 0.5, -0.1, ['f', 'b'])
        merged = room_map.merge([left, right])
        self.assertEqual((merged.origin_x, merged.origin_y, merged.width, merged.height), (-0.3, -0.1, 9, 4))
        self.assertEqual(merged.state(-3, 2), 'f')
        self.assertEqual(merged.state(-2, 2), 'b')
        self.assertEqual(merged.state(5, -1), 'f')
        self.assertEqual(merged.state(5, 0), 'b')
        self.assertEqual(merged.state(0, 0), 'u')
        self.assertEqual(merged.observed, 4)

    def test_merge_refuses_mixed_cell_sizes_and_nothing(self):
        self.assertIsNone(room_map.merge([]))
        self.assertIsNone(room_map.merge([VISIT_1, grid(0.2, 0.0, 0.0, ['f'])]))

    def test_only_the_newest_visits_are_merged(self):
        newest_first = [grid(0.1, 0.0, 0.0, ['f'])] * 2 + [grid(0.1, 0.0, 0.0, ['b'])] * 3
        self.assertEqual(room_map.merge(newest_first).cells, '1b')
        self.assertEqual(room_map.merge(newest_first, keep=2).cells, '1f')
        self.assertEqual(room_map.KEEP, 50)

    def test_shared_vector_matches_what_the_phone_computes(self):
        vector = json.loads((PROTOCOL / 'room-map-v1.json').read_text())
        encoding = vector['encoding']
        self.assertEqual(room_map.encode(encoding['states']), encoding['cells'])
        self.assertEqual(room_map.decode(encoding['cells'], encoding['width'] * encoding['height']), encoding['states'])
        visits = room_map.usable(vector['visits'])
        self.assertEqual(len(visits), len(vector['visits']))
        merged = room_map.merge(visits)
        want = vector['merged']
        self.assertEqual(merged, room_map.RoomMap(want['cell_size'], want['origin_x'], want['origin_y'], want['width'], want['height'], want['cells']))
        self.assertEqual(len(visits), want['visits'])


if __name__ == '__main__':
    unittest.main()
