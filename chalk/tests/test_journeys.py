import json
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import journeys, room_map  # noqa: E402

PROTOCOL = Path(__file__).resolve().parents[2] / 'protocol'
VECTOR = json.loads((PROTOCOL / 'journey-v1.json').read_text())
NOW = datetime(2026, 10, 18, tzinfo=timezone.utc)


def row(**changes):
    base = {'venue_id': 'v', 'tag_id': 't', 'user_id': 'u', 'session_id': 's', 'started_at': '2026-10-17T18:00:00Z', 'target_label': 'exit',
            'steps': [{'t': 0, 'x': 0.0, 'y': 1.0, 'heading_deg': 0}, {'t': 2, 'x': 0.0, 'y': 2.0, 'heading_deg': 0}],
            'obstacles': [], 'cue_latency_ms': [100], 'arrived_at': '2026-10-17T18:00:02Z', 'arrival_distance_m': 0.0}
    return dict(base, **changes)


class RowTests(unittest.TestCase):
    def test_table_rows_and_export_rows_both_read(self):
        from_text = journeys.from_row(row(steps=json.dumps(row()['steps']), obstacles='[{"x": 1, "y": 1}]', cue_latency_ms='[100]',
                                         started_at=datetime(2026, 10, 17, 18), arrived_at=datetime(2026, 10, 17, 18, 0, 2)))
        from_lists = journeys.from_row(row(obstacles=[{'x': 1, 'y': 1}]))
        self.assertEqual(from_text, from_lists)
        self.assertEqual(from_lists.started_at, datetime(2026, 10, 17, 18, tzinfo=timezone.utc), 'naive database times are read as UTC')
        self.assertEqual(from_lists.obstacles, ((1.0, 1.0),))
        self.assertEqual(from_lists.steps[1], journeys.Step(2.0, 0.0, 2.0, 0.0))
        self.assertEqual(journeys.from_row(row(target_label='  Water   Fountain ')).target_label, 'water fountain')
        self.assertIsNone(journeys.from_row(row(arrived_at=None)).arrived_at)

    def test_rows_the_phone_could_not_have_written_are_ignored(self):
        bad = [row(steps='nope'), row(steps=[{'t': 0, 'x': 0.0}]), row(steps=[{'t': 0, 'x': 101.0, 'y': 0.0, 'heading_deg': 0}]),
               row(steps=[{'t': -1, 'x': 0.0, 'y': 0.0, 'heading_deg': 0}]), row(obstacles=[{'x': 1}]), row(obstacles=[[1, 1]]),
               row(cue_latency_ms=[-1]), row(cue_latency_ms=['fast']), row(arrival_distance_m=-0.1), row(arrival_distance_m=None),
               row(arrived_at='yesterday'), row(arrived_at='2026-10-17T17:00:00Z'), row(started_at=None), row(session_id=''),
               row(target_label=' '), row(venue_id=None)]
        for item in bad:
            with self.subTest(item=item):
                self.assertIsNone(journeys.from_row(item))
        self.assertEqual(len(journeys.usable([row(), row(steps='nope'), row(session_id='two')])), 2)

    def test_a_journey_round_trips_through_the_export_format(self):
        journey = journeys.from_row(row(obstacles=[{'x': 1, 'y': 1}]))
        self.assertEqual(journeys.from_row(journey.to_row()), journey)
        self.assertEqual(journey.to_row()['started_at'], '2026-10-17T18:00:00+00:00')


class ScoreTests(unittest.TestCase):
    def test_efficiency_is_the_straight_line_over_the_walk_and_zero_without_arrival(self):
        walked = journeys.from_row(row(steps=[{'t': 0, 'x': 0, 'y': 0, 'heading_deg': 0}, {'t': 1, 'x': 0, 'y': 4, 'heading_deg': 0},
                                              {'t': 2, 'x': 3, 'y': 4, 'heading_deg': 90}]))
        self.assertEqual(journeys.walked_m(walked), 7.0)
        self.assertEqual(journeys.path_efficiency(walked), 0.7143)
        self.assertEqual(journeys.path_efficiency(journeys.from_row(dict(walked.to_row(), arrived_at=None))), 0.0)
        still = journeys.from_row(row(steps=[{'t': 0, 'x': 0, 'y': 0, 'heading_deg': 0}]))
        self.assertEqual(journeys.path_efficiency(still), 0.0, 'nothing walked is no efficiency, not a division')

    def test_clearance_is_the_nearest_obstacle_to_any_step_and_a_collision_is_under_30_cm(self):
        journey = journeys.from_row(row(obstacles=[{'x': 0.2, 'y': 1.0}, {'x': 3.0, 'y': 3.0}]))
        self.assertEqual(journeys.min_clearance_m(journey), 0.2)
        self.assertEqual(journeys.score(journey).collisions, 1)
        self.assertIsNone(journeys.min_clearance_m(journeys.from_row(row())))
        self.assertEqual(journeys.score(journeys.from_row(row())).collisions, 0)
        self.assertEqual(journeys.score(journeys.from_row(row(obstacles=[{'x': 0.3, 'y': 1.0}]))).collisions, 0, '0.3 m is not under 0.3 m')

    def test_p95_is_the_nearest_rank_percentile_of_the_where_is_report(self):
        self.assertEqual(journeys.p95([120, 95, 140, 110, 400]), 400)
        self.assertEqual(journeys.p95([90, 100, 110, 130]), 130)
        self.assertEqual(journeys.p95(range(1, 101)), 95)
        self.assertIsNone(journeys.p95([]))

    def test_rank_is_collisions_then_efficiency_then_latency(self):
        clean_slow = journeys.from_row(row(session_id='clean-slow', cue_latency_ms=[900]))
        clean_fast = journeys.from_row(row(session_id='clean-fast', cue_latency_ms=[100]))
        bent = journeys.from_row(row(session_id='bent', steps=[{'t': 0, 'x': 0, 'y': 0, 'heading_deg': 0}, {'t': 1, 'x': 1, 'y': 0, 'heading_deg': 90},
                                                              {'t': 2, 'x': 1, 'y': 1, 'heading_deg': 0}], cue_latency_ms=[50]))
        hit = journeys.from_row(row(session_id='hit', obstacles=[{'x': 0.1, 'y': 1.0}], cue_latency_ms=[10]))
        silent = journeys.from_row(row(session_id='silent', cue_latency_ms=[]))
        ranked = [journey.session_id for journey, _ in journeys.rank([hit, silent, bent, clean_slow, clean_fast])]
        self.assertEqual(ranked, ['clean-fast', 'clean-slow', 'silent', 'bent', 'hit'], 'no latency at all ranks after any latency')

    def test_window_keeps_sixty_days(self):
        def at(days_ago, session):
            return journeys.from_row(row(session_id=session, started_at=(NOW - timedelta(days=days_ago)).isoformat(), arrived_at=None))
        kept = journeys.within_days([at(0, 'today'), at(60, 'edge'), at(61, 'old'), at(-1, 'future')], NOW)
        self.assertEqual([j.session_id for j in kept], ['today', 'edge'])
        self.assertEqual(journeys.WINDOW_DAYS, 60)
        self.assertEqual([j.session_id for j in journeys.within_days([at(10, 'a')], NOW, days=5)], [])


