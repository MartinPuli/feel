import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import path, room_map  # noqa: E402

PROTOCOL = Path(__file__).resolve().parents[2] / 'protocol'


def grid(rows, cell_size=0.5, origin_x=0.0, origin_y=0.0):
    """A map from rows written in +y order, each a string of u/f/b, for readable tests."""
    return room_map.RoomMap(cell_size, origin_x, origin_y, len(rows[0]), len(rows), room_map.encode(''.join(rows)))


class CellTests(unittest.TestCase):
    def test_a_point_belongs_to_the_cell_on_its_positive_side_without_float_noise(self):
        self.assertEqual(path.cell_of(-2.05, 4.05, 0.1), (-21, 40))
        self.assertEqual(path.cell_of(1.1, -1.0, 0.1), (11, -10))
        self.assertEqual(path.cell_of(0.0, 0.0, 0.5), (0, 0))
        self.assertEqual(path.cell_of(-0.3, 0.3, 0.5), (-1, 0))
        self.assertEqual(path.centre(-1, 0, 0.5), (-0.25, 0.25))

    def test_coarsening_is_blocked_if_any_fine_cell_is_and_free_if_any_is(self):
        fine = grid(['ffffffffff', 'ffffffffff', 'ffffffffff', 'ffbfffffff', 'ffffffffff', 'ffffuuuuuu'], cell_size=0.1)
        coarse = path.coarsen(fine)
        self.assertEqual(coarse, {(0, 0): 'b', (1, 0): 'f', (0, 1): 'f'}, 'one blocked 10 cm cell blocks the half-metre cell; unseen cells are absent')
        self.assertEqual(path.coarsen(None), {})


class PlanTests(unittest.TestCase):
    def test_an_open_floor_gives_a_straight_suggested_direction(self):
        world = grid(['ffff'] * 4)
        polyline = path.plan(world, (0.25, 0.25), (1.75, 1.75))
        self.assertEqual(polyline, [(0.25, 0.25), (1.75, 1.75)], 'diagonal all the way: no corner')
        self.assertEqual(path.plan(world, (0.25, 0.25), (0.25, 1.75)), [(0.25, 0.25), (0.25, 1.75)])

    def test_a_wall_is_never_crossed_and_the_gap_is_used(self):
        world = grid(['fffffffff', 'fffffffff', 'bbbbfbbbb', 'fffffffff', 'fffffffff'])
        cells = path.plan_cells(path.coarsen(world), (4, 0), (4, 4))
        self.assertEqual(cells, [(4, 0), (4, 1), (4, 2), (4, 3), (4, 4)], 'straight through the gap in the wall')
        world = grid(['fffff', 'fffff', 'bbbbf', 'fffff', 'fffff'])
        cells = path.plan_cells(path.coarsen(world), (0, 0), (0, 4))
        self.assertNotIn('b', [world.state(ix, iy) for ix, iy in cells], 'no blocked cell on the way')
        self.assertTrue(any(ix < 0 for ix, _ in cells), 'the unknown floor beyond the map edge is a dearer way round a short wall, not a wall itself')

    def test_an_enclosed_start_has_no_path_and_the_goal_cell_may_be_a_door(self):
        world = grid(['bbb', 'bfb', 'bbb'])
        self.assertIsNone(path.plan_cells(path.coarsen(world), (1, 1), (5, 5)))
        self.assertIsNone(path.plan(world, (0.75, 0.75), (2.75, 2.75)))
        world = grid(['fff', 'bbb'])
        self.assertEqual(path.plan_cells(path.coarsen(world), (1, 0), (1, 1)), [(1, 0), (1, 1)], 'the goal is entered whatever its cell says')

    def test_unknown_costs_more_than_free_so_a_walked_corridor_is_preferred(self):
        world = grid(['fuuu', 'fuuu', 'fuuu', 'ffff'])
        cells = path.plan_cells(path.coarsen(world), (0, 0), (3, 3))
        self.assertEqual(cells, [(0, 0), (0, 1), (0, 2), (1, 3), (2, 3), (3, 3)], 'up the free column, then along the free row')

    def test_one_cell_of_clearance_is_kept_where_the_room_allows(self):
        world = grid(['fffff', 'fffff', 'fffff', 'ffbff', 'fffff', 'fffff', 'fffff'])
        cells = path.plan_cells(path.coarsen(world), (2, 0), (2, 6))
        self.assertFalse(any(abs(ix - 2) <= 1 and abs(iy - 3) <= 1 for ix, iy in cells), f'no cell touching the obstacle: {cells}')
        self.assertEqual((cells[0], cells[-1]), ((2, 0), (2, 6)))

    def test_diagonals_do_not_cut_a_blocked_corner(self):
        world = grid(['bf', 'ff'])
        self.assertEqual(path.plan_cells(path.coarsen(world), (0, 1), (1, 0)), [(0, 1), (1, 1), (1, 0)])

    def test_corners_are_where_the_direction_changes(self):
        self.assertEqual(path.corners([(0, 0), (1, 1), (2, 2), (3, 2), (4, 2), (4, 3)]), [(2, 2), (4, 2)])
        self.assertEqual(path.corners([(0, 0), (1, 0)]), [])
        self.assertEqual(path.corners([(0, 0)]), [])


