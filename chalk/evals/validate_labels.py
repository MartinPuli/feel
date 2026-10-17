#!/usr/bin/env python3
"""Check a Where-is label file before uploading it to Chalk.

Usage: python3 evals/validate_labels.py data/labels.jsonl
Exit 0 and "N rows valid" when every row is usable; otherwise the problems, exit 1.

Each line: {"image": "photos/x.jpg", "question": "Where is the desk?", "box": [x0, y0, x1, y1] | null}
Boxes are fractions of the image (top-left origin). At least a third of the rows must
have "box": null, so the evaluation also measures correct "not found" answers.
"""
from __future__ import annotations
import json
from pathlib import Path
import sys


def validate(labels: Path) -> list[str]:
    problems: list[str] = []
    try:
        lines = [line for line in labels.read_text().splitlines() if line.strip()]
    except OSError as error:
        return [f'cannot read {labels}: {error}']
    if not lines:
        return ['no rows: the file is empty']
    absent = 0
    for number, line in enumerate(lines, start=1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as error:
            problems.append(f'row {number}: not JSON ({error})')
            continue
        if not isinstance(row, dict):
            problems.append(f'row {number}: must be a JSON object')
            continue
        image = row.get('image')
        if not isinstance(image, str) or not image:
            problems.append(f'row {number}: image must be a path')
        elif not (labels.parent / image).is_file():
            problems.append(f'row {number}: image not found: {image}')
        question = row.get('question')
        if not isinstance(question, str) or not question.strip():
            problems.append(f'row {number}: question must be non-empty text')
        if 'box' not in row:
            problems.append(f'row {number}: box is required (null when the thing is absent)')
            continue
        box = row['box']
        if box is None:
            absent += 1
            continue
        valid_box = (isinstance(box, list) and len(box) == 4
                     and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in box)
                     and 0 <= box[0] < box[2] <= 1 and 0 <= box[1] < box[3] <= 1)
        if not valid_box:
            problems.append(f'row {number}: box must be [x0, y0, x1, y1] inside 0..1 with positive size')
    if absent * 3 < len(lines):
        problems.append(f'only {absent} of {len(lines)} rows have the thing absent; at least a third must, to score "not found"')
    return problems


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    labels = Path(argv[1])
    problems = validate(labels)
    if problems:
        print('\n'.join(problems))
        return 1
    rows = sum(1 for line in labels.read_text().splitlines() if line.strip())
    print(f'{rows} rows valid')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
