"""A suggested direction over the room's world map: A* on coarse cells, a polyline, progress points every 6 m.

Pure functions shared by the Chalk resolvers in chalk/feel_context (Path.polyline, Path.progress_points) and their
tests; protocol/journey-v1.json is the vector the phone must reproduce for the progress points and, if it plans with
these rules, the path. No Chalk import here.

The world map is a feel_chalk.room_map.RoomMap in the printed tag's levelled frame (x right along the tag, y out into
the room, metres). The planner coarsens it to PLAN_CELL metre cells (a coarse cell is blocked when any fine cell whose
centre falls in it is blocked, free when any is free and none blocked, unknown otherwise) and searches the box around
the map, the start and the goal, MARGIN cells wider on every side.

Moves go to the 8 neighbours; a diagonal move is refused when either cell it cuts between is blocked. The cost of a
move is its length (1 or sqrt 2 cells) times the cost of the cell it enters: FREE_COST for free, UNKNOWN_COST for unknown,
plus CLEARANCE_COST when that cell touches a blocked cell (8-neighbourhood), so the planner keeps one cell of clearance
where it can and still reaches a door. Blocked cells are never entered, except the goal cell: a remembered exit is a
gap in a wall the map may show closed. The heuristic is octile distance times FREE_COST. Ties open the node with the
lower heuristic first, then the one pushed first; neighbours are pushed in the order of NEIGHBOURS. Costs are rounded
to a micro-cell so the same ties resolve the same way everywhere.

The polyline is the start point, the centre of every coarse cell where the path turns, and the goal point. Progress
points are every SPACING metres along it, the last one always the goal. Nothing here says a path is clear or safe:
a path is a suggested direction over remembered cells, and the live camera decides each step.
"""
from __future__ import annotations
import heapq
import math

from . import room_map

PLAN_CELL = 0.5          # metres; one cell of clearance is half a metre
MARGIN = 2               # cells around the box of map, start and goal the search may use
MAX_CELLS = 250_000      # same bound as the room map
FREE_COST = 1.0
UNKNOWN_COST = 2.0
CLEARANCE_COST = 1.0
SPACING = 6.0            # metres between progress points
NEIGHBOURS = ((1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, 1), (-1, -1), (1, -1))
SQRT2 = math.sqrt(2.0)


def cell_of(x: float, y: float, cell_size: float) -> tuple[int, int]:
    """The lattice cell holding a point: floor of the quotient after rounding away float noise, so a point on a cell
    edge belongs to the cell on its positive side and -2.05 / 0.1 is -21, not -20."""
    return (math.floor(round(x / cell_size, 6)), math.floor(round(y / cell_size, 6)))


def centre(ix: int, iy: int, cell_size: float) -> tuple[float, float]:
    return (round((ix + 0.5) * cell_size, 3), round((iy + 0.5) * cell_size, 3))


def coarsen(world: room_map.RoomMap | None, plan_cell: float = PLAN_CELL) -> dict[tuple[int, int], str]:
    """Observed coarse cells: blocked when any fine cell whose centre falls in the coarse cell is blocked, free when
    any is free and none blocked. Unobserved coarse cells are absent (unknown)."""
    coarse: dict[tuple[int, int], str] = {}
    if world is None:
        return coarse
    states = world.states
    for iy in range(world.height):
        for ix in range(world.width):
            state = states[iy * world.width + ix]
            if state == room_map.UNKNOWN:
                continue
            key = cell_of(*centre(world.min_ix + ix, world.min_iy + iy, world.cell_size), plan_cell)
            if state == room_map.BLOCKED or coarse.get(key) != room_map.BLOCKED:
                coarse[key] = state
    return coarse


def _octile(a: tuple[int, int], b: tuple[int, int]) -> float:
    dx, dy = abs(a[0] - b[0]), abs(a[1] - b[1])
    return max(dx, dy) + (SQRT2 - 1.0) * min(dx, dy)


