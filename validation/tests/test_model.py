"""Contract and explicit-policy tests. These do not test production software."""

from dataclasses import FrozenInstanceError
import json
import math
from pathlib import Path
import random
import tempfile
import unittest
from unittest.mock import patch

from validation.feel_model import (
    InputPolicy, ModelConfig, Packet, ReceiverModel, bearing_column,
    distance_band, encode_synthetic_frame, gap_for_band, tap_dip_angle,
)
from validation.run_scenarios import compare, render_html, run_suite, validate_suite


ROOT = Path(__file__).parents[1]


def wire(seq=0, bands=(1,) * 7, highlight=255):
    return Packet(seq, bands, highlight).encode()


class PacketContractTests(unittest.TestCase):
    def test_golden_valid_bytes_and_fields(self):
        vectors = json.loads((ROOT / "fixtures/protocol_vectors.json").read_text())
        for item in vectors["valid"]:
            with self.subTest(vector=item["id"]):
                packet = Packet.decode(bytes.fromhex(item["hex"]))
                self.assertEqual(packet.seq, item["seq"])
                self.assertEqual(list(packet.bands), item["bands"])
                self.assertEqual(packet.highlight, item["highlight"])
                self.assertEqual(Packet(item["seq"], item["bands"], item["highlight"]).encode().hex(), item["hex"])

    def test_golden_invalid_payloads(self):
        vectors = json.loads((ROOT / "fixtures/protocol_vectors.json").read_text())
        for item in vectors["invalid"]:
            with self.subTest(vector=item["id"]):
                with self.assertRaises(ValueError):
                    Packet.decode(bytes.fromhex(item["hex"]))

    def test_every_byte_value_in_every_band_position(self):
        for column in range(7):
            for value in range(256):
                payload = bytearray(wire())
                payload[column + 1] = value
                if value <= 4:
                    self.assertEqual(Packet.decode(payload).bands[column], value)
                else:
                    with self.assertRaises(ValueError):
                        Packet.decode(payload)

    def test_every_highlight_byte(self):
        for value in range(256):
            payload = bytearray(wire())
            payload[-1] = value
            if value <= 6 or value == 255:
                self.assertEqual(Packet.decode(payload).highlight, value)
            else:
                with self.assertRaises(ValueError):
                    Packet.decode(payload)

    def test_all_sequence_bytes_are_legal(self):
        for seq in range(256):
            self.assertEqual(Packet.decode(wire(seq)).seq, seq)

    def test_encoder_rejects_range_and_noninteger_fields(self):
        for seq in (-1, 256, True, 1.0):
            with self.assertRaises(ValueError):
                Packet(seq, [0] * 7)
        for band in (-1, 5, True, 1.0):
            with self.assertRaises(ValueError):
                Packet(0, [band] + [0] * 6)
        for bands in ([], [0] * 6, [0] * 8):
            with self.assertRaises(ValueError):
                Packet(0, bands)

    def test_byte_decoder_rejects_nonbytes(self):
        for payload in (None, [0] * 9, "000000000", 9):
            with self.assertRaises(ValueError):
                Packet.decode(payload)

    def test_packet_freezes_caller_owned_bands(self):
        bands = [0] * 7
        packet = Packet(0, bands)
        bands[0] = 4
        self.assertEqual(packet.bands, (0,) * 7)
        with self.assertRaises(FrozenInstanceError):
            packet.seq = 8

    def test_legal_byte_corruption_cannot_be_detected(self):
        payload = bytearray(wire())
        payload[1] ^= 1
        self.assertEqual(Packet.decode(payload).bands, (0, 1, 1, 1, 1, 1, 1))


