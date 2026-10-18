"""Export consented labeled traces for offline evaluation; never prints trace text."""
import argparse
import json
import os
from pathlib import Path
from server import Service
from evaluate import export_feedback

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database',required=True)
    parser.add_argument('--output',required=True)
    args=parser.parse_args()
    if not Path(args.database).is_file(): raise SystemExit('Database does not exist')
    if Path(args.database).resolve()==Path(args.output).resolve(): raise SystemExit('Output cannot overwrite database')
    service=Service(args.database)
    cases=export_feedback(service)
    payload={'schema_version':1,'provenance':'Consented explicit feedback. Context captured before feedback; labels are evaluation-only. Development examples, not an independent holdout.','cases':cases}
    # Atomic exclusive creation prevents accidental replacement of existing datasets.
    fd=os.open(args.output,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as output: json.dump(payload,output,indent=2); output.write('\n')
    print(json.dumps({'exported_cases':len(cases),'output':str(Path(args.output))}))
