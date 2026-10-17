"""Chalk settings from environment variables, optionally loaded from chalk/.env."""
from __future__ import annotations
from dataclasses import dataclass
import os
from pathlib import Path

ENV_FILE = Path(__file__).resolve().parents[1] / '.env'
DEFAULT_API_HOST = 'https://api.chalk.ai'


def load_env_file(path: Path = ENV_FILE) -> None:
    """Read KEY=VALUE lines without overriding variables already set."""
    if not path.is_file():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, value = line.split('=', 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


@dataclass(frozen=True)
class Settings:
    api_host: str
    router_api_key: str | None
    environment_id: str | None
    model: str | None

    @property
    def router_base(self) -> str:
        return self.api_host.rstrip('/') + '/v1/router'

    def missing(self) -> list[str]:
        names = {'CHALK_ROUTER_API_KEY': self.router_api_key, 'CHALK_ENV_ID': self.environment_id,
                 'FEEL_CHALK_MODEL': self.model}
        return [name for name, value in names.items() if not value]


def settings() -> Settings:
    load_env_file()
    return Settings(
        api_host=os.environ.get('CHALK_API_HOST', DEFAULT_API_HOST),
        router_api_key=os.environ.get('CHALK_ROUTER_API_KEY') or None,
        environment_id=os.environ.get('CHALK_ENV_ID') or None,
        model=os.environ.get('FEEL_CHALK_MODEL') or None,
    )
