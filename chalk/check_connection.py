#!/usr/bin/env python3
"""Check that this machine can reach and use Chalk for FEEL Where-is.

Exit 0 when every check passes, 1 on a failure, 2 when a check is blocked on
setup (missing key, CLI login or package). Sends no photos.
"""
from __future__ import annotations
import argparse
import dataclasses
import os
from pathlib import Path
import shutil
import subprocess
import sys

from feel_chalk import gateway
from feel_chalk.config import settings

results: list[tuple[str, str, str]] = []


def record(status: str, name: str, detail: str) -> None:
    results.append((status, name, detail))
    print(f'{status:8} {name}: {detail}', flush=True)


def check_gateway(chat: bool) -> None:
    config = settings()
    anonymous = dataclasses.replace(config, router_api_key=None, environment_id=None)
    try:
        gateway.list_models(anonymous)
        record('PASS', 'reach gateway', f'{config.router_base} answered')
    except gateway.GatewayError as error:
        if error.status is None:
            record('FAIL', 'reach gateway', str(error))
            return
        record('PASS', 'reach gateway', f'{config.router_base} answered (HTTP {error.status} without a key, as expected)')
    missing = config.missing()
    if missing:
        record('BLOCKED', 'gateway settings', 'set ' + ', '.join(missing) + ' in chalk/.env (see .env.example)')
        return
    try:
        models = gateway.list_models(config)
    except gateway.GatewayError as error:
        record('FAIL', 'gateway key', str(error))
        return
    record('PASS', 'gateway key', f'{len(models)} model(s) listed for this key')
    # Listing a model verifies access, not inference. Only --chat may generate tokens.
    if config.model in models:
        record('PASS', 'model', f'{config.model} is listed')
    else:
        sample = ', '.join(models[:8]) or 'none'
        record('INFO' if chat else 'BLOCKED', 'model',
               f'{config.model} is not in the listing (listed: {sample}); '
               + ('checking with the requested text call' if chat else 'use --chat to explicitly test inference'))
    if chat:
        body = {'model': config.model, 'max_tokens': 64,
                'messages': [{'role': 'user', 'content': 'Reply with the single word OK.'}]}
        try:
            reply = gateway.chat(config, body)
            record('PASS', 'text request', f'{config.model} replied {reply.strip()[:40]!r}')
        except gateway.GatewayError as error:
            record('FAIL', 'text request', str(error))


def check_evaluations() -> None:
    try:
        import chalkcompute  # noqa: F401
        record('PASS', 'chalkcompute', 'package installed')
    except ImportError:
        record('BLOCKED', 'chalkcompute', 'run: python -m pip install -r chalk/requirements.txt')
    cli = shutil.which('chalk')
    default_cli = Path.home() / '.chalk' / 'bin' / 'chalk'
    if not cli and default_cli.is_file() and os.access(default_cli, os.X_OK):
        cli = str(default_cli)
    if not cli:
        record('BLOCKED', 'chalk CLI', 'install it, then run chalk login (see chalk/README.md)')
        return
    try:
        user = subprocess.run([cli, 'user'], capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        record('FAIL', 'chalk login', 'chalk user timed out')
        return
    if user.returncode == 0:
        record('PASS', 'chalk login', (user.stdout.strip().splitlines() or ['logged in'])[0][:80])
    else:
        record('BLOCKED', 'chalk login', 'run chalk login, then chalk environment <environment-id>')


def main() -> int:
    results.clear()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chat', action='store_true', help='also send one short text request (uses tokens)')
    args = parser.parse_args()
    check_gateway(args.chat)
    check_evaluations()
    statuses = {status for status, _, _ in results}
    return 1 if 'FAIL' in statuses else 2 if 'BLOCKED' in statuses else 0


if __name__ == '__main__':
    sys.exit(main())