class WorldMapTests(unittest.TestCase):
    def test_steps_free_cells_obstacles_block_them_and_both_beat_the_structure(self):
        structure = room_map.RoomMap(0.1, 0.0, 0.0, 2, 1, '1f1b')
        journey = journeys.from_row(row(steps=[{'t': 0, 'x': 0.15, 'y': 0.05, 'heading_deg': 0}, {'t': 1, 'x': 0.25, 'y': 0.05, 'heading_deg': 0}],
                                        obstacles=[{'x': 0.05, 'y': 0.05}, {'x': 0.25, 'y': 0.05}]))
        world = journeys.world_map(structure, [journey], NOW)
        self.assertEqual(world, room_map.RoomMap(0.1, 0.0, 0.0, 3, 1, '1b1f1b'), 'blocked over the free vote, free over the blocked vote, obstacle over step')
        self.assertEqual(journeys.world_map(None, [journey], NOW).cell_size, journeys.DEFAULT_CELL)
        self.assertEqual(journeys.world_map(None, [journey], NOW).cells, '1b1f1b')
        self.assertEqual(journeys.world_map(structure, [], NOW), structure)
        self.assertIsNone(journeys.world_map(None, [], NOW))

    def test_old_journeys_drop_out_of_the_map(self):
        old = journeys.from_row(row(started_at='2026-01-01T00:00:00Z', arrived_at=None, obstacles=[{'x': 0.05, 'y': 0.05}]))
        self.assertIsNone(journeys.world_map(None, [old], NOW))
        self.assertEqual(journeys.world_map(None, [old], datetime(2026, 1, 2, tzinfo=timezone.utc)).blocked, 1)

    def test_a_map_wider_than_the_phone_could_hold_is_refused(self):
        far = journeys.from_row(row(steps=[{'t': 0, 'x': -100.0, 'y': -100.0, 'heading_deg': 0}, {'t': 1, 'x': 100.0, 'y': 100.0, 'heading_deg': 0}]))
        self.assertIsNone(journeys.world_map(None, [far], NOW))


class VectorTests(unittest.TestCase):
    def test_shared_vector_scores_ranking_and_world_map(self):
        built = journeys.usable(VECTOR['journeys'])
        self.assertEqual(len(built), len(VECTOR['journeys']))
        for journey, case in zip(built, VECTOR['journeys']):
            with self.subTest(session=case['session_id']):
                scores = journeys.score(journey)
                self.assertEqual({'arrived': scores.arrived, 'min_clearance_m': scores.min_clearance_m, 'collisions': scores.collisions,
                                  'path_efficiency': scores.path_efficiency, 'cue_latency_p95_ms': scores.cue_latency_p95_ms}, case['scores'])
        self.assertEqual([journey.session_id for journey, _ in journeys.rank(built)], VECTOR['ranking'])
        now = journeys._time(VECTOR['now'])
        stale = journeys.from_row(VECTOR['stale_journey'])
        self.assertIsNotNone(stale)
        self.assertEqual(journeys.within_days(built + [stale], now), built)
        want = VECTOR['world_map']
        structure = room_map.validate(**want['structure'])
        world = journeys.world_map(structure, built + [stale], now)
        self.assertEqual(world, room_map.RoomMap(want['cell_size'], want['origin_x'], want['origin_y'], want['width'], want['height'], want['cells']))
        self.assertEqual((world.observed, world.blocked), (want['observed'], want['blocked']))
        self.assertEqual(len(journeys.within_days(built + [stale], now)), want['journeys'])


if __name__ == '__main__':
    unittest.main()
