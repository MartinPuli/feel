"""Offline CLI checks; no Chalk credentials, deployment or model calls."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from server import Service, decision
from test_server import REQUEST

ROOT=Path(__file__).parent
class EvaluationCLITests(unittest.TestCase):
    def test_help_requires_no_chalk_install_or_credentials(self):
        result=subprocess.run([sys.executable,str(ROOT/'chalk_evaluation.py'),'--help'],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
    def test_scorers_import_without_sdk_or_deployment(self):
        import chalk_evaluation as e
        output=json.dumps({'decision':{'action':'recall','place_id':'a'},'latency_ms':500})
        self.assertEqual(e.recorded_candidate(output),output)
        self.assertEqual(e.exact_intent(output,'{"action":"recall","place_id":"a"}'),1)
        self.assertEqual(e.exact_intent(output,'{"action":"recall","place_id":"b"}'),0)
        self.assertEqual(e.grounded_destination(output,'{"places":[{"id":"b"}]}'),0)
        self.assertEqual(e.tracking_guard(output,'{"tracking_valid":false,"restoring":false}'),0)
        self.assertEqual(e.latency_budget(output,100),0)
    def test_mock_rejected_before_sdk_import(self):
        with tempfile.TemporaryDirectory() as tmp:
            data=Path(tmp)/'data.json'; data.write_text('[]')
            report=Path(tmp)/'report.json'; report.write_text('{"validation":"MOCK_NOT_LIVE"}')
            result=subprocess.run([sys.executable,str(ROOT/'chalk_evaluation.py'),str(data),str(report),'--name','test','--output',str(Path(tmp)/'out.json')],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0); self.assertIn('Refusing mock',result.stderr)
    def test_duplicate_results_rejected_before_sdk_import(self):
        import hashlib
        with tempfile.TemporaryDirectory() as tmp:
            data=Path(tmp)/'data.json'; data.write_text('[{"case_id":"a"},{"case_id":"b"}]')
            report=Path(tmp)/'report.json'; report.write_text(json.dumps({'validation':'LIVE_CHALK_GATEWAY','dataset_sha256':hashlib.sha256(data.read_bytes()).hexdigest(),'rows':[{'case_id':'a'},{'case_id':'a'}]}))
            result=subprocess.run([sys.executable,str(ROOT/'chalk_evaluation.py'),str(data),str(report),'--name','test','--output',str(Path(tmp)/'out.json')],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0); self.assertIn('duplicate or mismatched',result.stderr)
    def test_feedback_export_cli_preserves_snapshot_and_private_permissions(self):
        with tempfile.TemporaryDirectory() as tmp:
            db=Path(tmp)/'db.sqlite3'; output=Path(tmp)/'export.json'
            service=Service(str(db),lambda r,a:decision('recall','Selected',place_id='a'))
            result=service.interpret(REQUEST)
            service.feedback({'trace_id':result['trace_id'],'outcome':'incorrect','corrected_place_id':'b'},'session-a')
            service.db.close()
            command=[sys.executable,str(ROOT/'export_feedback.py'),'--database',str(db),'--output',str(output)]
            run=subprocess.run(command,capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stderr)
            case=json.loads(output.read_text())['cases'][0]
            self.assertEqual(case['snapshot']['aliases'],[]); self.assertEqual(case['expected']['place_id'],'b')
            self.assertEqual(output.stat().st_mode & 0o777,0o600)
            self.assertNotEqual(subprocess.run(command,capture_output=True).returncode,0)

if __name__=='__main__': unittest.main()
