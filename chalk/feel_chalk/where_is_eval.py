"""Chalk Evaluation for Where-is. NOT WIRED YET: needs labeled venue photos.

Run from chalk/ as a module so Chalk ships the whole feel_chalk package:
    python -m feel_chalk.where_is_eval data/labels.jsonl

Each labels.jsonl row (see evals/labels.example.jsonl):
    {"image": "photos/hall-01.jpg", "question": "Where is the registration desk?",
     "box": [x_min, y_min, x_max, y_max] or null when the thing is not in the photo}
"""
from __future__ import annotations
import base64
import json
import os
from pathlib import Path
import sys

import chalkcompute
from chalkcompute import Secret

from feel_chalk import gateway, where_is
from feel_chalk.config import settings


@chalkcompute.function(secrets=[Secret.from_local_env('CHALK_ROUTER_API_KEY')])
def where_is_task(question: str, image_b64: str) -> str:
    """Ask the gateway once; return the raw reply so the scorer sees exactly what the phone would."""
    config = settings()
    return gateway.chat(config, where_is.request_body(config.model or os.environ['FEEL_CHALK_MODEL'], question, image_b64))


@chalkcompute.function
def points_correctly(output: str, expected_box: str) -> float:
    """1 when the reply points inside the labeled box, or correctly says not found. Bad replies score 0."""
    expected = json.loads(expected_box)
    try:
        answer = where_is.parse(output)
    except where_is.AnswerError:
        return 0.0
    return 1.0 if where_is.points_at(answer, tuple(expected) if expected else None) else 0.0


def load_rows(labels: Path) -> list[dict]:
    rows = []
    for line in labels.read_text().splitlines():
        if not line.strip():
            continue
        item = json.loads(line)
        image = (labels.parent / item['image']).read_bytes()
        rows.append({'question': item['question'], 'image_b64': base64.b64encode(image).decode(),
                     'expected_box': json.dumps(item['box'])})
    if not rows:
        raise SystemExit('No labeled rows; an empty evaluation cannot pass.')
    return rows


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    # TODO before the first run: confirm the environment has Evaluations enabled, that the
    # scorer signature matches Chalk's custom-scorer contract (docs/evaluations/scorers), and
    # that FEEL_CHALK_MODEL / CHALK_ENV_ID reach the remote task (as secrets or env).
    dataset = chalkcompute.DatasetClient().upload('feel-where-is', load_rows(Path(sys.argv[1])))
    evaluation = chalkcompute.Evaluation.create('feel-where-is', dataset=dataset, task=where_is_task,
                                                scorers=[points_correctly])
    run = evaluation.run(metadata={'model': settings().model}).wait()
    print(run.status)
