"""Ask Chalk what FEEL knows: the last confirmed find of an object, a venue's downloadable pack, or
what is remembered at a printed room tag.

python -m feel_chalk.context last-seen --user <user id> --object keys
python -m feel_chalk.context venue-pack --venue harvard-yard --output pack.json
python -m feel_chalk.context room-anchors --venue harvard-yard --tag feel-tag-01

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

from . import anchors, history
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
    token = transport(config['CHALK_API_HOST'] + '/v1/oauth/token',
                      {'client_id': config['CHALK_CLIENT_ID'], 'client_secret': config['CHALK_CLIENT_SECRET'],
                       'grant_type': 'client_credentials'}, {}, timeout).get('access_token')
    if not isinstance(token, str) or not token:
        raise ContextError('token exchange returned no access token')
    body = {'inputs': inputs, 'outputs': outputs}
    if query_name:
        body['query_name'] = query_name
    reply = transport(config['CHALK_API_HOST'] + '/v1/query', body,
                      {'Authorization': f'Bearer {token}', 'X-Chalk-Env-Id': config['CHALK_ENV_ID']}, timeout)
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


def room_anchors(venue_id: str, tag_id: str, *, transport=post) -> dict:
    """The spoken summary and the remembered targets (feel_chalk.anchors.Remembered) at one printed tag."""
    key = f'{venue_id.strip().lower()}:{tag_id.strip().lower()}'
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
