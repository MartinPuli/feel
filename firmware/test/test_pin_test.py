#!/usr/bin/env python3
"""Host checks for firmware/tools/pin_test.py: pin specs, packets, pictures, status decoding."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import pin_test  # noqa: E402


class PinSpecTests(unittest.TestCase):
    def test_pins_map_to_wire_slots(self):
        self.assertEqual(pin_test.parse_pins(['3:2', '5:4']), [0, 0, 0, 2, 0, 4, 0])

    def test_rejects_slot_zero_and_bad_bands(self):
        for bad in (['0:1'], ['7:1'], ['3:5'], ['3:0'], ['3'], ['3:2', '3:1']):
            with self.assertRaises(SystemExit, msg=bad):
                pin_test.parse_pins(bad)

    def test_obstacles_parse_with_optional_height(self):
        self.assertEqual(pin_test.parse_obstacles(['-30:1.2', '20:0.6:0.8']),
                         [{'bearingDegrees': -30.0, 'distance': 1.2, 'height': 1.0},
                          {'bearingDegrees': 20.0, 'distance': 0.6, 'height': 0.8}])
        for bad in (['50:1'], ['0:0'], ['0:4.5'], ['x']):
            with self.assertRaises(SystemExit, msg=bad):
                pin_test.parse_obstacles(bad)

    def test_band_edges_match_the_encoder(self):
        self.assertEqual([pin_test.band_of(d) for d in (0.5, 0.89, 0.9, 1.59, 1.6, 2.49, 2.5, 4.0, 4.01, None)],
                         [1, 1, 2, 2, 3, 3, 4, 4, 0, 0])


class PacketTests(unittest.TestCase):
    def test_nine_byte_packet_layout(self):
        self.assertEqual(pin_test.packet(7, [0, 0, 0, 2, 0, 4, 0]), bytes([7, 0, 0, 0, 2, 0, 4, 0, 255]))
        self.assertEqual(pin_test.packet(300, [0] * 7, 3)[0], 300 & 0xFF)

    def test_status_decoding(self):
        status = bytes([1, 1, 1, 1, 42, 255, 0, 1, 0, 0, 0, 2, 0, 4, 0])
        decoded = pin_test.decode_status(status)
        self.assertEqual(decoded['bands'], [0, 0, 0, 2, 0, 4, 0])
        self.assertTrue(decoded['active'])
        self.assertEqual(decoded['output'], 'ready')
        self.assertEqual(decoded['lastSequence'], 42)
        self.assertEqual(pin_test.decode_status(b'\x02'), {'raw': '02'})

    def test_compare_reports_each_wrong_pin_and_slot_zero(self):
        self.assertEqual(pin_test.compare([0, 0, 0, 2, 0, 4, 0], [0, 0, 0, 2, 0, 4, 0]), [])
        problems = pin_test.compare([0, 0, 0, 2, 0, 4, 0], [1, 0, 0, 0, 0, 4, 0])
        self.assertEqual(len(problems), 2)
        self.assertIn('L1 slot 3', problems[0])
        self.assertIn('slot 0', problems[1])


class PictureTests(unittest.TestCase):
    def test_picture_marks_only_the_raised_pins(self):
        text = pin_test.picture([0, 0, 0, 2, 0, 4, 0], highlight=5)
        rows = text.splitlines()
        self.assertEqual(rows[0].split(), ['L3', 'L2', 'L1', 'R1', 'R2', 'R3'])
        far = rows[1].split()[2:]
        self.assertEqual(far, ['·', '·', '·', '·', '▲', '·'])          # slot 5 at band 4, tapping
        band2 = rows[3].split()[1:]
        self.assertEqual(band2, ['·', '·', '█', '·', '·', '·'])        # slot 3 at band 2
        self.assertEqual(text.count('█') + text.count('▲'), 2)

    def test_dry_run_prints_without_hardware(self):
        self.assertEqual(pin_test.main(['--pins', '3:2', '5:4', '--dry-run']), 0)
        self.assertEqual(pin_test.main(['--each', '--band', '1', '--dry-run']), 0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