class ReceiverTests(unittest.TestCase):
    def test_startup_has_no_logical_guidance(self):
        state = ReceiverModel().snapshot()
        self.assertEqual(state["status"], "awaiting_packet")
        self.assertEqual(state["bands"], [0] * 7)
        self.assertEqual(state["highlight"], 255)

    def test_timeout_exact_boundary_and_recovery(self):
        receiver = ReceiverModel()
        receiver.receive(wire(5, highlight=3), 50)
        self.assertEqual(receiver.advance(549)["status"], "active")
        self.assertEqual(receiver.advance(550)["status"], "failsafe_timeout")
        self.assertEqual(receiver.snapshot()["highlight"], 255)
        self.assertEqual(receiver.snapshot()["bands"], [0] * 7)
        receiver.advance(1000)
        self.assertEqual(receiver.counts["timeouts"], 1)
        self.assertTrue(receiver.receive(wire(0), 1000)["accepted"])
        self.assertEqual(receiver.status, "active")

    def test_timeout_is_configurable_but_default_is_500(self):
        self.assertEqual(ModelConfig().timeout_ms, 500)
        receiver = ReceiverModel(ModelConfig(timeout_ms=100))
        receiver.receive(wire(), 0)
        self.assertEqual(receiver.advance(100)["status"], "failsafe_timeout")

    def test_invalid_traffic_does_not_refresh_timeout(self):
        receiver = ReceiverModel()
        receiver.receive(wire(), 0)
        for now in range(100, 500, 100):
            self.assertFalse(receiver.receive(b"bad", now)["accepted"])
        self.assertEqual(receiver.last_received_ms, 0)
        self.assertEqual(receiver.advance(500)["bands"], [0] * 7)

    def test_monotonic_time_is_required_everywhere(self):
        for action in (lambda r: r.advance(9), lambda r: r.receive(wire(), 9),
                       lambda r: r.set_connected(False, 9)):
            receiver = ReceiverModel()
            receiver.advance(10)
            with self.assertRaises(ValueError):
                action(receiver)
            self.assertEqual(receiver.now_ms, 10)
        for time in (-1, True, 1.5):
            with self.assertRaises(ValueError):
                ReceiverModel().advance(time)

    def test_equal_time_is_allowed_for_atomic_events(self):
        receiver = ReceiverModel()
        receiver.receive(wire(), 0)
        receiver.receive(wire(1), 0)
        self.assertEqual(receiver.last_seq, 1)

    def test_wrap_and_short_forward_gap(self):
        receiver = ReceiverModel()
        for i, seq in enumerate((254, 255, 0, 1)):
            result = receiver.receive(wire(seq), i * 100)
            self.assertEqual(result["sequence"], "first" if i == 0 else "expected")
        result = receiver.receive(wire(4), 400)
        self.assertEqual(result["sequence"], "forward_gap")
        self.assertEqual(receiver.counts["possible_missing_packets"], 2)

    def test_observe_policy_exposes_duplicate_and_backward_risk(self):
        receiver = ReceiverModel()
        receiver.receive(wire(5), 0)
        self.assertTrue(receiver.receive(wire(5, [2] * 7), 100)["accepted"])
        self.assertTrue(receiver.receive(wire(4, [3] * 7), 200)["accepted"])
        self.assertEqual(receiver.bands, (3,) * 7)
        self.assertEqual(receiver.last_received_ms, 200)

    def test_forward_only_rejects_ambiguous_half_range(self):
        for seq in (0, 128, 255):
            with self.subTest(seq=seq):
                receiver = ReceiverModel(ModelConfig(sequence_policy="forward_only"))
                receiver.receive(wire(0), 0)
                self.assertFalse(receiver.receive(wire(seq, [4] * 7), 100)["accepted"])
                self.assertEqual(receiver.bands, (1,) * 7)
                self.assertEqual(receiver.last_received_ms, 0)

    def test_forward_only_accepts_delta_127_but_does_not_prove_freshness(self):
        receiver = ReceiverModel(ModelConfig(sequence_policy="forward_only"))
        receiver.receive(wire(0), 0)
        self.assertTrue(receiver.receive(wire(127), 100)["accepted"])
        self.assertEqual(receiver.counts["possible_missing_packets"], 126)

    def test_sender_restart_can_recover_after_timeout(self):
        receiver = ReceiverModel(ModelConfig(sequence_policy="forward_only"))
        receiver.receive(wire(5), 0)
        self.assertFalse(receiver.receive(wire(0), 100)["accepted"])
        receiver.advance(500)
        self.assertEqual(receiver.receive(wire(0), 600)["sequence"], "first")

    def test_256_sequence_values_cannot_encode_absolute_age(self):
        # An old sequence-1 packet and a newly wrapped sequence-1 packet are
        # byte-identical: neither sequence mode can establish absolute age.
        old = wire(1, [3] * 7)
        new = wire((1 + 256) % 256, [3] * 7)
        self.assertEqual(old, new)
        receiver = ReceiverModel(ModelConfig(sequence_policy="forward_only"))
        receiver.receive(wire(0), 0)
        self.assertTrue(receiver.receive(old, 100)["accepted"])

    def test_disconnect_clears_and_blocks_then_reconnect_waits(self):
        receiver = ReceiverModel()
        receiver.receive(wire(10, highlight=3), 0)
        receiver.set_connected(False, 10)
        self.assertEqual(receiver.bands, (0,) * 7)
        self.assertEqual(receiver.highlight, 255)
        self.assertFalse(receiver.receive(wire(11), 20)["accepted"])
        receiver.set_connected(True, 30)
        self.assertEqual(receiver.status, "awaiting_packet")
        self.assertEqual(receiver.bands, (0,) * 7)
        self.assertTrue(receiver.receive(wire(0), 40)["accepted"])

    def test_changed_bands_have_explicit_nominal_gap_phase(self):
        receiver = ReceiverModel()
        receiver.receive(wire(0), 0)
        receiver.receive(wire(1, [4] * 7), 200)
        column = receiver.snapshot()["columns"][0]
        self.assertEqual((column["phase"], column["nominal_command_degrees"]), ("gap_requested", 29.0))
        self.assertEqual(receiver.advance(239)["columns"][0]["phase"], "gap_requested")
        self.assertEqual(receiver.advance(240)["columns"][0]["phase"], "band_requested")
        self.assertEqual(receiver.advance(360)["columns"][0]["phase"], "hold_assumed")
        self.assertEqual(receiver.snapshot()["columns"][0]["physical_pin_state"], "NOT MEASURED")

    def test_repeated_band_command_does_not_restart_reference_settling(self):
        receiver = ReceiverModel()
        receiver.receive(wire(0), 0)
        receiver.receive(wire(1), 100)
        self.assertEqual(receiver.advance(120)["columns"][0]["phase"], "hold_assumed")

    def test_clear_uses_last_band_gap_without_claiming_actual_return(self):
        receiver = ReceiverModel()
        receiver.receive(wire(0, [4] * 7), 0)
        receiver.receive(wire(1, [0] * 7), 200)
        state = receiver.snapshot()
        self.assertEqual(state["columns"][0]["nominal_command_degrees"], 146.0)
        self.assertEqual(state["columns"][0]["phase"], "neutral_requested")
        self.assertEqual(state["logical_pin_selection"], [[0] * 4] * 7)

    def test_highlight_empty_column_does_not_invent_a_pin_or_tap(self):
        receiver = ReceiverModel()
        receiver.receive(wire(0, [0] * 7, 3), 0)
        state = receiver.snapshot()
        self.assertEqual(state["bands"], [0] * 7)
        self.assertTrue(state["columns"][3]["highlight_requested"])
        self.assertIsNone(state["columns"][3]["nominal_tap_dip_degrees"])

    def test_nominal_angles_and_tap_directions_are_reference_only(self):
        self.assertEqual([gap_for_band(b) for b in (1, 2, 3, 4)], [29.0, 29.0, 146.0, 146.0])
        self.assertEqual([tap_dip_angle(b) for b in (1, 2, 3, 4)], [13.0, 45.0, 130.0, 162.0])
        with self.assertRaises(ValueError):
            tap_dip_angle(0)

    def test_snapshot_is_not_a_mutable_backdoor(self):
        receiver = ReceiverModel()
        receiver.receive(wire(), 0)
        state = receiver.snapshot()
        state["bands"][0] = 4
        state["counts"]["accepted"] = 100
        self.assertEqual(receiver.bands, (1,) * 7)
        self.assertEqual(receiver.counts["accepted"], 1)

    def test_invalid_model_configuration_rejected(self):
        for kwargs in ({"timeout_ms": 0}, {"gap_ms": -1}, {"settle_ms": 1.2},
                       {"sequence_policy": "guess"}):
            with self.assertRaises(ValueError):
                ModelConfig(**kwargs)


