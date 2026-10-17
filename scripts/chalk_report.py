#!/usr/bin/env python3
"""Render measured Chalk reports without running inference or manufacturing a baseline."""
import argparse
import html
import json
import math
from pathlib import Path


def load(path):
    report = json.loads(Path(path).read_text())
    rows = report.get('rows', [])
    if not rows or len({r['case_id'] for r in rows}) != len(rows):
        raise ValueError('Report must contain nonempty, unique case IDs')
    if any(not isinstance(r.get('latency_ms'), (int, float)) or not math.isfinite(r['latency_ms']) or r['latency_ms'] < 0 for r in rows):
        raise ValueError('Invalid measured latency')
    if report.get('cases') != len(rows):
        raise ValueError('Case count does not match report rows')
    return report


def render(candidate, baseline=None):
    if baseline and baseline.get('validation') != candidate.get('validation'):
        raise ValueError('Cannot compare mock and live validation classes')
    if baseline and (baseline.get('dataset_sha256') != candidate.get('dataset_sha256') or
                     {r['case_id'] for r in baseline['rows']} != {r['case_id'] for r in candidate['rows']}):
        raise ValueError('Comparison requires the same dataset and case IDs')
    esc=lambda x: html.escape(str(x), quote=True)
    def summary(r, label):
        n=len(r['rows']); correct=sum(x['scores']['correct'] is True for x in r['rows'])
        errors=sum(bool(x.get('error')) for x in r['rows'])
        times=sorted(x['latency_ms'] for x in r['rows'])
        p50=(times[(n-1)//2]+times[n//2])/2
        p95=times[math.ceil(n*.95)-1]
        return f'<article><h2>{label}</h2><p class="metric">{correct}/{n} correct</p><p>{errors} request errors · median {p50:.0f} ms · p95 {p95:.0f} ms</p><p>{esc(r.get("validation","UNCLASSIFIED"))}</p><p>Models: {esc(", ".join(sorted({x["model"] for x in r["rows"]})))}</p><p>Prompts: {esc(", ".join(sorted({x["prompt_version"] for x in r["rows"]})))}</p></article>'
    old={r['case_id']:r for r in baseline['rows']} if baseline else {}
    rows=[]
    for r in candidate['rows']:
        d=r.get('decision',{})
        before=('PASS' if old[r['case_id']]['scores']['correct'] else 'FAIL') if old else 'Not measured'
        after='PASS' if r['scores']['correct'] else 'FAIL'
        rows.append('<tr>'+''.join(f'<td>{esc(v)}</td>' for v in (r['case_id'],before,after,d.get('action','—'),d.get('place_id') or '—',f'{r["latency_ms"]:.0f} ms',r.get('error') or '—'))+'</tr>')
    return '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FEEL · Chalk evidence</title><style>body{background:#101412;color:#eef5ee;font:17px system-ui;max-width:1100px;margin:40px auto;padding:24px}h1{font-size:42px}a{color:#b6edc2}article{border:1px solid #566659;border-radius:16px;padding:20px;flex:1}.cards{display:flex;gap:16px;flex-wrap:wrap}.metric{font-size:32px;font-weight:700}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:12px;border-bottom:1px solid #566659}.table{overflow:auto}small{color:#b7c6b9}code{overflow-wrap:anywhere}</style><h1>FEEL · Chalk evidence</h1><p>Grounded destinations. Explicit corrections. Measured results.</p><p>These scores evaluate interpretation against labeled cases. They do not prove physical navigation, speech accuracy, or servo operation.</p><div class="cards">'''+(summary(baseline,'Baseline') if baseline else '<article><h2>Baseline</h2><p>Not measured. No improvement claim.</p></article>')+summary(candidate,'Candidate')+'''</div><h2>Every case, including failures</h2><p>Latency covers the evaluation request and decision validation, not microphone-to-action time. Failures remain in the denominator.</p><div class="table"><table><thead><tr><th>Case</th><th>Baseline</th><th>Candidate</th><th>Action</th><th>Destination</th><th>Time</th><th>Error</th></tr></thead><tbody>'''+''.join(rows)+'</tbody></table></div><p>Dataset SHA-256: <code>'+esc(candidate.get('dataset_sha256','UNRECORDED'))+'</code></p><small>Generated from saved reports. MOCK results are transport fixtures, never model-quality evidence. Hosted Chalk evaluation is a separate recorded run.</small></html>'

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('candidate');p.add_argument('--baseline');p.add_argument('--output',required=True)
    a=p.parse_args();Path(a.output).write_text(render(load(a.candidate),load(a.baseline) if a.baseline else None))
