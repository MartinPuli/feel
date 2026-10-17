"""What FEEL says about where an object was last confirmed.

Pure functions shared by the Chalk resolvers in chalk/feel_context and their tests. No Chalk import
here, so the sentence and the choice of "latest find" are tested without a deployment.
"""
from __future__ import annotations
from dataclasses import dataclass
from datetime import datetime, timezone


@dataclass(frozen=True)
class Summary:
    last_place: str | None
    last_seen_at: datetime | None
    count: int


def normalize_object(name: str) -> str:
    """The object key the phone writes and the assistant asks for: lower case, single spaces."""
    return ' '.join(name.lower().split())


def summarize(finds: list[dict]) -> Summary:
    """Rows carry place, found_at (an aware datetime) and confidence. The latest confirmed find wins;
    rows without a usable place or time are ignored rather than guessed."""
    usable = [row for row in finds
              if isinstance(row.get('place'), str) and row['place'].strip()
              and isinstance(row.get('found_at'), datetime) and row['found_at'].tzinfo is not None]
    if not usable:
        return Summary(None, None, 0)
    latest = max(usable, key=lambda row: row['found_at'])
    return Summary(latest['place'].strip(), latest['found_at'].astimezone(timezone.utc), len(usable))


def ago(moment: datetime, now: datetime) -> str:
    seconds = (now.astimezone(timezone.utc) - moment.astimezone(timezone.utc)).total_seconds()
    if seconds < 90:
        return 'just now'
    minutes = round(seconds / 60)
    if minutes < 60:
        return f'{minutes} minutes ago'
    hours = round(seconds / 3600)
    if hours < 24:
        return f'{hours} hour{"s" if hours != 1 else ""} ago'
    days = round(seconds / 86400)
    return 'yesterday' if days == 1 else f'{days} days ago'


def spoken(object_name: str, summary: Summary, now: datetime) -> str:
    """One sentence the assistant can read out; it never claims the object is still there."""
    name = normalize_object(object_name) or 'that'
    if summary.last_place is None or summary.last_seen_at is None:
        return f'No confirmed find of {name} is on record.'
    count = f' ({summary.count} finds on record)' if summary.count > 1 else ''
    return f'{name.capitalize()}: last confirmed at the {summary.last_place}, {ago(summary.last_seen_at, now)}{count}.'
