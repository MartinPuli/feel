import hashlib
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import context  # noqa: E402

ENV = {'CHALK_API_HOST': 'https://api.example.test', 'CHALK_ENV_ID': 'env1', 'CHALK_CLIENT_ID': 'id1', 'CHALK_CLIENT_SECRET': 'secret1'}


class FakeTransport:
    def __init__(self, data=None, errors=None, token='tok'):
        self.calls = []
        self.data = data if data is not None else []
        self.errors = errors
        self.token = token

    def __call__(self, url, body, headers, timeout):
        self.calls.append((url, body, headers))
        if url.endswith('/v1/oauth/token'):
            return {'access_token': self.token}
        reply = {'data': self.data}
        if self.errors is not None:
            reply['errors'] = self.errors
        return reply


class ContextTests(unittest.TestCase):
    def setUp(self):
        for patcher in (mock.patch.dict(os.environ, ENV, clear=False), mock.patch.object(context, 'load_env_file', lambda *a, **k: None)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_last_seen_exchanges_the_token_then_runs_the_named_query(self):
        transport = FakeTransport(data=[{'field': 'object_history.spoken', 'value': 'Keys: last confirmed at the kitchen table, 2 hours ago.'}])
        with mock.patch.object(context, 'load_env_file', lambda *a, **k: None):
            sentence = context.last_seen('user-1', '  My   Keys ', transport=transport)
        self.assertEqual(sentence, 'Keys: last confirmed at the kitchen table, 2 hours ago.')
        token_url, token_body, token_headers = transport.calls[0]
        self.assertEqual(token_url, 'https://api.example.test/v1/oauth/token')
        self.assertEqual(token_body, {'client_id': 'id1', 'client_secret': 'secret1', 'grant_type': 'client_credentials'})
        self.assertNotIn('Authorization', token_headers)
        query_url, query_body, query_headers = transport.calls[1]
        self.assertEqual(query_url, 'https://api.example.test/v1/query')
        self.assertEqual(query_body, {'inputs': {'object_history.id': 'user-1:my keys'}, 'outputs': ['object_history.spoken'], 'query_name': 'last_seen'})
        self.assertEqual(query_headers, {'Authorization': 'Bearer tok', 'X-Chalk-Env-Id': 'env1'})

    def test_feature_errors_and_missing_outputs_raise_without_a_guess(self):
        with mock.patch.object(context, 'load_env_file', lambda *a, **k: None):
            with self.assertRaisesRegex(context.ContextError, 'object_history.spoken: no such user'):
                context.last_seen('u', 'keys', transport=FakeTransport(data=[{'field': 'object_history.spoken', 'error': {'message': 'no such user'}}]))
            with self.assertRaisesRegex(context.ContextError, 'no value for object_history.spoken'):
                context.last_seen('u', 'keys', transport=FakeTransport(data=[]))
            with self.assertRaisesRegex(context.ContextError, 'query failed: 401'):
                context.last_seen('u', 'keys', transport=FakeTransport(errors=[{'code': '401', 'message': 'bad token'}]))
            with self.assertRaisesRegex(context.ContextError, 'no access token'):
                context.last_seen('u', 'keys', transport=FakeTransport(token=''))

    def test_missing_credentials_are_named(self):
        with mock.patch.dict(os.environ, {'CHALK_CLIENT_SECRET': ''}), mock.patch.object(context, 'load_env_file', lambda *a, **k: None):
            with self.assertRaisesRegex(context.ContextError, 'CHALK_CLIENT_SECRET'):
                context.query({}, ['x'], transport=FakeTransport())

    def test_venue_pack_is_checked_like_the_phone_checks_it(self):
        payload = json.dumps({'venue_id': 'harvard-yard', 'entries': []}, separators=(',', ':'))
        pack = {'schema': 1, 'sha256': hashlib.sha256(payload.encode()).hexdigest(), 'payload': payload}
        with mock.patch.object(context, 'load_env_file', lambda *a, **k: None):
            got = context.venue_pack('harvard-yard', transport=FakeTransport(data=[{'field': 'venue.pack', 'value': json.dumps(pack)}]))
            self.assertEqual(got, pack)
            corrupt = dict(pack, payload=payload + ' ')
            with self.assertRaisesRegex(context.ContextError, 'hash does not match'):
                context.venue_pack('harvard-yard', transport=FakeTransport(data=[{'field': 'venue.pack', 'value': json.dumps(corrupt)}]))
            with self.assertRaisesRegex(context.ContextError, 'wrong shape'):
                context.venue_pack('harvard-yard', transport=FakeTransport(data=[{'field': 'venue.pack', 'value': '{"payload": 1}'}]))


if __name__ == '__main__':
    unittest.main()
