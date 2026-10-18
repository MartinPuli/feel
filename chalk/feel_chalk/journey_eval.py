"""Score frozen holdout journeys locally and say whether a candidate path version may be promoted.

python -m feel_chalk.journey_eval journeys.json --output report.json
python -m feel_chalk.journey_eval baseline.json --candidate candidate.json --output report.json

The input is an export of the journeys table (a JSON list of rows, or an object with a "journeys" list such as
protocol/journey-v1.json), walked under one path version. Only journeys whose session_id is in the frozen holdout
(protocol/journey-holdout.json, --holdout to point elsewhere) are scored; the rest are development data and are only
counted. Each holdout journey gets the scores of feel_chalk/journeys.py (arrived, min clearance, path efficiency, cue
latency p95) and the ranking is collisions first, then efficiency, then latency. With --candidate, a second export
walked under the candidate version is scored the same way and compared on the holdout: promote only when the candidate
has a lower collision rate, or the same and a higher mean efficiency, or both the same and a lower cue latency p95.

Local only: nothing is uploaded, no model is called, and the report has the numerator/denominator shape of the Where-is
report. A finished run is not a quality pass; read the scores.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path

from feel_chalk import journeys

HOLDOUT = Path(__file__).resolve().parents[2] / 'protocol' / 'journey-holdout.json'


class EvalError(ValueError):
    pass


def load_rows(source: Path) -> list[dict]:
    """The export's rows: a JSON list, or an object whose "journeys" is one."""
    try:
        data = json.loads(source.read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        raise EvalError(f'{source}: {type(error).__name__}') from None
    if isinstance(data, dict) and isinstance(data.get('journeys'), list):
        data = data['journeys']
    if not isinstance(data, list) or not all(isinstance(row, dict) for row in data):
        raise EvalError(f'{source}: not a list of journey rows')
    return data


def load_holdout(source: Path) -> list[str]:
    try:
        data = json.loads(source.read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        raise EvalError(f'{source}: {type(error).__name__}') from None
    sessions = data.get('sessions') if isinstance(data, dict) else None
    if not isinstance(sessions, list) or not sessions or not all(isinstance(s, str) and s for s in sessions):
        raise EvalError(f'{source}: needs a non-empty "sessions" list')
    return sessions


def _ratio(numerator: float, denominator: int) -> dict:
    return {'numerator': numerator, 'denominator': denominator, 'rate': numerator / denominator if denominator else None}


def score_version(rows: list[dict], holdout: list[str]) -> dict:
    """The holdout journeys of one export, scored and ranked, with per-metric numerators and denominators."""
    usable = journeys.usable(rows)
    held = [journey for journey in usable if journey.session_id in holdout]
    ranked = journeys.rank(held)
    arrived = [journey for journey, _ in ranked if journey.arrived_at is not None]
    latencies = [value for journey in held for value in journey.cue_latency_ms]
    return {
        'rows': len(rows), 'usable': len(usable), 'development': len(usable) - len(held), 'holdout': len(held),
        'holdout_sessions_missing': sorted(set(holdout) - {journey.session_id for journey in held}),
        'metrics': {
            'collisions': _ratio(sum(scores.collisions for _, scores in ranked), len(held)),
            'arrived': _ratio(len(arrived), len(held)),
            'path_efficiency': _ratio(round(sum(journeys.path_efficiency(journey) for journey in arrived), 4), len(arrived)),
        },
        'cue_latency_ms': {'p95': journeys.p95(latencies), 'cues': len(latencies)},
        'ranking': [{'session_id': journey.session_id, 'started_at': journey.started_at.isoformat(), 'arrived': scores.arrived,
                     'min_clearance_m': scores.min_clearance_m, 'collisions': scores.collisions, 'path_efficiency': scores.path_efficiency,
                     'cue_latency_p95_ms': scores.cue_latency_p95_ms} for journey, scores in ranked],
    }


def _rate(version: dict, name: str) -> float | None:
    return version['metrics'][name]['rate']


def promote(baseline: dict, candidate: dict) -> dict:
    """Yes only when the candidate is better on collisions, or equal there and better on efficiency, or equal on both and
    better on cue latency. Anything unscored on either side is not assessed."""
    pairs = [('collisions', _rate(baseline, 'collisions'), _rate(candidate, 'collisions'), 'lower'),
             ('path_efficiency', _rate(baseline, 'path_efficiency'), _rate(candidate, 'path_efficiency'), 'higher'),
             ('cue_latency_p95_ms', baseline['cue_latency_ms']['p95'], candidate['cue_latency_ms']['p95'], 'lower')]
    for name, base, cand, better in pairs:
        if base is None or cand is None:
            return {'decision': 'not assessed', 'reason': f'{name} is unscored on one side'}
        if cand == base:
            continue
        wins = cand < base if better == 'lower' else cand > base
        return {'decision': 'yes' if wins else 'no', 'reason': f'{name}: candidate {cand:g} vs baseline {base:g} ({better} is better)'}
    return {'decision': 'no', 'reason': 'equal on collisions, efficiency and latency'}


def ranking_lines(label: str, version: dict) -> list[str]:
    lines = [f'{label}: {version["holdout"]} holdout journey{"s" if version["holdout"] != 1 else ""} of {version["usable"]} usable '
             f'({version["development"]} development, {version["rows"] - version["usable"]} unusable rows)']
    for place, row in enumerate(version['ranking'], 1):
        clearance = 'no obstacle' if row['min_clearance_m'] is None else f'{row["min_clearance_m"]:.3f} m'
        latency = 'no cue' if row['cue_latency_p95_ms'] is None else f'{row["cue_latency_p95_ms"]:g} ms'
        lines.append(f'  {place}. {row["session_id"]}: {"arrived" if row["arrived"] else "did not arrive"}, clearance {clearance}, '
                     f'collisions {row["collisions"]}, efficiency {row["path_efficiency"]:.4f}, cue p95 {latency}')
    return lines


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('journeys', type=Path, help='export of the journeys table walked under the baseline path version')
    parser.add_argument('--candidate', type=Path, help='export walked under the candidate path version')
    parser.add_argument('--holdout', type=Path, default=HOLDOUT, help=f'frozen holdout sessions (default: {HOLDOUT})')
    parser.add_argument('--output', type=Path, default=Path('journey-evaluation-report.json'))
    args = parser.parse_args(argv)
    report = {'execution_mode': 'local', 'execution_status': 'NOT_RUN', 'quality_status': 'NOT_ASSESSED',
              'quality_note': 'A finished run is not a quality pass; the scores are what the holdout journeys recorded.',
              'holdout_file': str(args.holdout), 'baseline_file': str(args.journeys),
              'candidate_file': str(args.candidate) if args.candidate else None, 'promote': {'decision': 'not assessed', 'reason': 'no candidate'}}

    def persist():
        args.output.write_text(json.dumps(report, sort_keys=True, indent=2, allow_nan=False) + '\n', encoding='utf-8')

    # Reserve a new report before reading anything: never replace an export or an earlier report.
    try:
        with args.output.open('x', encoding='utf-8') as output:
            output.write(json.dumps(report) + '\n')
    except OSError:
        print('Report path must be new and writable; nothing was scored.')
        return 2
    try:
        holdout = load_holdout(args.holdout)
        report['holdout_sessions'] = holdout
        report['baseline'] = score_version(load_rows(args.journeys), holdout)
        lines = ranking_lines('Baseline', report['baseline'])
        if args.candidate:
            report['candidate'] = score_version(load_rows(args.candidate), holdout)
            report['promote'] = promote(report['baseline'], report['candidate'])
            lines += ranking_lines('Candidate', report['candidate'])
        report['execution_status'] = 'succeeded' if report['baseline']['holdout'] else 'incomplete'
        persist()
    except EvalError as error:
        report['execution_status'] = 'failed'
        report['error'] = str(error)
        persist()
        print(f'Evaluation failed: {error}. See {args.output}.')
        return 1
    for line in lines:
        print(line)
    print(f"promote: {report['promote']['decision']} ({report['promote']['reason']})")
    print(f"Execution: {report['execution_status']} (local). Quality: NOT_ASSESSED. Scores: {args.output}")
    return 0 if report['execution_status'] == 'succeeded' else 1


if __name__ == '__main__':
    raise SystemExit(main())
