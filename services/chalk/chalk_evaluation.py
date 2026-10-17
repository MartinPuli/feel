"""Publish recorded candidate runs to genuine Chalk Evaluations.

Model calls are made by evaluate.py through Chalk Model Gateway. This hosted
stage pins those outputs and runs independent deterministic scorers. It does NOT
pretend to execute new model inference remotely or re-train a model.
Requires authenticated chalkcompute, pyarrow and enabled Evaluations.
"""
import json
import chalkcompute

@chalkcompute.function
def recorded_candidate(candidate_output: str) -> str:
    return candidate_output

@chalkcompute.function
def exact_intent(output: str, expected: str) -> float:
    import json
    result=json.loads(output)
    if result.get('error'): return 0.0
    decision=result.get('decision',{})
    return float(all(decision.get(k)==v for k,v in json.loads(expected).items()))

@chalkcompute.function
def grounded_destination(output: str, context: str) -> float:
    import json
    result=json.loads(output)
    if result.get('error'): return 0.0
    destination=result.get('decision',{}).get('place_id')
    return float(destination is None or destination in {p['id'] for p in json.loads(context)['places']})

@chalkcompute.function
def tracking_guard(output: str, context: str) -> float:
    import json
    result=json.loads(output); state=json.loads(context)
    if result.get('error'): return 0.0
    return float((state['tracking_valid'] and not state['restoring']) or result.get('decision',{}).get('action') not in ('recall','remember','return_to_point'))

@chalkcompute.function
def latency_budget(output: str, budget_ms: float) -> float:
    import json
    result=json.loads(output)
    return float(not result.get('error') and result.get('latency_ms',1e9)<=budget_ms)

if __name__=='__main__':
    import argparse
    import hashlib
    from pathlib import Path
    parser=argparse.ArgumentParser()
    parser.add_argument('dataset'); parser.add_argument('candidate_report'); parser.add_argument('--name',required=True); parser.add_argument('--output',required=True)
    args=parser.parse_args()
    raw=Path(args.dataset).read_bytes(); cases=json.loads(raw); cases=cases['cases'] if isinstance(cases,dict) else cases
    candidate=json.loads(Path(args.candidate_report).read_text())
    if candidate['validation']!='LIVE_CHALK_GATEWAY': raise SystemExit('Refusing mock results in live Chalk evaluation')
    if candidate['dataset_sha256']!=hashlib.sha256(raw).hexdigest(): raise SystemExit('Dataset checksum mismatch')
    outputs={r['case_id']:r for r in candidate['rows']}
    if len(outputs)!=len(cases): raise SystemExit('Incomplete or duplicate candidate results')
    rows=[{'candidate_output':json.dumps(outputs[c['case_id']]),'expected':json.dumps(c['expected']),'context':json.dumps((c.get('snapshot') or {'request':c['request']})['request']['context']),'budget_ms':float(candidate['budget_ms'])} for c in cases]
    dataset=chalkcompute.DatasetClient().upload(args.name,rows)
    evaluation=chalkcompute.Evaluation.create(args.name,dataset=dataset,task=recorded_candidate,scorers=[exact_intent,grounded_destination,tracking_guard,latency_budget])
    run=evaluation.run(metadata={'dataset_sha256':candidate['dataset_sha256'],'prompt_version':candidate['rows'][0]['prompt_version']}).wait()
    table=chalkcompute.DatasetClient().read(run.result_dataset)
    result={'status':str(run.status),'evaluation':str(evaluation),'run':str(run),'results':table.to_pylist()}
    Path(args.output).write_text(json.dumps(result,indent=2,default=str)+'\n')
    # A SUCCEEDED run can still have row failures. Fail locally if any error column is populated.
    if len(result['results'])!=len(rows) or any(v for row in result['results'] for k,v in row.items() if k.endswith('_error')):
        raise SystemExit('Hosted evaluation has missing/error rows; inspect output')
    print(str(run.status))
