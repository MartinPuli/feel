"""Minimal client for Chalk's OpenAI-compatible Model Gateway (standard library only)."""
from __future__ import annotations
import json
from typing import NamedTuple
import urllib.error
import urllib.request

from .config import Settings


class GatewayError(RuntimeError):
    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


class Completion(NamedTuple):
    content: str
    model: str | None
    usage: dict | None


def _request(settings: Settings, method: str, path: str, body: dict | None = None, timeout: float = 30) -> dict:
    headers = {'Accept': 'application/json'}
    if settings.router_api_key:
        headers['Authorization'] = f'Bearer {settings.router_api_key}'
    if settings.environment_id:
        headers['X-Chalk-Env-Id'] = settings.environment_id
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(settings.router_base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read() or b'{}')
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors='replace')[:300]
        raise GatewayError(f'HTTP {error.code} from {path}: {detail}', error.code) from None
    except urllib.error.URLError as error:
        raise GatewayError(f'cannot reach {settings.router_base}: {error.reason}') from None
    except TimeoutError:
        raise GatewayError(f'{path} timed out after {timeout} s') from None


def list_models(settings: Settings) -> list[str]:
    return [item.get('id', '') for item in _request(settings, 'GET', '/models').get('data', [])]


def completion(settings: Settings, body: dict, timeout: float = 60) -> Completion:
    """Send one chat completion; return the reply text with the model that answered and its token usage."""
    reply = _request(settings, 'POST', '/chat/completions', body, timeout)
    try:
        content = reply['choices'][0]['message']['content']
    except (KeyError, IndexError, TypeError):
        raise GatewayError(f'unexpected reply shape: {str(reply)[:300]}') from None
    usage = reply.get('usage')
    return Completion(content, reply.get('model'), usage if isinstance(usage, dict) else None)


def chat(settings: Settings, body: dict, timeout: float = 60) -> str:
    return completion(settings, body, timeout).content
