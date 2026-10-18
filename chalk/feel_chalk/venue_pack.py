"""Build a downloadable venue pack from reviewed venue entries.

python -m feel_chalk.venue_pack reviewed.json --days 7 --output pack.json

The payload JSON travels as a string next to its SHA-256, so the phone rejects a corrupted or
truncated download. Validation matches ios/Shared/FeelCore/Sources/FeelCore/VenuePack.swift.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
from urllib.parse import urlsplit

SCHEMA = 1
KINDS = ('place', 'restriction')


class VenuePackError(ValueError):
    pass


def _text(value, field: str, limit: int) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > limit:
        raise VenuePackError(f'{field} must be non-empty text of at most {limit} characters')
    return value.strip()


def _time(value, field: str) -> datetime:
    try:
        moment = datetime.fromisoformat(value)
    except (TypeError, ValueError):
        raise VenuePackError(f'{field} must be an ISO 8601 time') from None
    if moment.utcoffset() != timedelta(0):
        raise VenuePackError(f'{field} must be in UTC')
    return moment


def _optional_time(value, field: str) -> datetime | None:
    return None if value is None else _time(value, field)


def _stamp(moment: datetime | None) -> str | None:
    return None if moment is None else moment.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def _entry(raw, generated: datetime) -> dict:
    if not isinstance(raw, dict):
        raise VenuePackError('every entry must be an object')
    entry_id = _text(raw.get('id'), 'id', 64)
    where = f'entry {entry_id}'
    kind = raw.get('kind')
    if kind not in KINDS:
        raise VenuePackError(f'{where}: kind must be place or restriction')
    url = raw.get('source_url')
    parts = urlsplit(url) if isinstance(url, str) else None
    if parts is None or parts.scheme != 'https' or not parts.hostname:
        raise VenuePackError(f'{where}: source_url must be an HTTPS URL')
    retrieved = _time(raw.get('retrieved_at'), f'{where} retrieved_at')
    if retrieved > generated:
        raise VenuePackError(f'{where}: retrieved_at is after the pack was built')
    start = _optional_time(raw.get('effective_from'), f'{where} effective_from')
    end = _optional_time(raw.get('effective_until'), f'{where} effective_until')
    if start and end and start >= end:
        raise VenuePackError(f'{where}: effective_until must be after effective_from')
    if kind == 'restriction' and (start is None or not raw.get('applies_to')):
        raise VenuePackError(f'{where}: a restriction needs applies_to and effective_from')
    aliases = raw.get('aliases', [])
    if not isinstance(aliases, list):
        raise VenuePackError(f'{where}: aliases must be a list')
    return {'id': entry_id, 'kind': kind, 'name': _text(raw.get('name'), f'{where} name', 120),
            'aliases': [_text(alias, f'{where} alias', 120) for alias in aliases],
            'text': _text(raw.get('text'), f'{where} text', 500), 'source_url': url,
            'retrieved_at': _stamp(retrieved), 'effective_from': _stamp(start), 'effective_until': _stamp(end),
            'applies_to': raw.get('applies_to') if kind == 'restriction' else None}


def build(source: dict, generated: datetime, days: int) -> dict:
    if type(days) is not int or days < 1:
        raise VenuePackError('days must be a positive whole number')
    if not isinstance(source, dict) or not isinstance(source.get('entries'), list) or not source['entries']:
        raise VenuePackError('the source needs at least one entry')
    if not isinstance(generated, datetime) or generated.utcoffset() is None:
        raise VenuePackError('generated_at must be a timezone-aware datetime')
    # Compare original instants before formatting both timestamps to wire seconds.
    # Rounding the build clock first rejects a legitimate same-second retrieval.
    generated = generated.astimezone(timezone.utc)
    entries = [_entry(raw, generated) for raw in source['entries']]
    ids = [entry['id'] for entry in entries]
    if len(set(ids)) != len(ids):
        raise VenuePackError('entry ids must be unique')
    places = {entry['id'] for entry in entries if entry['kind'] == 'place'}
    if any(entry['kind'] == 'restriction' and entry['applies_to'] not in places for entry in entries):
        raise VenuePackError('every restriction must apply to a place in this pack')
    payload = json.dumps({'venue_id': _text(source.get('venue_id'), 'venue_id', 64),
                          'venue_name': _text(source.get('venue_name'), 'venue_name', 120),
                          'generated_at': _stamp(generated), 'expires_at': _stamp(generated + timedelta(days=days)),
                          'entries': entries}, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
    return {'schema': SCHEMA, 'sha256': hashlib.sha256(payload.encode('utf-8')).hexdigest(), 'payload': payload}


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Reviewed entries: venue_id, venue_name and entries')
    parser.add_argument('--days', type=int, required=True, help='Days until the phone stops trusting the pack')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        pack = build(json.loads(args.source.read_text(encoding='utf-8')), datetime.now(timezone.utc), args.days)
    except (OSError, ValueError) as error:
        print(f'Venue pack not built: {error}')
        return 2
    try:
        with args.output.open('x', encoding='utf-8') as output:
            output.write(json.dumps(pack, indent=2, ensure_ascii=False) + '\n')
    except OSError:
        print('Output path must be new and writable; nothing was written.')
        return 2
    print(f"Built {args.output}: sha256 {pack['sha256']}.")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
