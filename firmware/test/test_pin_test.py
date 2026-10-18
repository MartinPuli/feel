#!/usr/bin/env python3
"""Host checks for firmware/tools/pin_test.py: pin specs, packets, pictures, status decoding."""
import sys
import asyncio
import contextlib
import io
import types
from unittest.mock import patch
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


class BLEVerificationTests(unittest.TestCase):
    """A fake radio exercises transport ordering; these tests never discover hardware."""
    bands = [0, 0, 0, 2, 0, 0, 0]

    def exercise(self, *, overrides=None, cleanup_notify=True, fail_hold=False,
                 fail_clear=False, read_fails=False, notifications=True, read_delay=0,
                 fail_stop=False, cancel_hold=False):
        clock = [0.0]
        writes = []
        state = {'callback': None, 'last': None, 'stopped': False, 'exited': False}
        overrides = overrides or {}

        def status(data):
            fields = {'connected': 1, 'active': 1, 'sequenceValid': 1,
                      'lastSequence': data[0], 'highlight': data[8],
                      'benchArmed': 0, 'output': 1}
            fields.update(overrides)
            return bytes([1, fields['connected'], fields['active'], fields['sequenceValid'],
                          fields['lastSequence'], fields['highlight'], fields['benchArmed'],
                          fields['output']] + list(data[1:8]))

        class Client:
            def __init__(self, _): pass
            async def __aenter__(self): return self
            async def __aexit__(self, *args): state['exited'] = True
            async def start_notify(self, _, callback): state['callback'] = callback
            async def stop_notify(self, _):
                state['stopped'] = True
                if fail_stop: raise OSError('simulated stop failure')
            async def write_gatt_char(self, _, data, **kwargs):
                writes.append(data)
                clear = not any(data[1:8])
                if cancel_hold and not clear:
                    raise asyncio.CancelledError()
                if (fail_hold and not clear) or (fail_clear and clear):
                    raise OSError('simulated write failure')
                state['last'] = status(data)
                if notifications and (not clear or cleanup_notify):
                    state['callback'](None, bytearray(state['last']))
            async def read_gatt_char(self, _):
                clock[0] += read_delay
                if read_fails: raise OSError('simulated read failure')
                return state['last']

        async def discover(*args, **kwargs): return object()
        async def sleep(delay): clock[0] += delay
        fake = types.SimpleNamespace(BleakClient=Client,
                                     BleakScanner=types.SimpleNamespace(find_device_by_name=discover))
        with patch.dict(sys.modules, {'bleak': fake}), \
             patch.object(pin_test.time, 'monotonic', lambda: clock[0]), \
             patch.object(pin_test.asyncio, 'sleep', sleep), contextlib.redirect_stdout(io.StringIO()):
            try:
                result = asyncio.run(pin_test.run_ble(self.bands, 3, 0.5, 'fake'))
            except asyncio.CancelledError:
                result = 'cancelled'
        return result, writes, state

    def test_cleanup_notifications_do_not_replace_hold_evidence(self):
        self.assertEqual(self.exercise()[0], 0)

    def test_unready_or_unrelated_status_never_proves_hold(self):
        for overrides in ({'output': 0}, {'output': 2}, {'lastSequence': 99},
                          {'highlight': 255}, {'connected': 0}, {'sequenceValid': 0},
                          {'benchArmed': 1}, {'active': 0}):
            with self.subTest(overrides=overrides):
                self.assertEqual(self.exercise(overrides=overrides, cleanup_notify=False)[0], 1)

    def test_read_failure_can_use_correlated_hold_notification(self):
        self.assertEqual(self.exercise(read_fails=True)[0], 0)

    def test_missing_evidence_is_failure(self):
        self.assertEqual(self.exercise(read_fails=True, notifications=False)[0], 1)

    def test_hold_write_failure_still_attempts_three_neutrals_and_disconnects(self):
        code, writes, state = self.exercise(fail_hold=True)
        self.assertEqual(code, 1)
        self.assertEqual(sum(not any(data[1:8]) for data in writes), 3)
        self.assertTrue(state['exited'])
        self.assertTrue(state['stopped'])

    def test_evidence_older_than_watchdog_is_rejected(self):
        self.assertEqual(self.exercise(read_delay=0.6)[0], 1)

    def test_cancellation_propagates_after_neutral_cleanup(self):
        code, writes, state = self.exercise(cancel_hold=True)
        self.assertEqual(code, 'cancelled')
        self.assertEqual(sum(not any(data[1:8]) for data in writes), 3)
        self.assertTrue(state['exited'])

    def test_notification_cleanup_error_is_not_success(self):
        self.assertEqual(self.exercise(fail_stop=True)[0], 1)

    def test_clear_failure_retries_and_cannot_report_success(self):
        code, writes, state = self.exercise(fail_clear=True)
        self.assertEqual(code, 1)
        self.assertEqual(sum(not any(data[1:8]) for data in writes), 3)
        self.assertTrue(state['exited'])


class LidarArgumentTests(unittest.TestCase):
    def test_each_aborts_after_failed_hold(self):
        with patch.object(pin_test, 'run_ble', return_value=1) as hold, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(pin_test.main(['--each']), 1)
        self.assertEqual(hold.call_count, 1)

    def test_documented_negative_bearing_cli(self):
        with patch.object(pin_test, 'lidar_to_bands', return_value=([0] * 7, [None] * 7)) as project, \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(pin_test.main(['--lidar', '-30:1.2', '20:0.6', '--dry-run']), 0)
        self.assertEqual(project.call_args.args[0][0]['bearingDegrees'], -30.0)

    def test_malformed_height_and_extra_fields_are_rejected(self):
        for spec in ('0:1:nan', '0:1:inf', '0:1:1:2'):
            with self.subTest(spec=spec), self.assertRaises(SystemExit):
                pin_test.parse_obstacles([spec])


if __name__ == '__main__':
    unittest.main(verbosity=2)
