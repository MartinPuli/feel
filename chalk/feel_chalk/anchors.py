"""What FEEL remembers at one printed room tag: targets confirmed earlier, in the tag's own frame.

Pure functions shared by the Chalk resolvers in chalk/feel_context (RoomMemory) and their tests, and
mirrored by FeelCore's RememberedTarget on the phone (protocol/room-memory-v1.json is the shared vector).
No Chalk import here.

The frame is the ARKit image anchor of the printed tag: x to the right along the tag, y out of the tag
into the room, z down along the tag, in metres. A position is the per-axis median of the label's last
KEEP sightings, so one bad confirmation moves nothing much. Spoken directions are for someone standing
at the tag with their back to it. Memory only shortcuts the question; it never says what is there now.
"""
from __future__ import annotations
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
import json
import math
import statistics

from . import history

KEEP = 20


@dataclass(frozen=True)
class Remembered:
    label: str
    x: float
    y: float
    z: float
    sightings: int
    last_seen_at: datetime


def normalize_label(name: str) -> str:
    """Same key as confirmed finds: lower case, single spaces."""
    return history.normalize_object(name)


def _finite(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def usable(rows: list[dict]) -> list[dict]:
    """Rows with a label, three finite coordinates and an aware time; anything else is ignored, never guessed."""
    kept = []
    for row in rows:
        label = normalize_label(row.get('label')) if isinstance(row.get('label'), str) else ''
        seen_at = row.get('seen_at')
        if not label or not all(_finite(row.get(axis)) for axis in 'xyz') \
                or not isinstance(seen_at, datetime) or seen_at.tzinfo is None:
            continue
        kept.append({'label': label, 'x': float(row['x']), 'y': float(row['y']), 'z': float(row['z']),
                     'seen_at': seen_at.astimezone(timezone.utc)})
    return kept


def remember(anchors: list[dict], keep: int = KEEP) -> list[Remembered]:
    """One target per label, sorted by label: the per-axis median of its newest `keep` sightings (rounded to
    millimetres), how many sightings there are in all, and the newest time."""
    by_label: dict[str, list[dict]] = {}
    for row in usable(anchors):
        by_label.setdefault(row['label'], []).append(row)
    result = []
    for label in sorted(by_label):
        rows = sorted(by_label[label], key=lambda r: r['seen_at'], reverse=True)
        newest = rows[:keep]
        x, y, z = (round(statistics.median(r[axis] for r in newest), 3) for axis in 'xyz')
        result.append(Remembered(label, x, y, z, len(rows), rows[0]['seen_at']))
    return result


def direction(x: float, y: float) -> str:
    """Where a tag-frame point is for someone standing at the tag with their back to it: +y is ahead, +x is left."""
    bearing = math.degrees(math.atan2(-x, y))   # 0 ahead, positive to the right
    side = 'right' if bearing > 0 else 'left'
    size = abs(bearing)
    if size <= 22.5:
        return 'ahead'
    if size <= 67.5:
        return f'ahead-{side}'
    if size <= 112.5:
        return f'to the {side}'
    if size <= 157.5:
        return f'behind-{side}'
    return 'behind'


def distance_text(metres: float) -> str:
    if metres < 0.75:
        return 'at the tag'
    whole = max(1, round(metres))
    return f'about {whole} meter{"s" if whole != 1 else ""}'


def _times(count: int) -> str:
    return {1: 'once', 2: 'twice'}.get(count, f'{count} times')


def spoken(targets: list[Remembered], now: datetime) -> str:
    """One sentence the assistant can read out. Past sightings only; it never claims a target is still there."""
    if not targets:
        return 'Nothing is remembered at this tag yet.'
    parts = []
    for target in targets:
        metres = math.hypot(target.x, target.y)
        where = distance_text(metres) if metres < 0.75 else f'{distance_text(metres)} {direction(target.x, target.y)}'
        parts.append(f'{target.label} {where}, seen {_times(target.sightings)}, last {history.ago(target.last_seen_at, now)}')
    return 'Remembered here: ' + '; '.join(parts) + '.'


def to_json(targets: list[Remembered]) -> str:
    return json.dumps([dict(asdict(t), last_seen_at=t.last_seen_at.isoformat()) for t in targets], ensure_ascii=False)


def from_json(text: str) -> list[Remembered]:
    """The list back from `to_json`; anything malformed reads as nothing remembered."""
    try:
        items = json.loads(text)
        return [Remembered(str(i['label']), float(i['x']), float(i['y']), float(i['z']), int(i['sightings']),
                           datetime.fromisoformat(i['last_seen_at'])) for i in items]
    except (TypeError, ValueError, KeyError, AttributeError):
        return []
