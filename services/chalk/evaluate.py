"""Immutable-context evaluation. Live mode calls Chalk; mock mode is explicitly synthetic."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import statistics
import time
from pathlib import Path
from server import Gateway, APIError, validate_request, validate_decision, PROMPT_VERSION, infer


def score(row, result, budget_ms=1000):
    d=result.get('decision',{})
    expected=row['expected']
    match=all(d.get(k)==v for k,v in expected.items()) and not result.get('error')
    context=row['snapshot']['request']['context']
    ids={p['id'] for p in context['places']}
    grounded=d.get('place_id') is None or d.get('place_id') in ids
    guarded=(context['tracking_valid'] and not context['restoring']) or d.get('action') not in {'recall','return_to_point','remember'}
    return {'correct':bool(match),'grounded':bool(grounded and not result.get('error')),'tracking_guard':bool(guarded and not result.get('error')),'within_budget':result.get('latency_ms',float('inf'))<=budget_ms and not result.get('error')}


def report(rows):
    times=sorted(r['latency_ms'] for r in rows)
    return {'cases':len(rows),'accuracy':sum(r['scores']['correct'] for r in rows)/len(rows) if rows else None,'p50_ms':statistics.median(times) if times else None,'p95_ms':times[max(0,math.ceil(len(times)*.95)-1)] if times else None,'errors':sum(bool(r.get('error')) for r in rows),'rows':rows}


def run(dataset, gateway, model_label, budget_ms=1000):
    results=[]
    for row in dataset:
        snap=row.get('snapshot') or {'request':row['request'],'aliases':[]}; row=dict(row,snapshot=snap); request=snap['request']; validate_request(request)
        # Only immutable pre-feedback context enters inference. Expected/correction never does.
        started=time.monotonic()
        result={'case_id':row['case_id'],'model':model_label,'prompt_version':PROMPT_VERSION}
        try:
            result['decision']=infer(request,snap.get('aliases',[]),gateway)
        except APIError as error:
            result['error']=error.code
        result['latency_ms']=round((time.monotonic()-started)*1000,2)
        result['scores']=score(row,result,budget_ms)
        results.append(result)
    return report(results)


def export_feedback(service):
    rows=[]
    for r in service.export():
        if r['corrected_place_id']:
            expected={'action':'recall','place_id':r['corrected_place_id'],'name':None}
        elif r['outcome']=='correct':
            expected={k:r['snapshot']['decision'][k] for k in ('action','place_id','name')}
        else:
            continue # Incorrect without a reference answer is not an accuracy label.
        rows.append({'case_id':r['trace_id'],'snapshot':r['snapshot'],'expected':expected})
    return rows

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('dataset'); parser.add_argument('--output',required=True)
    parser.add_argument('--budget-ms',type=float,default=1000)
    parser.add_argument('--mock',action='store_true',help='Synthetic transport only; NOT model quality evidence')
    args=parser.parse_args()
    data=Path(args.dataset).read_bytes(); dataset=json.loads(data); dataset=dataset['cases'] if isinstance(dataset,dict) else dataset
    gateway=Gateway()
    if not args.mock and not all((gateway.key,gateway.env,gateway.model)):
        raise SystemExit('Live evaluation requires Chalk Gateway credentials, environment and model')
    if args.mock:
        # Fixed abstention deliberately does not inspect expected labels.
        gateway=lambda request,aliases: {'action':'clarify','place_id':None,'name':None,'message':'Synthetic fixture: choose a place.'}
    started_at=datetime.now(timezone.utc).isoformat()
    result=run(dataset,gateway,'MOCK_FIXED_ABSTENTION' if args.mock else gateway.model,args.budget_ms)
    result.update(started_at=started_at,completed_at=datetime.now(timezone.utc).isoformat(),model='MOCK_FIXED_ABSTENTION' if args.mock else gateway.model,prompt_version=PROMPT_VERSION,validation='MOCK_NOT_LIVE' if args.mock else 'LIVE_CHALK_GATEWAY',dataset_sha256=hashlib.sha256(data).hexdigest(),budget_ms=args.budget_ms)
    Path(args.output).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='rows'}))
