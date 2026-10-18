import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import context, room_map  # noqa: E402

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
            return {'access_token': self.token, 'engines': {'env1': 'https://engine.example.test'}}
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
        self.assertEqual(query_url, 'https://engine.example.test/v1/query/online', 'the environment engine answers queries, not api.chalk.ai')
        self.assertEqual(query_body, {'inputs': {'object_history.id': 'user-1:my keys'}, 'outputs': ['object_history.spoken'], 'query_name': 'last_seen'})
        self.assertEqual(query_headers, {'Authorization': 'Bearer tok', 'X-Chalk-Env-Id': 'env1', 'X-Chalk-Client-Id': 'id1', 'X-Chalk-Deployment-Type': 'engine'})

    def test_a_grant_without_an_engine_for_the_environment_is_refused(self):
        class NoEngine(FakeTransport):
            def __call__(self, url, body, headers, timeout):
                reply = super().__call__(url, body, headers, timeout)
                return {'access_token': 'tok', 'engines': {'other': 'https://x'}} if url.endswith('/v1/oauth/token') else reply
        with self.assertRaisesRegex(context.ContextError, 'no query engine for environment env1'):
            context.last_seen('u', 'keys', transport=NoEngine(data=[{'field': 'object_history.spoken', 'value': 'x'}]))

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

    def test_room_anchors_runs_the_named_query_and_returns_the_remembered_targets(self):
        targets = '[{"label": "exit", "x": -4.0, "y": 5.1, "z": 0.05, "sightings": 4, "last_seen_at": "2026-10-17T20:00:00+00:00"}]'
        spoken = 'Remembered here: exit about 6 meters ahead-right, seen 4 times, last 2 hours ago.'
        transport = FakeTransport(data=[{'field': 'room_memory.spoken', 'value': spoken}, {'field': 'room_memory.targets', 'value': targets}])
        got = context.room_anchors(' Harvard-Yard ', 'FEEL-TAG-01 ', transport=transport)
        self.assertEqual(got['spoken'], spoken)
        self.assertEqual([(t.label, t.x, t.y, t.z, t.sightings) for t in got['targets']], [('exit', -4.0, 5.1, 0.05, 4)])
        query_url, query_body, query_headers = transport.calls[1]
        self.assertEqual(query_url, 'https://engine.example.test/v1/query/online')
        self.assertEqual(query_body, {'inputs': {'room_memory.id': 'harvard-yard:feel-tag-01'},
                                      'outputs': ['room_memory.spoken', 'room_memory.targets'], 'query_name': 'room_anchors'})
        self.assertEqual(query_headers, {'Authorization': 'Bearer tok', 'X-Chalk-Env-Id': 'env1', 'X-Chalk-Client-Id': 'id1', 'X-Chalk-Deployment-Type': 'engine'})

    def test_room_anchors_rejects_malformed_targets_instead_of_guessing(self):
        for value, reason in [('nope', 'not JSON'), ('{"label": "exit"}', 'wrong shape'), ('[{"label": "exit"}]', 'wrong shape'), ('', 'empty')]:
            with self.subTest(value=value):
                with self.assertRaisesRegex(context.ContextError, reason):
                    context.room_anchors('v', 't', transport=FakeTransport(data=[{'field': 'room_memory.spoken', 'value': 'x'},
                                                                                   {'field': 'room_memory.targets', 'value': value}]))

    MERGED = room_map.RoomMap(0.1, -0.2, 0.0, 8, 6, '28f2b10f2u6b')

    def test_room_structure_runs_the_named_query_and_returns_the_merged_map(self):
        transport = FakeTransport(data=[{'field': 'room_memory.structure', 'value': self.MERGED.to_json()}, {'field': 'room_memory.structure_visits', 'value': 3}])
        got = context.room_structure(' Harvard-Yard ', 'FEEL-TAG-01 ', transport=transport)
        self.assertEqual(got, {'map': self.MERGED, 'visits': 3})
        query_url, query_body, query_headers = transport.calls[1]
        self.assertEqual(query_url, 'https://engine.example.test/v1/query/online')
        self.assertEqual(query_body, {'inputs': {'room_memory.id': 'harvard-yard:feel-tag-01'},
                                      'outputs': ['room_memory.structure', 'room_memory.structure_visits'], 'query_name': 'room_structure'})
        self.assertEqual(query_headers['X-Chalk-Env-Id'], 'env1')

    def test_room_structure_without_shared_visits_is_no_map(self):
        transport = FakeTransport(data=[{'field': 'room_memory.structure', 'value': None}, {'field': 'room_memory.structure_visits', 'value': 0}])
        self.assertEqual(context.room_structure('v', 't', transport=transport), {'map': None, 'visits': 0})

    def test_room_structure_rejects_malformed_maps_instead_of_guessing(self):
        for value in ['nope', '{"width": 1}', '{"schema": 1, "cell_size": 0.1, "origin_x": 0, "origin_y": 0, "width": 1, "height": 1, "cells": "2f"}', 7, '']:
            with self.subTest(value=value):
                with self.assertRaisesRegex(context.ContextError, 'not a room map'):
                    context.room_structure('v', 't', transport=FakeTransport(data=[{'field': 'room_memory.structure', 'value': value},
                                                                                     {'field': 'room_memory.structure_visits', 'value': 1}]))
        for visits in ['three', -1, True, None]:
            with self.subTest(visits=visits):
                with self.assertRaisesRegex(context.ContextError, 'structure_visits'):
                    context.room_structure('v', 't', transport=FakeTransport(data=[{'field': 'room_memory.structure', 'value': None},
                                                                                     {'field': 'room_memory.structure_visits', 'value': visits}]))

    def test_room_structure_command_writes_the_map_and_says_what_it_holds(self):
        output = Path(tempfile.mkdtemp()) / 'structure.json'
        with mock.patch.object(context, 'room_structure', return_value={'map': self.MERGED, 'visits': 3}), contextlib.redirect_stdout(io.StringIO()) as printed:
            self.assertEqual(context.main(['room-structure', '--venue', ' Harvard-Yard', '--tag', 'feel-tag-01', '--output', str(output)]), 0)
        self.assertEqual(room_map.from_json(output.read_text()), self.MERGED)
        self.assertEqual(printed.getvalue().strip(), 'Room structure at harvard-yard:feel-tag-01: 8 x 6 cells of 0.1 m, 46 remembered (38 free, 8 blocked), '
                         f'merged from 3 visits. Wrote {output}.')
        with mock.patch.object(context, 'room_structure', return_value={'map': self.MERGED, 'visits': 3}), contextlib.redirect_stdout(io.StringIO()) as printed:
            self.assertEqual(context.main(['room-structure', '--venue', 'harvard-yard', '--tag', 'feel-tag-01', '--output', str(output)]), 2, 'the output path must be new')
        with mock.patch.object(context, 'room_structure', return_value={'map': None, 'visits': 0}), contextlib.redirect_stdout(io.StringIO()) as printed:
            self.assertEqual(context.main(['room-structure', '--venue', 'v', '--tag', 't', '--output', str(output.with_name('none.json'))]), 0)
        self.assertEqual(printed.getvalue().strip(), 'Nothing is remembered about the structure of the room at v:t yet.')
        self.assertFalse(output.with_name('none.json').exists())


if __name__ == '__main__':
    unittest.main()