class SyntheticInputTests(unittest.TestCase):
    def frame(self, **changes):
        frame = {"captured_ms": 0, "tracking": True, "distances_m": [0.5] * 7, "targets": []}
        frame.update(changes)
        return frame

    def test_band_interval_edges(self):
        values = (0.3, 0.899999, 0.9, 1.599999, 1.6, 2.499999, 2.5, 4.0, 4.000001)
        self.assertEqual([distance_band(x) for x in values], [1, 1, 2, 2, 3, 3, 4, 4, 0])

    def test_close_policy_is_explicit_and_configurable(self):
        self.assertEqual(distance_band(0.1), 1)
        self.assertEqual(distance_band(0.1, InputPolicy(close_policy="none")), 0)

    def test_unknown_depth_is_not_a_free_space_claim(self):
        for value in (None, float("nan"), float("inf"), -float("inf"), -1, 0):
            self.assertEqual(distance_band(value), 0)
        for value in ("0.5", True):
            with self.assertRaises(ValueError):
                distance_band(value)

    def test_tracking_loss_clears_bands_and_highlight(self):
        frame = self.frame(tracking=False, targets=[{"observed_ms": 0, "bearing_degrees": 0}])
        packet, evidence = encode_synthetic_frame(frame, 0, 0)
        self.assertEqual(packet.bands, (0,) * 7)
        self.assertEqual(packet.highlight, 255)
        self.assertEqual(evidence["upstream_policy"], "tracking_lost")

    def test_depth_freshness_boundary(self):
        self.assertEqual(encode_synthetic_frame(self.frame(), 250, 0)[0].bands, (1,) * 7)
        self.assertEqual(encode_synthetic_frame(self.frame(), 251, 0)[0].bands, (0,) * 7)

    def test_future_timestamps_rejected(self):
        with self.assertRaises(ValueError):
            encode_synthetic_frame(self.frame(captured_ms=1), 0, 0)
        with self.assertRaises(ValueError):
            encode_synthetic_frame(self.frame(targets=[{"observed_ms": 1, "bearing_degrees": 0}]), 0, 0)

    def test_delayed_target_cannot_restore_old_highlight(self):
        frame = self.frame(captured_ms=300, targets=[{"observed_ms": 0, "bearing_degrees": 0}])
        packet, evidence = encode_synthetic_frame(frame, 300, 0)
        self.assertEqual(packet.highlight, 255)
        self.assertEqual(packet.bands, (1,) * 7)
        self.assertIn("stale_target_ignored", evidence["target_policy"])

    def test_target_loss_and_conflict_do_not_change_obstacles(self):
        for targets in ([], [{"observed_ms": 0, "bearing_degrees": -20},
                             {"observed_ms": 0, "bearing_degrees": 20}]):
            packet, _ = encode_synthetic_frame(self.frame(targets=targets), 0, 0)
            self.assertEqual(packet.highlight, 255)
            self.assertEqual(packet.bands, (1,) * 7)

    def test_bearing_boundaries_and_out_of_field_of_view(self):
        self.assertEqual(bearing_column(-45), 0)
        self.assertEqual(bearing_column(0), 3)
        self.assertEqual(bearing_column(45), 6)
        self.assertIsNone(bearing_column(-45.001))
        self.assertIsNone(bearing_column(45.001))
        for value in (float("nan"), float("inf"), True, "0"):
            with self.assertRaises(ValueError):
                bearing_column(value)

    def test_synthetic_pose_is_metadata_not_an_arkit_transform(self):
        pose = {"yaw_degrees": 90, "x_m": 1, "z_m": 2}
        packet, evidence = encode_synthetic_frame(self.frame(pose=pose), 0, 0)
        self.assertEqual(packet.bands, (1,) * 7)
        self.assertEqual(evidence["pose_metadata_only"], pose)

    def test_input_configuration_and_shape_validation(self):
        for kwargs in ({"fov_degrees": 0}, {"fov_degrees": True}, {"fov_degrees": math.nan},
                       {"depth_max_age_ms": -1}, {"target_max_age_ms": 1.5}, {"close_policy": "guess"}):
            with self.assertRaises(ValueError):
                InputPolicy(**kwargs)
        with self.assertRaises(ValueError):
            encode_synthetic_frame(self.frame(distances_m=[1] * 6), 0, 0)
        with self.assertRaises(ValueError):
            encode_synthetic_frame(self.frame(tracking="yes"), 0, 0)