def plan_cells(coarse: dict[tuple[int, int], str], start: tuple[int, int], goal: tuple[int, int]) -> list[tuple[int, int]] | None:
    """A* from the start cell to the goal cell over the coarse map; the cells of the path including both ends, or None
    when no path exists inside the search box or the box would be larger than MAX_CELLS."""
    xs = [start[0], goal[0]] + [ix for ix, _ in coarse]
    ys = [start[1], goal[1]] + [iy for _, iy in coarse]
    lo_x, hi_x, lo_y, hi_y = min(xs) - MARGIN, max(xs) + MARGIN, min(ys) - MARGIN, max(ys) + MARGIN
    if (hi_x - lo_x + 1) * (hi_y - lo_y + 1) > MAX_CELLS:
        return None

    def blocked(cell):
        return cell != goal and coarse.get(cell) == room_map.BLOCKED

    def enter_cost(cell):
        base = FREE_COST if cell == goal or coarse.get(cell) == room_map.FREE else UNKNOWN_COST
        near = any(coarse.get((cell[0] + dx, cell[1] + dy)) == room_map.BLOCKED for dx, dy in NEIGHBOURS)
        return base + (CLEARANCE_COST if near else 0.0)

    best = {start: 0.0}
    parent: dict[tuple[int, int], tuple[int, int]] = {}
    counter = 0
    heap = [(round(_octile(start, goal) * FREE_COST, 6), round(_octile(start, goal), 6), counter, start)]
    closed = set()
    while heap:
        _, _, _, cell = heapq.heappop(heap)
        if cell in closed:
            continue
        if cell == goal:
            path = [cell]
            while path[-1] != start:
                path.append(parent[path[-1]])
            return path[::-1]
        closed.add(cell)
        for dx, dy in NEIGHBOURS:
            nxt = (cell[0] + dx, cell[1] + dy)
            if not (lo_x <= nxt[0] <= hi_x and lo_y <= nxt[1] <= hi_y) or nxt in closed or blocked(nxt):
                continue
            if dx and dy and (blocked((cell[0] + dx, cell[1])) or blocked((cell[0], cell[1] + dy))):
                continue
            g = round(best[cell] + (SQRT2 if dx and dy else 1.0) * enter_cost(nxt), 6)
            if g < best.get(nxt, math.inf):
                best[nxt] = g
                parent[nxt] = cell
                counter += 1
                h = _octile(nxt, goal)
                heapq.heappush(heap, (round(g + h * FREE_COST, 6), round(h, 6), counter, nxt))
    return None


def corners(cells: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """The cells where the path changes direction, without its two ends."""
    turns = []
    for before, cell, after in zip(cells, cells[1:], cells[2:]):
        if (cell[0] - before[0], cell[1] - before[1]) != (after[0] - cell[0], after[1] - cell[1]):
            turns.append(cell)
    return turns


def plan(world: room_map.RoomMap | None, start: tuple[float, float], goal: tuple[float, float],
         plan_cell: float = PLAN_CELL) -> list[tuple[float, float]] | None:
    """The polyline from the start point to the goal point (metres, 3 decimals): the start, the centre of each coarse
    cell where the path turns, the goal. None when no path exists."""
    cells = plan_cells(coarsen(world, plan_cell), cell_of(*start, plan_cell), cell_of(*goal, plan_cell))
    if cells is None:
        return None
    points = [(round(start[0], 3), round(start[1], 3))]
    points += [centre(ix, iy, plan_cell) for ix, iy in corners(cells)]
    points.append((round(goal[0], 3), round(goal[1], 3)))
    return points


def length(polyline: list[tuple[float, float]]) -> float:
    return sum(math.dist(a, b) for a, b in zip(polyline, polyline[1:]))


def progress_points(polyline: list[tuple[float, float]], spacing: float = SPACING) -> list[tuple[float, float]]:
    """Points every `spacing` metres along the polyline, the first `spacing` metres in, and the last point of the
    polyline (the goal) always last, never twice. An empty or single-point polyline gives just its last point."""
    if not polyline:
        return []
    points: list[tuple[float, float]] = []
    walked = 0.0
    next_at = spacing
    for a, b in zip(polyline, polyline[1:]):
        segment = math.dist(a, b)
        while segment > 0 and next_at <= walked + segment - 1e-9:
            along = (next_at - walked) / segment
            points.append((round(a[0] + (b[0] - a[0]) * along, 3), round(a[1] + (b[1] - a[1]) * along, 3)))
            next_at += spacing
        walked += segment
    points.append((round(polyline[-1][0], 3), round(polyline[-1][1], 3)))
    return points
