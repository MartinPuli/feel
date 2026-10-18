"""Mint the short-lived Chalk query access the phone ships with, so the Lantern app can read the shared memory
(named queries last_seen, room_structure, room_anchors) without ever holding the client secret.

python -m feel_chalk.query_token [--env chalk/.env] >> ios/Config/Supabase.local.xcconfig

Exchanges CHALK_CLIENT_ID and CHALK_CLIENT_SECRET for an access token exactly as context.py does, takes the
environment's engine host from the grant, and prints the three build-config lines the app reads
(FEEL_CHALK_QUERY_ENGINE, FEEL_CHALK_QUERY_TOKEN, FEEL_CHALK_CLIENT_ID). The token goes to stdout only, so it
travels through the pipe into the git-ignored file and nowhere else; what the terminal shows is when it expires.
ios/scripts/supabase_config.sh runs this when the env file carries the two credentials. The token lives as long as
the grant says (expires_in), so rerun before the demo build; an expired token makes every query fail with
"access" on the phone, which then keeps its own stores. Standard library only.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import sys

from .config import load_env_file
from . import context

NAMES = ('FEEL_CHALK_QUERY_ENGINE', 'FEEL_CHALK_QUERY_TOKEN', 'FEEL_CHALK_CLIENT_ID')


def access(*, transport=None, timeout: float = 20) -> dict:
    """engine, token, environment, client_id and expires_in (seconds, or None when the grant does not say)."""
    transport = transport or context.post
    config = context.credentials()
    grant = transport(config['CHALK_API_HOST'] + '/v1/oauth/token',
                      {'client_id': config['CHALK_CLIENT_ID'], 'client_secret': config['CHALK_CLIENT_SECRET'],
                       'grant_type': 'client_credentials'}, {}, timeout)
    token = grant.get('access_token')
    if not isinstance(token, str) or not token or any(c.isspace() for c in token):
        raise context.ContextError('token exchange returned no access token')
    engines = grant.get('engines') if isinstance(grant.get('engines'), dict) else {}
    engine = engines.get(config['CHALK_ENV_ID'])
    if not isinstance(engine, str) or not engine.startswith('https://') or len(engine) <= len('https://'):
        raise context.ContextError(f"no query engine for environment {config['CHALK_ENV_ID']} in the token grant")
    expires_in = grant.get('expires_in')
    if isinstance(expires_in, bool) or not isinstance(expires_in, (int, float)) or expires_in <= 0:
        expires_in = None
    return {'engine': engine.rstrip('/'), 'token': token, 'environment': config['CHALK_ENV_ID'],
            'client_id': config['CHALK_CLIENT_ID'], 'expires_in': expires_in}


def xcconfig_lines(granted: dict) -> list[str]:
    """The lines ios/Config/Supabase.local.xcconfig takes; // starts a comment there, so the scheme is split with $()."""
    host = granted['engine'][len('https://'):]
    return [f'FEEL_CHALK_QUERY_ENGINE = https:/$()/{host}',
            f"FEEL_CHALK_QUERY_TOKEN = {granted['token']}",
            f"FEEL_CHALK_CLIENT_ID = {granted['client_id']}"]


def lifetime(expires_in) -> str:
    if expires_in is None:
        return 'The grant did not say when the token expires.'
    hours = expires_in / 3600
    return f'The token expires in about {hours:.1f} hours; rerun before the demo build.' if hours >= 1 \
        else f'The token expires in about {round(expires_in / 60)} minutes; rerun before the demo build.'


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--env', type=Path, default=None, help='env file with CHALK_ENV_ID, CHALK_CLIENT_ID and CHALK_CLIENT_SECRET (default chalk/.env)')
    args = parser.parse_args(argv)
    if args.env is not None:
        load_env_file(args.env)
    try:
        granted = access()
    except context.ContextError as error:
        print(f'Chalk query access unavailable: {error}', file=sys.stderr)
        return 1
    for line in xcconfig_lines(granted):
        print(line)
    print(f"Chalk query access for environment {granted['environment']} at {granted['engine']}. {lifetime(granted['expires_in'])}", file=sys.stderr)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
