import copy
import json
import threading
import unittest
import urllib.request
import urllib.error
from unittest.mock import patch
from http.server import ThreadingHTTPServer
from server import Service, APIError, Gateway, handler, decision
from evaluate import export_feedback, run

REQUEST={'request_id':'r1','session_id':'session-a','utterance':'go to my place','language':'en','context':{'places':[{'id':'a','name':'Entrance'},{'id':'b','name':'Desk'}],'tracking_valid':True,'restoring':False,'mode':'live'},'consent':True}
class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.r=copy.deepcopy(REQUEST); self.calls=[]
        def gateway(r,aliases):
            self.calls.append((copy.deepcopy(r),copy.deepcopy(aliases)))
            return decision('recall','Selected.',place_id='a')
        self.s=Service(':memory:',gateway)
    def assert_error(self,code,call):
        with self.assertRaises(APIError) as cm: call()
        self.assertEqual(cm.exception.code,code)
    def test_interpret_and_correction(self):
        result=self.s.interpret(self.r)
        self.assertEqual(result['decision']['place_id'],'a')
        feedback=self.s.feedback({'trace_id':result['trace_id'],'outcome':'incorrect','corrected_place_id':'b'},'session-a')
        self.assertFalse(feedback['action_executed'])
        self.r['request_id']='r2'; self.s.interpret(self.r)
        self.assertEqual(self.calls[-1][1],[{'phrase':'go to my place','place_id':'b'}])
        exported=export_feedback(self.s)
        self.assertEqual(exported[0]['expected']['place_id'],'b')
        self.assertEqual(exported[0]['snapshot']['aliases'],[])
    def test_no_consent_retains_no_text(self):
        self.r['consent']=False; result=self.s.interpret(self.r)
        self.assertIsNone(self.s.db.execute('SELECT snapshot FROM traces').fetchone()[0])
        self.assert_error('correction_not_in_consented_context',lambda:self.s.feedback({'trace_id':result['trace_id'],'outcome':'incorrect','corrected_place_id':'b'},'session-a'))
    def test_cross_session_feedback(self):
        result=self.s.interpret(self.r)
        self.assert_error('trace_not_found',lambda:self.s.feedback({'trace_id':result['trace_id'],'outcome':'correct'},'other'))
    def test_cross_session_aliases(self):
        result=self.s.interpret(self.r); self.s.feedback({'trace_id':result['trace_id'],'outcome':'incorrect','corrected_place_id':'b'},'session-a')
        self.r['session_id']='other'; self.s.interpret(self.r)
        self.assertEqual(self.calls[-1][1],[])
    def test_unknown_correction(self):
        result=self.s.interpret(self.r)
        self.assert_error('correction_not_in_consented_context',lambda:self.s.feedback({'trace_id':result['trace_id'],'outcome':'incorrect','corrected_place_id':'invented'},'session-a'))
    def test_duplicate_feedback_and_request(self):
        result=self.s.interpret(self.r)
        self.assert_error('duplicate_request',lambda:self.s.interpret(self.r))
        f={'trace_id':result['trace_id'],'outcome':'correct'}; self.s.feedback(f,'session-a')
        self.assert_error('feedback_already_recorded',lambda:self.s.feedback(f,'session-a'))
    def test_unknown_model_place(self):
        self.s.gateway=lambda r,a:decision('recall','Go.',place_id='invented')
        self.assert_error('unknown_model_destination',lambda:self.s.interpret(self.r))
    def test_tracking_guard(self):
        for field,value in [('tracking_valid',False),('restoring',True)]:
            with self.subTest(field=field):
                r=copy.deepcopy(self.r); r['request_id']=field; r['context'][field]=value
                self.assertEqual(self.s.interpret(r)['decision']['action'],'reject')
    def test_duplicate_names(self):
        self.r['context']['places'][1]['name']='Entrance'
        self.assertEqual(self.s.interpret(self.r)['decision']['action'],'clarify')
    def test_malformed_and_hardware_model(self):
        for d in ({'angle':120},decision('servo','move'),decision('stop','Stop',place_id='a'),decision('remember','Save',name='')):
            self.s.gateway=lambda r,a,d=d:d
            self.assert_error('invalid_model_name' if d.get('action')=='remember' else 'invalid_model_response',lambda:self.s.interpret(self.r))
    def test_local_stop_no_gateway(self):
        self.r['utterance']='Stop'; self.assertEqual(self.s.interpret(self.r)['decision']['action'],'stop'); self.assertEqual(self.calls,[])
    def test_delete_session(self):
        self.s.interpret(self.r); self.s.delete_session('session-a'); self.assertEqual(self.s.export(),[])
    def test_timeout(self):
        with patch.dict('os.environ',{'CHALK_ROUTER_API_KEY':'secret','CHALK_ENVIRONMENT_ID':'env','CHALK_MODEL':'model'}):
            g=Gateway()
            with patch('urllib.request.OpenerDirector.open',side_effect=TimeoutError()):
                self.assert_error('chalk_timeout',lambda:g(self.r,[]))
    def test_no_config(self):
        with patch.dict('os.environ',{},clear=True):
            self.assert_error('chalk_not_configured',lambda:Gateway()(self.r,[]))
    def test_live_evaluation_does_not_pass_expected(self):
        row={'case_id':'1','snapshot':{'request':self.r,'aliases':[]},'expected':{'action':'recall','place_id':'b'}}
        report=run([row],self.s.gateway,'fake')
        self.assertEqual(report['accuracy'],0)
        self.assertNotIn('expected',self.calls[0][0])
    def test_return_point_has_no_bookmark_id(self):
        self.s.gateway=lambda r,a:decision('return_to_point','Return.')
        self.assertEqual(self.s.interpret(self.r)['decision']['action'],'reject')
        self.r['request_id']='r2'; self.r['context']['has_return_point']=True
        self.assertEqual(self.s.interpret(self.r)['decision']['action'],'return_to_point')
    def test_retention_prunes_trace_and_alias(self):
        result=self.s.interpret(self.r)
        self.s.feedback({'trace_id':result['trace_id'],'outcome':'incorrect','corrected_place_id':'b'},'session-a')
        self.s.db.execute('UPDATE traces SET created=0'); self.s.db.commit(); self.s.prune()
        self.assertEqual(self.s.export(),[])
        self.assertEqual(self.s.db.execute('SELECT * FROM aliases').fetchall(),[])
    def test_bad_request_shapes(self):
        for change in ({'consent':'yes'},{'utterance':''},{'request_id':[]},{'context':{}},{'unexpected':1}):
            r=copy.deepcopy(self.r); r.update(change)
            with self.subTest(change=change), self.assertRaises(APIError): self.s.interpret(r)
    def test_duplicate_place_ids(self):
        self.r['context']['places'][1]['id']='a'
        self.assert_error('duplicate_place_id',lambda:self.s.interpret(self.r))
    def test_gateway_malformed_payload(self):
        class Response:
            def __enter__(self): return self
            def __exit__(self,*args): pass
            def read(self,n): return b'{"choices": []}'
        with patch.dict('os.environ',{'CHALK_ROUTER_API_KEY':'secret','CHALK_ENVIRONMENT_ID':'env','CHALK_MODEL':'model'}):
            with patch('urllib.request.OpenerDirector.open',return_value=Response()) as call:
                self.assert_error('invalid_model_response',lambda:Gateway()(self.r,[]))
                req=call.call_args[0][0]
                self.assertEqual(req.full_url,'https://api.chalk.ai/v1/router/chat/completions')
                self.assertEqual(req.get_header('X-chalk-env-id'),'env')
                self.assertEqual(req.get_header('Authorization'),'Bearer secret')
    def test_gateway_http_error_redacted(self):
        with patch.dict('os.environ',{'CHALK_ROUTER_API_KEY':'secret','CHALK_ENVIRONMENT_ID':'env','CHALK_MODEL':'model'}):
            error=urllib.error.HTTPError('https://secret.example',401,'provider secret',{},None)
            with patch('urllib.request.OpenerDirector.open',side_effect=error):
                self.assert_error('chalk_unavailable',lambda:Gateway()(self.r,[]))
    def test_replay_stop_uses_production_shortcut(self):
        self.r['utterance']='Stop'
        report=run([{'case_id':'stop','request':self.r,'expected':{'action':'stop'}}],self.s.gateway,'fake')
        self.assertEqual(report['accuracy'],1); self.assertEqual(self.calls,[])
    def test_http_auth_and_feedback(self):
        http=ThreadingHTTPServer(('127.0.0.1',0),handler(self.s,'secret')); thread=threading.Thread(target=http.serve_forever,daemon=True); thread.start()
        try:
            url=f'http://127.0.0.1:{http.server_port}/v1/interpret'
            request=urllib.request.Request(url,data=json.dumps(self.r).encode())
            with self.assertRaises(urllib.error.HTTPError) as cm: urllib.request.urlopen(request)
            self.assertEqual(cm.exception.code,401)
            request.add_header('Authorization','Bearer secret')
            with urllib.request.urlopen(request) as response: self.assertEqual(json.load(response)['session_id'],'session-a')
        finally: http.shutdown(); http.server_close()

if __name__=='__main__': unittest.main()
