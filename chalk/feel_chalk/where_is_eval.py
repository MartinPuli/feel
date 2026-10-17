"""Chalk Evaluation for Where-is: does the vision model point at the right thing, and does it
say "not found" when the thing is absent?

Run from chalk/ as a module so Chalk ships the whole feel_chalk package:
    python -m feel_chalk.where_is_eval data/labels.jsonl --model openai/gpt-6.1-sol
    python -m feel_chalk.where_is_eval data/labels.jsonl --model openai/gpt-6-luna

Needs: chalk login, chalk environment <id>, Evaluations enabled, and CHALK_ROUTER_API_KEY /
CHALK_ENV_ID in chalk/.env (uploaded as Chalk secrets at deploy time). Validate the labels
first: python3 evals/validate_labels.py data/labels.jsonl

Each labels.jsonl row (see evals/labels.example.jsonl):
    {"image": "photos/hall-01.jpg", "question": "Where is the registration desk?",
     "box": [x_min, y_min, x_max, y_max] or null when the thing is not in the photo}
"""
from __future__ import annotations
import argparse
import base64
import json
import os
from pathlib import Path

import chalkcompute
from chalkcompute import Secret

from feel_chalk import gateway, where_is
from feel_chalk.config import settings

SECRETS = [Secret.from_local_env('CHALK_ROUTER_API_KEY'), Secret.from_local_env('CHALK_ENV_ID'),
           Secret.from_local_env('FEEL_CHALK_MODEL')]


@chalkcompute.function(secrets=SECRETS)
def where_is_task(question: str, image_b64: str) -> str:
    """One gateway call per row; the raw reply is returned so scorers see exactly what the phone would."""
    config = settings()
    try:
        return gateway.chat(config, where_is.request_body(config.model or os.environ['FEEL_CHALK_MODEL'], question, image_b64))
    except gateway.GatewayError as error:
        return f'GATEWAY ERROR: {error}'


# Scorer parameters bind to dataset columns by name, plus `output` (the task's reply).
@chalkcompute.function
def points_correctly(output: str, expected_box: str) -> float:
    """1 when the reply's box centre lands inside the labeled box, or when the thing is absent and
    the reply says not found. Malformed replies score 0."""
    expected = json.loads(expected_box)
    try:
        answer = where_is.parse(output)
    except where_is.AnswerError:
        return 0.0
    return 1.0 if where_is.points_at(answer, tuple(expected) if expected else None) else 0.0


@chalkcompute.function
def reply_is_well_formed(output: str) -> float:
    """1 when the reply obeys the JSON contract at all (found or not), 0 otherwise."""
    try:
        where_is.parse(output)
        return 1.0
    except where_is.AnswerError:
        return 0.0


@chalkcompute.function
def false_found(output: str, expected_box: str) -> float:
    """1 when the thing is absent but the model claimed to see it: the dangerous error for a blind user."""
    if json.loads(expected_box) is not None:
        return 0.0
    try:
        return 1.0 if where_is.parse(output).found else 0.0
    except where_is.AnswerError:
        return 0.0


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
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('labels', type=Path)
    parser.add_argument('--model', help='gateway model id, e.g. openai/gpt-6.1-sol (default: FEEL_CHALK_MODEL from .env)')
    args = parser.parse_args()
    if args.model:
        os.environ['FEEL_CHALK_MODEL'] = args.model
    model = settings().model or os.environ.get('FEEL_CHALK_MODEL') or 'unset'
    dataset = chalkcompute.DatasetClient().upload('feel-where-is', load_rows(args.labels))
    evaluation = chalkcompute.Evaluation.create(f'feel-where-is-{model.replace("/", "-")}', dataset=dataset, task=where_is_task,
                                                scorers=[points_correctly, reply_is_well_formed, false_found])
    run = evaluation.run(metadata={'model': model}).wait()
    print(run.status, 'model:', model, 'evaluation:', evaluation, 'run:', run)
