"""Journeys: every walk from a printed tag toward a remembered target, and what it tells the room map.

Pure functions shared by the Chalk resolvers in chalk/feel_context (Journey, RoomMemory.world_map) and the local
evaluation (feel_chalk/journey_eval.py); protocol/journey-v1.json is the vector the phone must reproduce. No Chalk
import here.

A journey is one trip in the tag's levelled frame (x right along the tag, y out into the room, metres): the steps the
phone recorded (t seconds after started_at, x, y, heading_deg clockwise from +y), the blocked cell centres it saw,
how long each cue took, and whether it arrived. Scores per journey: arrived; the smallest distance from any step to
any obstacle seen on that trip (None without obstacles); path efficiency, the straight line from the first step to
the last over the distance walked, 0 when the journey did not arrive; and the 95th percentile of the cue latencies
(the nearest-rank percentile the Where-is report uses). A journey counts one collision when its clearance is under
COLLISION_M. Ranking is collisions first, then efficiency, then latency.

The world map is the room's merged structure with what journeys of the last WINDOW_DAYS days add: a cell a step stood
in is free, a cell an obstacle was seen in is blocked; an obstacle beats a step, and both beat the structure's vote.
Older journeys drop out of the map. Nothing in it is a claim about the room now.
"""
from __future__ import annotations
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
import json
import math

from . import room_map
from .path import cell_of

WINDOW_DAYS = 60
COLLISION_M = 0.3
DEFAULT_CELL = 0.1       # metres, when the room has no merged structure to take the cell size from
MAX_STEPS = 10_000
REACH = room_map.REACH


@dataclass(frozen=True)
class Step:
    t: float
    x: float
    y: float
    heading_deg: float


@dataclass(frozen=True)
class Journey:
    venue_id: str
    tag_id: str
    user_id: str
    session_id: str
    started_at: datetime
    target_label: str
    steps: tuple[Step, ...]
    obstacles: tuple[tuple[float, float], ...]
    cue_latency_ms: tuple[float, ...]
    arrived_at: datetime | None
    arrival_distance_m: float

    def to_row(self) -> dict:
        """The journey as a row of the journeys table (the export format), times in ISO 8601 UTC."""
        row = asdict(self)
        row['steps'] = [asdict(step) for step in self.steps]
        row['obstacles'] = [{'x': x, 'y': y} for x, y in self.obstacles]
        row['cue_latency_ms'] = list(self.cue_latency_ms)
        row['started_at'] = self.started_at.isoformat()
        row['arrived_at'] = self.arrived_at.isoformat() if self.arrived_at else None
        return row


@dataclass(frozen=True)
class Scores:
    arrived: bool
    min_clearance_m: float | None
    collisions: int
    path_efficiency: float
    cue_latency_p95_ms: float | None


def _real(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _time(value) -> datetime | None:
    """An aware UTC time from a datetime or an ISO 8601 string; naive values are read as UTC."""
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace('Z', '+00:00'))
        except ValueError:
            return None
    if not isinstance(value, datetime):
        return None
    return (value if value.tzinfo else value.replace(tzinfo=timezone.utc)).astimezone(timezone.utc)


def _list(value) -> list | None:
    """A JSON array from a list or its text (the jsonb column read as text)."""
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except ValueError:
            return None
    return value if isinstance(value, list) else None


def _text(value) -> str:
    return value.strip().lower() if isinstance(value, str) else ''


def from_row(row: dict) -> Journey | None:
    """A journey from a table row or an export row, or None when any part of it is not what the phone could record.
    Steps, obstacles and latencies may be lists or JSON text; times may be datetimes or ISO strings."""
    venue_id, tag_id, user_id, session_id = (_text(row.get(k)) for k in ('venue_id', 'tag_id', 'user_id', 'session_id'))
    target_label = ' '.join(_text(row.get('target_label')).split())
    started_at, arrived_at = _time(row.get('started_at')), _time(row.get('arrived_at'))
    steps, obstacles, latencies = _list(row.get('steps')), _list(row.get('obstacles')), _list(row.get('cue_latency_ms'))
    distance = row.get('arrival_distance_m')
    if not (venue_id and tag_id and user_id and session_id and target_label and started_at) \
            or (row.get('arrived_at') is not None and arrived_at is None) or (arrived_at and arrived_at < started_at) \
            or steps is None or obstacles is None or latencies is None or len(steps) > MAX_STEPS \
            or not _real(distance) or distance < 0:
        return None
    built_steps = []
    for step in steps:
        if not isinstance(step, dict) or not all(_real(step.get(k)) for k in ('t', 'x', 'y', 'heading_deg')) \
                or step['t'] < 0 or abs(step['x']) > REACH or abs(step['y']) > REACH:
            return None
        built_steps.append(Step(float(step['t']), float(step['x']), float(step['y']), float(step['heading_deg'])))
    built_obstacles = []
    for point in obstacles:
        if not isinstance(point, dict) or not (_real(point.get('x')) and _real(point.get('y'))) \
                or abs(point['x']) > REACH or abs(point['y']) > REACH:
            return None
        built_obstacles.append((float(point['x']), float(point['y'])))
    if not all(_real(value) and value >= 0 for value in latencies):
        return None
    return Journey(venue_id, tag_id, user_id, session_id, started_at, target_label, tuple(built_steps), tuple(built_obstacles),
                   tuple(float(value) for value in latencies), arrived_at, float(distance))