class ReplayTests(unittest.TestCase):
    def fixture(self):
        return json.loads((ROOT / "fixtures/scenarios.json").read_text())

    def test_empty_suites_events_and_expectations_are_rejected(self):
        mutations = (
            lambda f: f.update(scenarios=[]),
            lambda f: f["scenarios"][0].update(events=[]),
            lambda f: f["scenarios"][0]["events"][0].update(expect={}),
            lambda f: f["scenarios"][0]["events"][0].update(expect={"state": {}}),
            lambda f: f["scenarios"][0]["events"][0].update(expect={"state": {"counts": {}}}),
        )
        for mutate in mutations:
            fixture = self.fixture()
            mutate(fixture)
            with self.assertRaises(ValueError):
                validate_suite(fixture)

    def test_empty_fixture_cannot_generate_a_passing_report(self):
        fixture = self.fixture()
        fixture["scenarios"] = []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "empty.json"
            path.write_text(json.dumps(fixture))
            with self.assertRaises(ValueError):
                run_suite(path)

    def test_schema_ids_time_and_event_shape_are_checked(self):
        mutations = (
            lambda f: f.update(schema_version=2),
            lambda f: f["scenarios"].append(f["scenarios"][0]),
            lambda f: f["scenarios"][0]["events"][1].update(time_ms=-1),
            lambda f: f["scenarios"][0]["events"][2].update(time_ms=1),
            lambda f: f["scenarios"][0]["events"][0].update(kind="invented"),
            lambda f: f["scenarios"][0]["events"][0].update(expect={"wrong": 1}),
        )
        for mutate in mutations:
            fixture = self.fixture()
            mutate(fixture)
            with self.assertRaises(ValueError):
                validate_suite(fixture)

    def test_every_scenario_matches_hand_authored_expectations(self):
        report = run_suite()
        failures = [f"{s['id']} / {step['label']}: {step['failures']}"
                    for s in report["scenarios"] for step in s["trace"] if not step["passed"]]
        self.assertEqual(failures, [])
        self.assertEqual(report["scenario_count"], 18)
        self.assertEqual(report["event_count"], 77)

    def test_wrong_nominal_command_phases_fail_replay(self):
        def broken_view(column, now_ms, config):
            return {"target_band": column.target, "phase": "neutral_requested",
                    "nominal_command_degrees": 999.0, "physical_pin_state": "NOT MEASURED"}
        with patch("validation.feel_model.ColumnCommand.view", broken_view):
            report = run_suite()
        scenario = next(s for s in report["scenarios"] if s["id"] == "nominal_gap_transition")
        self.assertFalse(report["passed"])
        self.assertFalse(scenario["passed"])
        self.assertEqual(sum(not e["passed"] for e in scenario["trace"]), 5)

    def test_replay_is_byte_deterministic(self):
        self.assertEqual(json.dumps(run_suite(), sort_keys=True), json.dumps(run_suite(), sort_keys=True))

    def test_loss_fixture_matches_declared_seed(self):
        fixture = json.loads((ROOT / "fixtures/scenarios.json").read_text())
        scenario = next(s for s in fixture["scenarios"] if s["id"] == "seeded_packet_loss")
        rng = random.Random(fixture["seed"])
        self.assertEqual([e["kind"] == "drop" for e in scenario["events"][1:-1]],
                         [rng.random() < 0.4 for _ in range(12)])

    def test_logical_single_pin_invariant_across_all_traces(self):
        for scenario in run_suite()["scenarios"]:
            for event in scenario["trace"]:
                for column in event["state"]["logical_pin_selection"]:
                    self.assertLessEqual(sum(column), 1)

    def test_wrong_fixture_expectation_is_reported(self):
        self.assertEqual(compare({"state": {"bands": [4]}}, {"state": {"bands": [1]}}),
                         ["state.bands: expected [4], got [1]"])
        self.assertTrue(compare({"missing": 1}, {}))

    def test_html_is_self_contained_trace_not_second_protocol_model(self):
        report = run_suite()
        page = render_html(report)
        self.assertIn("SIMULATION", page)
        self.assertIn(report["fixture_sha256"], page)
        self.assertNotIn("<script src=", page)
        self.assertNotIn("fetch(", page)
        self.assertNotIn("navigator.bluetooth", page)
        self.assertNotIn("navigator.serial", page)

    def test_html_escapes_script_terminators_in_fixture_text(self):
        report = run_suite()
        report["fixture_provenance"] = "</script><script>alert(1)</script>"
        page = render_html(report)
        self.assertNotIn(report["fixture_provenance"], page)
        self.assertIn("\\u003c/script\\u003e", page)


if __name__ == "__main__":
    unittest.main()
