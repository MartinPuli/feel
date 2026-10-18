import contextlib
import io
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import context, query_token  # noqa: E402

ENV = {'CHALK_API_HOST': 'https://api.example.test', 'CHALK_ENV_ID': 'env1', 'CHALK_CLIENT_ID': 'id1', 'CHALK_CLIENT_SECRET': 'secret1'}


class FakeTransport:
    def __init__(self, grant=None):
        self.calls = []
        self.grant = grant if grant is not None else {'access_token': 'tok.en.sig', 'expires_in': 7200,
                                                      'engines': {'env1': 'https://engine.example.test/'}}

    def __call__(self, url, body, headers, timeout):
        self.calls.append((url, body, headers))
        return self.grant


class QueryTokenTests(unittest.TestCase):
    def setUp(self):
        for patcher in (mock.patch.dict(os.environ, ENV, clear=False), mock.patch.object(context, 'load_env_file', lambda *a, **k: None)):
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_access_is_the_token_exchange_and_the_grants_engine(self):
        transport = FakeTransport()
        granted = query_token.access(transport=transport)
        self.assertEqual(len(transport.calls), 1, 'only the exchange; no query is run here')
        url, body, headers = transport.calls[0]
        self.assertEqual(url, 'https://api.example.test/v1/oauth/token')
        self.assertEqual(body, {'client_id': 'id1', 'client_secret': 'secret1', 'grant_type': 'client_credentials'})
        self.assertEqual(headers, {})
        self.assertEqual(granted, {'engine': 'https://engine.example.test', 'token': 'tok.en.sig', 'environment': 'env1',
                                   'client_id': 'id1', 'expires_in': 7200})

    def test_the_lines_are_what_the_build_config_takes_and_never_the_secret(self):
        lines = query_token.xcconfig_lines(query_token.access(transport=FakeTransport()))
        self.assertEqual(lines, ['FEEL_CHALK_QUERY_ENGINE = https:/$()/engine.example.test',
                                 'FEEL_CHALK_QUERY_TOKEN = tok.en.sig',
                                 'FEEL_CHALK_CLIENT_ID = id1'])
        self.assertNotIn('secret1', '\n'.join(lines))

    def test_a_grant_without_a_token_or_an_engine_is_refused(self):
        with self.assertRaisesRegex(context.ContextError, 'no access token'):
            query_token.access(transport=FakeTransport({'access_token': '', 'engines': {'env1': 'https://e'}}))
        with self.assertRaisesRegex(context.ContextError, 'no query engine for environment env1'):
            query_token.access(transport=FakeTransport({'access_token': 'tok', 'engines': {'other': 'https://e'}}))
        with self.assertRaisesRegex(context.ContextError, 'no query engine'):
            query_token.access(transport=FakeTransport({'access_token': 'tok', 'engines': {'env1': 'http://plain'}}))

    def test_an_unknown_lifetime_is_said_not_guessed(self):
        granted = query_token.access(transport=FakeTransport({'access_token': 'tok', 'engines': {'env1': 'https://e.test'}}))
        self.assertIsNone(granted['expires_in'])
        self.assertEqual(query_token.lifetime(None), 'The grant did not say when the token expires.')
        self.assertEqual(query_token.lifetime(7200), 'The token expires in about 2.0 hours; rerun before the demo build.')
        self.assertEqual(query_token.lifetime(900), 'The token expires in about 15 minutes; rerun before the demo build.')

    def test_main_prints_the_lines_to_stdout_and_the_expiry_to_stderr(self):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(query_token.context, 'post', FakeTransport()), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = query_token.main([])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue().splitlines(), ['FEEL_CHALK_QUERY_ENGINE = https:/$()/engine.example.test',
                                                       'FEEL_CHALK_QUERY_TOKEN = tok.en.sig', 'FEEL_CHALK_CLIENT_ID = id1'])
        self.assertIn('expires in about 2.0 hours', err.getvalue())
        self.assertNotIn('tok.en.sig', err.getvalue(), 'the token travels through stdout only')

    def test_main_fails_plainly_without_credentials(self):
        err = io.StringIO()
        with mock.patch.dict(os.environ, {'CHALK_CLIENT_SECRET': ''}), contextlib.redirect_stderr(err):
            code = query_token.main([])
        self.assertEqual(code, 1)
        self.assertIn('missing in chalk/.env: CHALK_CLIENT_SECRET', err.getvalue())


if __name__ == '__main__':
    unittest.main()
