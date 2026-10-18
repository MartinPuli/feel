"""Room structure memory: the floor plan FEEL's route planner learned on earlier visits, in a printed tag's frame.

Pure functions shared by the Chalk resolvers in chalk/feel_context (RoomMemory.structure) and their tests, and
mirrored by FeelCore's RoomMap on the phone (protocol/room-map-v1.json is the vector both must reproduce).
No Chalk import here.

A map is a grid of cells, each unknown, free or blocked, in the levelled frame of the tag: x right along the tag,
y out of the tag into the room, in metres. The origin is the corner of the cell with the smallest indices and
sits on the cell lattice (rounded to the nanometre, so the same corner is always the same number). Cells are
run-length encoded over the row-major array, +x within a row and rows in +y: <count><state> with u, f and b;
the canonical encoding uses maximal runs.

Visits merge by a per-cell vote: unknown when no visit observed the cell; blocked when at least half of the visits
that observed it saw it blocked (a tie goes to blocked: a missed wall costs more than a spurious one, which the live
camera overrides); free otherwise. A merged map only seeds the route planner before the camera has seen the room.
It never drives the pins.
"""
from __future__ import annotations
from dataclasses import asdict, dataclass
from functools import cached_property
import json
import math
import re

SCHEMA = 1
UNKNOWN, FREE, BLOCKED = 'u', 'f', 'b'
STATES = frozenset((UNKNOWN, FREE, BLOCKED))
KEEP = 50               # newest shared visits merged per tag; the SQL in feel_context/resolvers.py returns no more
MAX_SIDE = 2000         # cells per side
MAX_CELLS = 250_000     # 50 m x 50 m at 10 cm, the same bound as the phone's route planner window
MAX_CELL_SIZE = 1.0     # metres
REACH = 100.0           # metres from the tag, like anchors
_RUN = re.compile(r'([1-9][0-9]*)([ufb])')


def encode(states) -> str:
    """Canonical run-length encoding of a row-major sequence of u/f/b states."""
    runs, current, length = [], None, 0
    for state in states:
        if state not in STATES:
            raise ValueError(f'not a cell state: {state!r}')
        if state == current:
            length += 1
        else:
            if current is not None:
                runs.append(f'{length}{current}')
            current, length = state, 1
    if current is not None:
        runs.append(f'{length}{current}')
    return ''.join(runs)


def decode(text, count) -> list[str] | None:
    """The states behind an encoding of exactly `count` cells, or None for anything malformed."""
    if not isinstance(text, str) or isinstance(count, bool) or not isinstance(count, int) or count < 0:
        return None
    states: list[str] = []
    position = 0
    for match in _RUN.finditer(text):
        if match.start() != position:
            return None
        position = match.end()
        states.extend(match.group(2) * int(match.group(1)))
        if len(states) > count:
            return None
    if position != len(text) or len(states) != count:
        return None
    return states


def _real(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _integer(value) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _lattice_index(origin: float, cell_size: float) -> int:
    index = round(origin / cell_size)
    if abs(origin / cell_size - index) > 1e-6:
        raise ValueError(f'origin {origin} is not on the {cell_size} m lattice')
    return index


def _origin(index: int, cell_size: float) -> float:
    return round(index * cell_size, 9)


@dataclass(frozen=True)
class RoomMap:
    cell_size: float
    origin_x: float
    origin_y: float
    width: int
    height: int
    cells: str

    def __post_init__(self):
        if not (_real(self.cell_size) and 0 < self.cell_size <= MAX_CELL_SIZE):
            raise ValueError(f'cell size {self.cell_size!r}')
        for origin in (self.origin_x, self.origin_y):
            if not _real(origin) or abs(origin) > REACH:
                raise ValueError(f'origin {origin!r}')
        if not (_integer(self.width) and _integer(self.height) and 1 <= self.width <= MAX_SIDE and 1 <= self.height <= MAX_SIDE
                and self.width * self.height <= MAX_CELLS):
            raise ValueError(f'size {self.width!r} x {self.height!r}')
        states = decode(self.cells, self.width * self.height)
        if states is None:
            raise ValueError('cells do not encode the map')
        # Canonical: origins on the lattice, maximal runs, so equal maps compare equal.
        object.__setattr__(self, 'origin_x', _origin(_lattice_index(self.origin_x, self.cell_size), self.cell_size))
        object.__setattr__(self, 'origin_y', _origin(_lattice_index(self.origin_y, self.cell_size), self.cell_size))
        object.__setattr__(self, 'cells', encode(states))

    @property
    def min_ix(self) -> int:
        return round(self.origin_x / self.cell_size)

    @property
    def min_iy(self) -> int:
        return round(self.origin_y / self.cell_size)

    @cached_property
    def states(self) -> list[str]:
        return decode(self.cells, self.width * self.height)

    @property
    def observed(self) -> int:
        return sum(state != UNKNOWN for state in self.states)

    @property
    def blocked(self) -> int:
        return self.states.count(BLOCKED)

    def state(self, ix: int, iy: int) -> str:
        """The cell at lattice indices (ix, iy); outside the map is unknown."""
        if not (self.min_ix <= ix < self.min_ix + self.width and self.min_iy <= iy < self.min_iy + self.height):
            return UNKNOWN
        return self.states[(iy - self.min_iy) * self.width + (ix - self.min_ix)]

    def to_dict(self) -> dict:
        return {'schema': SCHEMA, **asdict(self)}

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), sort_keys=True)