def usable(rows: list[dict]) -> list[Journey]:
    """Rows as journeys, in the order given; rows that do not validate are ignored, never guessed."""
    return [journey for journey in (from_row(row) for row in rows) if journey is not None]


def within_days(journeys: list[Journey], now: datetime, days: int = WINDOW_DAYS) -> list[Journey]:
    """The journeys that started within the last `days` days of `now` (and not after it): the room map's window."""
    now = _time(now)
    oldest = now - timedelta(days=days)
    return [journey for journey in journeys if oldest <= journey.started_at <= now]


def p95(values) -> float | None:
    """Nearest-rank 95th percentile, as the Where-is report computes latency; None without values."""
    ordered = sorted(values)
    return ordered[math.ceil(0.95 * len(ordered)) - 1] if ordered else None


def walked_m(journey: Journey) -> float:
    return sum(math.hypot(b.x - a.x, b.y - a.y) for a, b in zip(journey.steps, journey.steps[1:]))


def min_clearance_m(journey: Journey) -> float | None:
    if not journey.steps or not journey.obstacles:
        return None
    return round(min(math.hypot(step.x - x, step.y - y) for step in journey.steps for x, y in journey.obstacles), 3)


def path_efficiency(journey: Journey) -> float:
    """Straight-line distance between the first and last step over the distance walked; 0 when the journey did not
    arrive or did not move."""
    walked = walked_m(journey)
    if journey.arrived_at is None or walked <= 0:
        return 0.0
    first, last = journey.steps[0], journey.steps[-1]
    return round(min(1.0, math.hypot(last.x - first.x, last.y - first.y) / walked), 4)


def score(journey: Journey) -> Scores:
    clearance = min_clearance_m(journey)
    return Scores(arrived=journey.arrived_at is not None, min_clearance_m=clearance,
                  collisions=1 if clearance is not None and clearance < COLLISION_M else 0,
                  path_efficiency=path_efficiency(journey), cue_latency_p95_ms=p95(journey.cue_latency_ms))


def rank_key(scores: Scores) -> tuple:
    return (scores.collisions, -scores.path_efficiency, math.inf if scores.cue_latency_p95_ms is None else scores.cue_latency_p95_ms)


def rank(journeys: list[Journey]) -> list[tuple[Journey, Scores]]:
    """Journeys best first: fewest collisions, then the highest efficiency, then the lowest cue latency; ties keep
    the order given."""
    scored = [(journey, score(journey)) for journey in journeys]
    return sorted(scored, key=lambda pair: rank_key(pair[1]))


def world_map(structure: room_map.RoomMap | None, journeys: list[Journey], now: datetime,
              cell_size: float = DEFAULT_CELL) -> room_map.RoomMap | None:
    """The merged structure plus the last WINDOW_DAYS days of journeys: cells steps stood in are free, cells obstacles
    were seen in are blocked (an obstacle beats a step, both beat the structure). None when there is nothing at all."""
    recent = within_days(journeys, now)
    cell = structure.cell_size if structure else cell_size
    cells: dict[tuple[int, int], str] = {}
    if structure:
        for iy in range(structure.height):
            for ix in range(structure.width):
                state = structure.states[iy * structure.width + ix]
                if state != room_map.UNKNOWN:
                    cells[(structure.min_ix + ix, structure.min_iy + iy)] = state
    for journey in recent:
        for step in journey.steps:
            cells[cell_of(step.x, step.y, cell)] = room_map.FREE
    for journey in recent:
        for x, y in journey.obstacles:
            cells[cell_of(x, y, cell)] = room_map.BLOCKED
    if not cells:
        return None
    min_ix, min_iy = min(ix for ix, _ in cells), min(iy for _, iy in cells)
    width, height = max(ix for ix, _ in cells) - min_ix + 1, max(iy for _, iy in cells) - min_iy + 1
    if width > room_map.MAX_SIDE or height > room_map.MAX_SIDE or width * height > room_map.MAX_CELLS:
        return None
    states = [room_map.UNKNOWN] * (width * height)
    for (ix, iy), state in cells.items():
        states[(iy - min_iy) * width + (ix - min_ix)] = state
    return room_map.RoomMap(cell, round(min_ix * cell, 9), round(min_iy * cell, 9), width, height, room_map.encode(states))
