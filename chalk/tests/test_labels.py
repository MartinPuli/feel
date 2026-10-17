import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from evals.validate_labels import validate  # noqa: E402

EXAMPLE = Path(__file__).resolve().parents[1] / 'evals' / 'labels.example.jsonl'


class LabelValidatorTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        (self.dir / 'photos').mkdir()
        self.labels = self.dir / 'labels.jsonl'

    def tearDown(self):
        shutil.rmtree(self.dir)

    def write(self, rows, images=('hall-01.jpg', 'hall-02.jpg')):
        for name in images:
            (self.dir / 'photos' / name).write_bytes(b'\xff\xd8\xff')
        self.labels.write_text(''.join(json.dumps(r) + '\n' for r in rows))

    def test_example_file_is_valid(self):
        rows = [json.loads(line) for line in EXAMPLE.read_text().splitlines() if line.strip()]
        self.write(rows)
        self.assertEqual(validate(self.labels), [])

    def test_missing_image_is_reported(self):
        rows = [json.loads(line) for line in EXAMPLE.read_text().splitlines() if line.strip()]
        self.write(rows, images=('hall-01.jpg',))
        self.assertTrue(any('hall-02.jpg' in p for p in validate(self.labels)))

    def test_box_outside_image_is_reported(self):
        self.write([{'image': 'photos/hall-01.jpg', 'question': 'Where is the desk?', 'box': [0.1, 0.2, 1.3, 0.4]},
                    {'image': 'photos/hall-02.jpg', 'question': 'Where is the desk?', 'box': None}])
        self.assertTrue(any('row 1' in p and 'box' in p for p in validate(self.labels)))

    def test_requires_a_third_absent_rows(self):
        self.write([{'image': 'photos/hall-01.jpg', 'question': 'Where is the desk?', 'box': [0.1, 0.2, 0.3, 0.4]},
                    {'image': 'photos/hall-02.jpg', 'question': 'Where is the desk?', 'box': [0.1, 0.2, 0.3, 0.4]}])
        self.assertTrue(any('absent' in p for p in validate(self.labels)))

    def test_empty_file_is_reported(self):
        self.labels.write_text('')
        self.assertTrue(any('no rows' in p for p in validate(self.labels)))


if __name__ == '__main__':
    unittest.main()
