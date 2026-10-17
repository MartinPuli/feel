"""Where-is evaluation rows: the task's JSON record and the report summary with explicit denominators."""
from __future__ import annotations
import json
import math

SCORES = ('points_correctly', 'reply_is_well_formed', 'false_found')
STATUSES = ('ok', 'late', 'error')
USAGE_FIELDS = ('prompt_tokens', 'completion_tokens', 'total_tokens')


def read_output(output) -> dict | None:
    """The task's JSON record, or None when the output is not one."""
    if not isinstance(output, str):
        return None
    try:
        record = json.loads(output)
    except ValueError:
        return None
    return record if isinstance(record, dict) and record.get('status') in STATUSES else None


def usable_reply(output) -> str | None:
    """The model's reply only when it arrived within the deadline; late or failed requests have none."""
    record = read_output(output)
    reply = record.get('reply') if record and record['status'] == 'ok' else None
    return reply if isinstance(reply, str) else None


def _number(value) -> float | None:
    return float(value) if type(value) in (int, float) and math.isfinite(value) else None


def _absent(row: dict) -> bool | None:
    try:
        return json.loads(row['expected_box']) is None
    except (KeyError, TypeError, ValueError):
        return None


def _ratio(numerator: float, denominator: int) -> dict:
    return {'numerator': numerator, 'denominator': denominator, 'rate': numerator / denominator if denominator else None}


def _row(index: int, row: dict) -> dict:
    record = read_output(row.get('output')) or {}
    scores = {name: _number(row.get(name + '_value')) for name in SCORES}
    scores = {name: value if value is not None and 0 <= value <= 1 else None for name, value in scores.items()}
    usage = record.get('usage')
    return {'row_index': index, 'status': record.get('status'), 'absent': _absent(row),
            'elapsed_ms': _number(record.get('elapsed_ms')),
            'model': record.get('model') if isinstance(record.get('model'), str) else None,
            'usage': {name: usage[name] for name in USAGE_FIELDS if type(usage.get(name)) is int} if isinstance(usage, dict) else None,
            'scores': scores, 'error_columns': [name for name, value in row.items() if name.endswith('_error') and value]}


def _metrics(rows: list[dict]) -> dict:
    present = [row for row in rows if not row['absent']]
    absent = [row for row in rows if row['absent']]

    def total(group, name):
        return sum(row['scores'][name] for row in group)
    return {'present_localization': _ratio(total(present, 'points_correctly'), len(present)),
            'absent_accuracy': _ratio(total(absent, 'points_correctly'), len(absent)),
            'false_found': _ratio(total(absent, 'false_found'), len(absent)),
            'well_formed': _ratio(total(rows, 'reply_is_well_formed'), len(rows)),
            'missing_response': _ratio(sum(row['status'] == 'late' for row in rows), len(rows))}


def summarize_results(records: list[dict], expected_rows: int) -> dict:
    """Retain row scores, timing and usage without copying photos, questions, replies or provider errors.
    Gateway errors leave the run incomplete; replies after the deadline are scored as missing responses."""
    rows = [_row(index, row) for index, row in enumerate(records)]
    complete = len(rows) == expected_rows and all(
        row['status'] in ('ok', 'late') and row['absent'] is not None and not row['error_columns']
        and None not in row['scores'].values() for row in rows)
    elapsed = sorted(row['elapsed_ms'] for row in rows if row['elapsed_ms'] is not None)
    with_usage = [row['usage'] for row in rows if row['usage']]
    return {'rows_complete': complete, 'result_row_count': len(rows),
            'metrics': _metrics(rows) if complete and rows else None,
            'latency_ms': {'p50': elapsed[math.ceil(0.5 * len(elapsed)) - 1], 'p95': elapsed[math.ceil(0.95 * len(elapsed)) - 1],
                           'max': elapsed[-1], 'rows': len(elapsed)} if elapsed else None,
            'usage': dict({name: sum(usage.get(name, 0) for usage in with_usage) for name in USAGE_FIELDS},
                          rows=len(with_usage)) if with_usage else None,
            'resolved_models': sorted({row['model'] for row in rows if row['model']}),
            'rows': rows}