class ProgressTests(unittest.TestCase):
    def test_points_every_six_metres_then_the_target(self):
        line = [(0.0, 0.0), (0.0, 20.0)]
        self.assertEqual(path.progress_points(line), [(0.0, 6.0), (0.0, 12.0), (0.0, 18.0), (0.0, 20.0)])
        self.assertEqual(path.progress_points([(0.0, 0.0), (0.0, 12.0)]), [(0.0, 6.0), (0.0, 12.0)], 'a point on the target is the target, once')
        self.assertEqual(path.progress_points([(0.0, 0.0), (3.0, 0.0)]), [(3.0, 0.0)], 'a short path has only the target')
        self.assertEqual(path.progress_points([(1.0, 1.0)]), [(1.0, 1.0)])
        self.assertEqual(path.progress_points([]), [])

    def test_points_follow_the_corners(self):
        bent = [(0.0, 0.0), (0.0, 4.0), (5.0, 4.0), (5.0, 10.0)]
        self.assertEqual(path.progress_points(bent), [(2.0, 4.0), (5.0, 7.0), (5.0, 10.0)])
        self.assertEqual(path.progress_points(bent, spacing=4.0), [(0.0, 4.0), (4.0, 4.0), (5.0, 7.0), (5.0, 10.0)])
        self.assertAlmostEqual(path.length(bent), 15.0)


class VectorTests(unittest.TestCase):
    def test_shared_vector_matches_what_the_phone_computes(self):
        vector = json.loads((PROTOCOL / 'journey-v1.json').read_text())
        world = room_map.from_json(json.dumps(dict(vector['world_map'], schema=1)))
        self.assertIsNotNone(world)
        plan = vector['plan']
        coarse = path.coarsen(world, plan['cell_size'])
        min_ix, min_iy = path.cell_of(plan['origin_x'], plan['origin_y'], plan['cell_size'])
        rows = [''.join(coarse.get((min_ix + ix, min_iy + iy), 'u') for ix in range(len(plan['rows'][0]))) for iy in range(len(plan['rows']))]
        self.assertEqual(rows, plan['rows'])
        case = vector['path']
        start, goal = tuple(case['from']), tuple(case['target'])
        cells = path.plan_cells(coarse, path.cell_of(*start, plan['cell_size']), path.cell_of(*goal, plan['cell_size']))
        self.assertEqual([list(cell) for cell in cells], case['cells'])
        polyline = path.plan(world, start, goal)
        self.assertEqual([list(point) for point in polyline], case['polyline'])
        self.assertEqual(round(path.length(polyline), 3), case['length_m'])
        self.assertEqual(case['progress_spacing_m'], path.SPACING)
        self.assertEqual([list(point) for point in path.progress_points(polyline)], case['progress_points'])


if __name__ == '__main__':
    unittest.main()
