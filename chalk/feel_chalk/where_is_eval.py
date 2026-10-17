"""Validate and optionally run the hosted Where-is evaluation.

Offline: python -m feel_chalk.where_is_eval labels.jsonl --preflight --output report.json
Hosted:  python -m feel_chalk.where_is_eval labels.jsonl --model MODEL --output report.json

Hosted mode uploads photos and deploys task/scorers only after local validation.
A successful execution is not a quality pass; inspect the persisted scores.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
from urllib.parse import urlsplit

from feel_chalk import gateway, where_is
from feel_chalk.config import settings
from feel_chalk.eval_data import DatasetError, prepare


def where_is_task(question: str, image_b64: str) -> str:
    """One gateway call per row; the raw reply is returned so scorers see exactly what the phone would."""
    config = settings()
    try:
        return gateway.chat(config, where_is.request_body(config.model or os.environ['FEEL_CHALK_MODEL'], question, image_b64))
    except gateway.GatewayError as error:
        return f'GATEWAY ERROR: {error}'


# Scorer parameters bind to dataset columns by name, plus `output` (the task's reply).
def points_correctly(output: str, expected_box: str) -> float:
    """1 when the reply's box centre lands inside the labeled box, or when the thing is absent and
    the reply says not found. Malformed replies score 0."""
    expected = json.loads(expected_box)
    try:
        answer = where_is.parse(output)
    except where_is.AnswerError:
        return 0.0
    return 1.0 if where_is.points_at(answer, tuple(expected) if expected else None) else 0.0


def reply_is_well_formed(output: str) -> float:
    """1 when the reply obeys the JSON contract at all (found or not), 0 otherwise."""
    try:
        where_is.parse(output)
        return 1.0
    except where_is.AnswerError:
        return 0.0


def false_found(output: str, expected_box: str) -> float:
    """1 when the thing is absent but the model claimed to see it: the dangerous error for a blind user."""
    if json.loads(expected_box) is not None:
        return 0.0
    try:
        return 1.0 if where_is.parse(output).found else 0.0
    except where_is.AnswerError:
        return 0.0


def load_rows(labels: Path) -> list[dict]:
    """Compatibility entry point; now performs the same mandatory validation."""
    return prepare(labels)[0]


def deploy_functions(sdk, host: str, model: str):
    # In SDK 2.13.7 applying function() starts deployment. Never decorate at import.
    task = sdk.function(where_is_task,
                        env={'CHALK_API_HOST': host, 'FEEL_CHALK_MODEL': model},
                        secrets=[sdk.Secret.from_local_env('CHALK_ROUTER_API_KEY'),
                                 sdk.Secret.from_local_env('CHALK_ENV_ID')])
    scorers = [sdk.function(function) for function in
               (points_correctly, reply_is_well_formed, false_found)]
    return task, scorers


def summarize_results(records: list[dict], expected_rows: int) -> dict:
    """Retain row scores without copying photos, questions or provider error bodies."""
    names = ('points_correctly', 'reply_is_well_formed', 'false_found')
    complete = len(records) == expected_rows
    results = []
    for index, row in enumerate(records):
        errors = [name for name, value in row.items() if name.endswith('_error') and value]
        if errors:
            complete = False
        scores = {}
        for name in names:
            value = row.get(name + '_value')
            if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 1:
                complete = False
                value = None
            scores[name] = value
        output = row.get('output')
        task_failed = not isinstance(output, str) or output.startswith('GATEWAY ERROR:')
        if task_failed:
            complete = False
        results.append({'row_index': index, 'task_failed': task_failed, 'scores': scores, 'error_columns': errors})
    means = {name: sum(row['scores'][name] for row in results) / expected_rows
             if complete and expected_rows else None for name in names}
    return {'rows_complete': complete, 'result_row_count': len(records), 'scores': means, 'rows': results}


def _load_sdk():
    import chalkcompute
    return chalkcompute


def main(argv=None, *, sdk_loader=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('labels', type=Path)
    parser.add_argument('--model', help='Gateway model override for hosted mode')
    parser.add_argument('--preflight', action='store_true', help='Validate/hash locally; no SDK, credentials or cloud calls')
    parser.add_argument('--output', type=Path, default=Path('where-is-evaluation-report.json'))
    parser.add_argument('--timeout', type=float, default=600, help='Hosted run wait limit in seconds (default: 600)')
    args = parser.parse_args(argv)
    report = {'preflight_status': 'NOT_RUN', 'execution_status': 'NOT_RUN',
              'quality_status': 'NOT_ASSESSED', 'quality_note': 'Execution completion is not a quality pass.'}

    def persist():
        args.output.write_text(json.dumps(report, sort_keys=True, indent=2, allow_nan=False) + '\n', encoding='utf-8')

    # Exclusively reserve a new report before validation: never replace labels, photos,
    # an existing report, or a symlink, even on a failed preflight.
    try:
        with args.output.open('x', encoding='utf-8') as output:
            output.write(json.dumps(report) + '\n')
    except OSError:
        print('Report path must be new and writable; no cloud operation attempted.')
        return 2

    try:
        if not math.isfinite(args.timeout) or args.timeout <= 0:
            raise ValueError('Timeout must be finite and positive.')
        rows, manifest = prepare(args.labels)
        report.update(manifest)
        report['prompt_sha256'] = hashlib.sha256(where_is.PROMPT.encode('utf-8')).hexdigest()
        report['preflight_status'] = 'PASS'
        persist()  # Prove evidence can be written before any upload or deployment.
    except Exception as error:
        report['preflight_status'] = 'FAIL'
        report['error_type'] = type(error).__name__
        if isinstance(error, (DatasetError, ValueError)):
            report['validation_error'] = str(error)
        try:
            persist()
        except OSError:
            pass
        print('Preflight failed; no cloud operation attempted. See the report when available.')
        return 2
    if args.preflight:
        print(f"Preflight PASS: {report['row_count']} rows, sha256 {report['dataset_sha256']}. No cloud operations.")
        return 0

    try:
        config = settings()
        model = args.model or config.model
        host = urlsplit(config.api_host)
        if not model or not config.router_api_key or not config.environment_id:
            raise ValueError('Hosted evaluation needs configured gateway settings.')
        if host.scheme != 'https' or not host.netloc or host.username or host.password or host.query or host.fragment:
            raise ValueError('Gateway host must be HTTPS without embedded credentials.')
        report.update(model=model, api_host=config.api_host, environment_id=config.environment_id)
        persist()
        sdk = (sdk_loader or _load_sdk)()
        dataset_client = sdk.DatasetClient()
        dataset = dataset_client.upload('feel-where-is', rows)
        report.update(dataset_id=dataset.dataset_id, dataset_revision_id=dataset.revision_id)
        persist()
        task, scorers = deploy_functions(sdk, config.api_host, model)
        evaluation = sdk.Evaluation.create(f'feel-where-is-{model.replace("/", "-")}', dataset=dataset,
                                           task=task, scorers=scorers,
                                           metadata={'dataset_sha256': report['dataset_sha256'], 'model': model, 'prompt_sha256': report['prompt_sha256']})
        report.update(evaluation_id=evaluation.id, suite_id=evaluation.suite_id)
        persist()
        run = evaluation.run(metadata={'model': model, 'dataset_sha256': report['dataset_sha256'], 'prompt_sha256': report['prompt_sha256']})
        report.update(run_id=run.id, execution_status=run.status.value)
        persist()
        run = run.wait(timeout=args.timeout, raise_on_failure=False)
        report['execution_status'] = run.status.value
        report.update(result_dataset_id=run.result_dataset_id, result_dataset_revision_id=run.result_dataset_revision_id)
        persist()
        if run.status.value != 'succeeded':
            print('Hosted evaluation did not succeed. See persisted run evidence.')
            return 1
        if run.result_dataset is None:
            report['execution_status'] = 'incomplete'
            persist()
            return 1
        summary = summarize_results(dataset_client.read(run.result_dataset).to_pylist(), report['row_count'])
        report.update(summary)
        if not summary['rows_complete']:
            report['execution_status'] = 'incomplete'
        persist()
        print(f"Execution: {report['execution_status']}. Quality: NOT_ASSESSED. Scores and run IDs: {args.output}")
        return 0 if summary['rows_complete'] else 1
    except Exception as error:
        report['execution_status'] = 'timed_out' if isinstance(error, TimeoutError) else 'failed'
        report['error_type'] = type(error).__name__  # Provider errors can contain sensitive text.
        persist()
        print('Hosted evaluation failed or is incomplete. See persisted evidence; no quality pass claimed.')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
