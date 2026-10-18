"""Ask Chalk what FEEL knows: the last confirmed find of an object, a venue's downloadable pack, what
is remembered at a printed room tag, or the structure of the room behind it.

python -m feel_chalk.context last-seen --user <user id> --object keys
python -m feel_chalk.context venue-pack --venue harvard-yard --output pack.json
python -m feel_chalk.context room-anchors --venue harvard-yard --tag feel-tag-01
python -m feel_chalk.context room-structure --venue harvard-yard --tag feel-tag-01 --output structure.json

All run Chalk online queries over the features in chalk/feel_context, authenticated with the
service token in chalk/.env (CHALK_CLIENT_ID and CHALK_CLIENT_SECRET, scoped to CHALK_ENV_ID).
Standard library only, like gateway.py. No photo, audio or location ever travels this path.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import urllib.error
import urllib.request

from . import anchors, history, room_map
from .config import DEFAULT_API_HOST, load_env_file

NAMES = ('CHALK_ENV_ID', 'CHALK_CLIENT_ID', 'CHALK_CLIENT_SECRET')


class ContextError(RuntimeError):
    pass


def credentials() -> dict:
    load_env_file()
    values = {name: os.environ.get(name) or None for name in NAMES}
    missing = [name for name, value in values.items() if not value]
    if missing:
        raise ContextError('missing in chalk/.env: ' + ', '.join(missing))
    return dict(values, CHALK_API_HOST=os.environ.get('CHALK_API_HOST', DEFAULT_API_HOST).rstrip('/'))


def post(url: str, body: dict, headers: dict, timeout: float) -> dict:
    request = urllib.request.Request(url, data=json.dumps(body).encode(), method='POST',
                                     headers=dict(headers, **{'Content-Type': 'application/json', 'Accept': 'application/json'}))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read() or b'{}')
    except urllib.error.HTTPError as error:
        raise ContextError(f'HTTP {error.code} from {url.rsplit("/", 1)[-1]}: {error.read().decode(errors="replace")[:300]}') from None
    except urllib.error.URLError as error:
        raise ContextError(f'cannot reach {url}: {error.reason}') from None
    except TimeoutError:
        raise ContextError(f'{url} timed out after {timeout} s') from None


def query(inputs: dict, outputs: list[str], *, query_name: str | None = None, timeout: float = 20, transport=post) -> dict:
    """One online query. Returns {feature: value}; any per-feature error or missing output raises."""
    config = credentials()
    grant = transport(config['CHALK_API_HOST'] + '/v1/oauth/token',
                      {'client_id': config['CHALK_CLIENT_ID'], 'client_secret': config['CHALK_CLIENT_SECRET'],
                       'grant_type': 'client_credentials'}, {}, timeout)
    token = grant.get('access_token')
    if not isinstance(token, str) or not token:
        raise ContextError('token exchange returned no access token')
    # Online queries are answered by the environment's own engine, which the token grant names;
    # api.chalk.ai only answers its version record to a query.
    engines = grant.get('engines') if isinstance(grant.get('engines'), dict) else {}
    engine = engines.get(config['CHALK_ENV_ID'])
    if not isinstance(engine, str) or not engine.startswith('https://'):
        raise ContextError(f"no query engine for environment {config['CHALK_ENV_ID']} in the token grant")
    body = {'inputs': inputs, 'outputs': outputs}
    if query_name:
        body['query_name'] = query_name
    reply = transport(engine.rstrip('/') + '/v1/query/online', body,
                      {'Authorization': f'Bearer {token}', 'X-Chalk-Env-Id': config['CHALK_ENV_ID'],
                       'X-Chalk-Client-Id': config['CHALK_CLIENT_ID'], 'X-Chalk-Deployment-Type': 'engine'}, timeout)
    errors = reply.get('errors') or []
    if errors:
        first = errors[0] if isinstance(errors[0], dict) else {}
        raise ContextError(f"query failed: {first.get('code', 'error')} {str(first.get('message', ''))[:200]}".rstrip())
    values = {}
    for item in reply.get('data') or []:
        if not isinstance(item, dict) or 'field' not in item:
            continue
        if item.get('error'):
            message = item['error'].get('message') if isinstance(item['error'], dict) else item['error']
            raise ContextError(f"{item['field']}: {str(message)[:200]}")
        values[item['field']] = item.get('value')
    missing = [name for name in outputs if name not in values]
    if missing:
        raise ContextError('no value for ' + ', '.join(missing))
    return values


def last_seen(user_id: str, object_name: str, *, transport=post) -> str:
    key = f'{user_id.strip()}:{history.normalize_object(object_name)}'
    values = query({'object_history.id': key}, ['object_history.spoken'], query_name='last_seen', transport=transport)
    spoken = values['object_history.spoken']
    if not isinstance(spoken, str) or not spoken:
        raise ContextError('object_history.spoken is empty')
    return spoken


def venue_pack(venue_id: str, *, transport=post) -> dict:
    """The pack exactly as the phone will download it; its hash is checked here as the phone checks it."""
    values = query({'venue.id': venue_id}, ['venue.pack'], query_name='venue_pack', transport=transport)
    try:
        pack = json.loads(values['venue.pack'])
    except (TypeError, ValueError):
        raise ContextError('venue.pack is not JSON') from None
    if not isinstance(pack, dict) or set(pack) != {'schema', 'sha256', 'payload'} or not isinstance(pack['payload'], str):
        raise ContextError('venue.pack has the wrong shape')
    if hashlib.sha256(pack['payload'].encode('utf-8')).hexdigest() != pack['sha256']:
        raise ContextError('venue.pack hash does not match its payload')
    return pack


def room_key(venue_id: str, tag_id: str) -> str:
    """RoomMemory.id: the venue slug and the tag id as printed, '<venue_id>:<tag_id>'."""
    return f'{venue_id.strip().lower()}:{tag_id.strip().lower()}'


def room_anchors(venue_id: str, tag_id: str, *, transport=post) -> dict:
    """The spoken summary and the remembered targets (feel_chalk.anchors.Remembered) at one printed tag."""
    key = room_key(venue_id, tag_id)
    values = query({'room_memory.id': key}, ['room_memory.spoken', 'room_memory.targets'], query_name='room_anchors', transport=transport)
    spoken, raw = values['room_memory.spoken'], values['room_memory.targets']
    if not isinstance(spoken, str) or not spoken or not isinstance(raw, str) or not raw:
        raise ContextError('room_memory.spoken or room_memory.targets is empty')
    try:
        items = json.loads(raw)
    except ValueError:
        raise ContextError('room_memory.targets is not JSON') from None
    targets = anchors.from_json(raw)
    if not isinstance(items, list) or len(targets) != len(items):
        raise ContextError('room_memory.targets has the wrong shape')
    return {'spoken': spoken, 'targets': targets}


def room_structure(venue_id: str, tag_id: str, *, transport=post) -> dict:
    """The structure of the room behind one printed tag as Chalk merged it from shared visits (feel_chalk.room_map.RoomMap),
    with the number of visits that voted; the map is None while nobody has shared a visit."""
    values = query({'room_memory.id': room_key(venue_id, tag_id)}, ['room_memory.structure', 'room_memory.structure_visits'],
                   query_name='room_structure', transport=transport)
    raw, visits = values['room_memory.structure'], values['room_memory.structure_visits']
    if isinstance(visits, bool) or not isinstance(visits, int) or visits < 0:
        raise ContextError('room_memory.structure_visits is not a count')
    if raw is None:
        return {'map': None, 'visits': visits}
    built = room_map.from_json(raw) if isinstance(raw, str) else None
    if built is None:
        raise ContextError('room_memory.structure is not a room map')
    return {'map': built, 'visits': visits}


def room_structure_summary(venue_id: str, tag_id: str, built: room_map.RoomMap, visits: int) -> str:
    free = built.observed - built.blocked
    return (f'Room structure at {room_key(venue_id, tag_id)}: {built.width} x {built.height} cells of {built.cell_size:g} m, '
            f'{built.observed} remembered ({free} free, {built.blocked} blocked), merged from {visits} visit{"s" if visits != 1 else ""}.')


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    seen = commands.add_parser('last-seen', help='where an object was last confirmed')
    seen.add_argument('--user', required=True)
    seen.add_argument('--object', required=True)
    pack = commands.add_parser('venue-pack', help='download a venue pack built by Chalk')
    pack.add_argument('--venue', required=True)
    pack.add_argument('--output', type=Path, required=True)
    room = commands.add_parser('room-anchors', help='what is remembered at a printed room tag')
    room.add_argument('--venue', required=True)
    room.add_argument('--tag', required=True)
    structure = commands.add_parser('room-structure', help='the floor-plan map remembered behind a printed room tag, merged from shared visits')
    structure.add_argument('--venue', required=True)
    structure.add_argument('--tag', required=True)
    structure.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == 'last-seen':
            print(last_seen(args.user, args.object))
            return 0
        if args.command == 'room-anchors':
            result = room_anchors(args.venue, args.tag)
            print(result['spoken'])
            for target in result['targets']:
                print(f"  {target.label}: x {target.x:+.2f} y {target.y:+.2f} z {target.z:+.2f} m in the tag frame, "
                      f"{target.sightings} sighting{'s' if target.sightings != 1 else ''}, last {target.last_seen_at.isoformat()}")
            return 0
        if args.command == 'room-structure':
            result = room_structure(args.venue, args.tag)
            if result['map'] is None:
                print(f'Nothing is remembered about the structure of the room at {room_key(args.venue, args.tag)} yet.')
                return 0
            try:
                with args.output.open('x', encoding='utf-8') as output:
                    output.write(result['map'].to_json() + '\n')
            except OSError:
                print('Output path must be new and writable; nothing was written.')
                return 2
            print(room_structure_summary(args.venue, args.tag, result['map'], result['visits']) + f' Wrote {args.output}.')
            return 0
        built = venue_pack(args.venue)
        try:
            with args.output.open('x', encoding='utf-8') as output:
                output.write(json.dumps(built, indent=2, ensure_ascii=False) + '\n')
        except OSError:
            print('Output path must be new and writable; nothing was written.')
            return 2
        print(f"Wrote {args.output}: sha256 {built['sha256']}.")
        return 0
    except ContextError as error:
        print(f'Chalk context unavailable: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
