import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feel_chalk import where_is  # noqa: E402
from feel_chalk.config import Settings  # noqa: E402

PROTOCOL = Path(__file__).resolve().parents[2] / 'protocol'


class ContractTests(unittest.TestCase):
    def test_prompt_matches_shared_file(self):
        self.assertEqual(where_is.PROMPT, (PROTOCOL / 'where-is-prompt.txt').read_text().strip())

    def test_deadline_matches_shared_file(self):
        shared = json.loads((PROTOCOL / 'where-is-cases.json').read_text())['deadline_seconds']
        self.assertEqual(where_is.DEADLINE_SECONDS, shared)

    def test_shared_parser_cases(self):
        cases = json.loads((PROTOCOL / 'where-is-cases.json').read_text())['cases']
        self.assertGreater(len(cases), 0)
        for case in cases:
            with self.subTest(case['name']):
                if case.get('error'):
                    with self.assertRaises(where_is.AnswerError):
                        where_is.parse(case['text'])
                    continue
                answer = where_is.parse(case['text'])
                expect = case['expect']
                self.assertEqual(answer.found, expect['found'])
                self.assertEqual(answer.label, expect['label'])
                self.assertEqual(answer.box, tuple(expect['box']) if expect['box'] else None)
                self.assertAlmostEqual(answer.confidence, expect['confidence'])

    def test_request_body_carries_prompt_question_and_image(self):
        body = where_is.request_body('anthropic/example', 'Where is the desk?', 'QUJD')
        self.assertEqual(body['model'], 'anthropic/example')
        self.assertEqual(body['messages'][0], {'role': 'system', 'content': where_is.PROMPT})
        parts = body['messages'][1]['content']
        self.assertEqual(parts[0], {'type': 'text', 'text': 'Where is the desk?'})
        self.assertEqual(parts[1]['image_url']['url'], 'data:image/jpeg;base64,QUJD')


class ScoringTests(unittest.TestCase):
    desk = (0.6, 0.4, 0.9, 0.8)

    def test_centre_inside_labeled_box_is_correct(self):
        self.assertTrue(where_is.points_at(where_is.Answer(True, 'desk', (0.65, 0.5, 0.85, 0.7), 0.9), self.desk))

    def test_centre_outside_labeled_box_is_wrong(self):
        self.assertFalse(where_is.points_at(where_is.Answer(True, 'desk', (0.0, 0.0, 0.2, 0.2), 0.9), self.desk))

    def test_not_found_is_wrong_when_thing_is_there(self):
        self.assertFalse(where_is.points_at(where_is.Answer(False, '', None, 0), self.desk))

    def test_not_found_is_correct_when_thing_is_absent(self):
        self.assertTrue(where_is.points_at(where_is.Answer(False, '', None, 0), None))

    def test_any_found_answer_is_wrong_when_thing_is_absent(self):
        self.assertFalse(where_is.points_at(where_is.Answer(True, 'desk', self.desk, 0.9), None))


class SettingsTests(unittest.TestCase):
    def test_missing_lists_every_unset_value(self):
        self.assertEqual(Settings('https://api.chalk.ai', None, None, None).missing(),
                         ['CHALK_ROUTER_API_KEY', 'CHALK_ENV_ID', 'FEEL_CHALK_MODEL'])

    def test_router_base(self):
        self.assertEqual(Settings('https://api.chalk.ai/', 'k', 'e', 'm').router_base, 'https://api.chalk.ai/v1/router')


if __name__ == '__main__':
    unittest.main()