def validate(cell_size, origin_x, origin_y, width, height, cells) -> RoomMap | None:
    """A map from the six table columns, or None when any of them is not what the phone could hold."""
    if not all(_real(value) for value in (cell_size, origin_x, origin_y)) or not (_integer(width) and _integer(height)) \
            or not isinstance(cells, str):
        return None
    try:
        return RoomMap(float(cell_size), float(origin_x), float(origin_y), width, height, cells)
    except ValueError:
        return None


def from_json(text) -> RoomMap | None:
    """The map back from `to_json`; anything malformed reads as no map."""
    try:
        item = json.loads(text)
    except (TypeError, ValueError):
        return None
    if not isinstance(item, dict) or item.get('schema') != SCHEMA:
        return None
    return validate(item.get('cell_size'), item.get('origin_x'), item.get('origin_y'), item.get('width'), item.get('height'), item.get('cells'))


def usable(rows: list[dict]) -> list[RoomMap]:
    """Database rows as maps, in the order given; rows that do not validate are ignored, never guessed."""
    maps = []
    for row in rows:
        built = validate(row.get('cell_size'), row.get('origin_x'), row.get('origin_y'), row.get('width'), row.get('height'), row.get('cells'))
        if built is not None:
            maps.append(built)
    return maps


def merge(maps: list[RoomMap], keep: int = KEEP) -> RoomMap | None:
    """The structural map of the newest `keep` visits (given newest first): one vote per visit per cell, covering
    every cell any of them observed. None without visits, when their cell sizes differ, or when nothing was observed."""
    newest = list(maps)[:max(0, keep)]
    if not newest:
        return None
    cell_size = newest[0].cell_size
    if any(abs(visit.cell_size - cell_size) > 1e-9 for visit in newest):
        return None
    votes: dict[tuple[int, int], list[int]] = {}
    for visit in newest:
        states = visit.states
        for iy in range(visit.height):
            for ix in range(visit.width):
                state = states[iy * visit.width + ix]
                if state == UNKNOWN:
                    continue
                tally = votes.setdefault((visit.min_ix + ix, visit.min_iy + iy), [0, 0])
                tally[0 if state == BLOCKED else 1] += 1
    if not votes:
        return None
    min_ix, min_iy = min(ix for ix, _ in votes), min(iy for _, iy in votes)
    width, height = max(ix for ix, _ in votes) - min_ix + 1, max(iy for _, iy in votes) - min_iy + 1
    if width > MAX_SIDE or height > MAX_SIDE or width * height > MAX_CELLS:
        return None
    states = [UNKNOWN] * (width * height)
    for (ix, iy), (blocked, free) in votes.items():
        states[(iy - min_iy) * width + (ix - min_ix)] = BLOCKED if blocked >= free else FREE
    return RoomMap(cell_size, _origin(min_ix, cell_size), _origin(min_iy, cell_size), width, height, encode(states))
