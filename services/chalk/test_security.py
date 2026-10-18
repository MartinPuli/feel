"""Credential isolation and request lifecycle tests, with no cloud calls."""
import copy
import json
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer
import threading
import unittest
from unittest.mock import patch
from server import APIError, Service, decision, load_tokens, handler
from test_server import REQUEST


class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        def gateway(request, aliases):
            self.calls.append(copy.deepcopy(aliases))
            return decision('recall', 'Selected.', place_id='a')
        self.service = Service(':memory:', gateway)

    def test_same_caller_supplied_session_cannot_access_other_users_feedback(self):
        result = self.service.interpret(REQUEST, 'alice')
        with self.assertRaises(APIError) as caught:
            self.service.feedback({'trace_id': result['trace_id'], 'outcome': 'correct'}, 'session-a', 'bob')
        self.assertEqual(caught.exception.code, 'trace_not_found')
        self.service.feedback({'trace_id': result['trace_id'], 'outcome': 'incorrect', 'corrected_place_id': 'b'}, 'session-a', 'alice')
        self.service.interpret(REQUEST, 'bob')
        self.assertEqual(self.calls[-1], [])
        request = copy.deepcopy(REQUEST)
        request['request_id'] = 'next'
        self.service.interpret(request, 'alice')
        self.assertEqual(self.calls[-1], [{'phrase': 'go to my place', 'place_id': 'b'}])

    def test_other_principal_cannot_delete_session(self):
        result = self.service.interpret(REQUEST, 'alice')
        self.service.feedback({'trace_id': result['trace_id'], 'outcome': 'correct'}, 'session-a', 'alice')
        self.service.delete_session('session-a', 'bob')
        self.assertEqual(len(self.service.export()), 1)
        self.service.delete_session('session-a', 'alice')
        self.assertEqual(self.service.export(), [])

    def test_http_identity_comes_from_credential_not_supplied_session(self):
        server=ThreadingHTTPServer(('127.0.0.1',0),handler(self.service, {'alice':'alice-token','bob':'bob-token'}))
        thread=threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        def post(path, token, body):
            request=urllib.request.Request(f'http://127.0.0.1:{server.server_port}'+path,
                data=json.dumps(body).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
            with urllib.request.urlopen(request,timeout=2) as result:
                return json.load(result)
        try:
            result=post('/v1/interpret','alice-token',REQUEST)
            feedback={'trace_id':result['trace_id'],'session_id':'session-a','outcome':'correct'}
            with self.assertRaises(urllib.error.HTTPError) as caught:
                post('/v1/feedback','bob-token',feedback)
            self.assertEqual(caught.exception.code,404)
            self.assertTrue(post('/v1/feedback','alice-token',feedback)['recorded'])
            post('/v1/delete-session','bob-token',{'session_id':'session-a'})
            self.assertEqual(len(self.service.export()),1)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(2)

    def test_credentials_are_distinct_and_validated(self):
        for tokens in ('{}', '{"a":"short"}', '{"a":"' + 'x'*32 + '","b":"' + 'x'*32 + '"}'):
            with self.subTest(tokens=tokens), patch.dict('os.environ', {'FEEL_API_TOKENS_JSON': tokens}), self.assertRaises(ValueError):
                load_tokens()
        with patch.dict('os.environ', {'FEEL_API_TOKENS_JSON': '{"alice":"' + 'x'*32 + '","bob":"' + 'y'*32 + '"}'}):
            self.assertEqual(set(load_tokens()), {'alice', 'bob'})


class RequestLifecycleTests(unittest.TestCase):
    def test_duplicate_is_rejected_before_second_gateway_call_and_delete_invalidates_inflight(self):
        entered = threading.Event()
        release = threading.Event()
        outcomes = []
        calls = []
        def gateway(request, aliases):
            calls.append(request['request_id'])
            entered.set()
            if not release.wait(2):
                raise AssertionError('test release timed out')
            return decision('recall', 'Selected.', place_id='a')
        service = Service(':memory:', gateway)
        def run():
            try:
                outcomes.append(service.interpret(REQUEST, 'alice'))
            except APIError as error:
                outcomes.append(error.code)
        thread = threading.Thread(target=run)
        thread.start()
        try:
            self.assertTrue(entered.wait(2))
            with self.assertRaises(APIError) as caught:
                service.interpret(REQUEST, 'alice')
            self.assertEqual(caught.exception.code, 'duplicate_request')
            service.delete_session('session-a', 'alice')
        finally:
            release.set()
            thread.join(2)
        self.assertFalse(thread.is_alive())
        self.assertEqual(calls, ['r1'])
        self.assertEqual(outcomes, ['session_deleted'])
        self.assertEqual(service.export(), [])
        self.assertEqual(service.inflight, set())

    def test_failed_gateway_releases_reservation_for_retry(self):
        def failing_gateway(request, aliases):
            raise APIError(504, 'chalk_timeout')
        service = Service(':memory:', failing_gateway)
        with self.assertRaises(APIError):
            service.interpret(REQUEST, 'alice')
        service.gateway = lambda request, aliases: decision('clarify', 'Which place?')
        self.assertEqual(service.interpret(REQUEST, 'alice')['decision']['action'], 'clarify')

if __name__ == '__main__':
    unittest.main()
