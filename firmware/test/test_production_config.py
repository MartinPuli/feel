#!/usr/bin/env python3
"""SYNTHETIC software fixtures only; no real measurement records or uploads."""
from contextlib import redirect_stdout
import copy
import importlib.util
import hashlib
import io
import json
from pathlib import Path
import runpy
import shutil
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

FIRMWARE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("production_config", FIRMWARE / "tools/production_config.py")
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class HookError(Exception):
    pass


class FakeEnvironment(dict):
    def __init__(self, project):
        super().__init__(PROJECT_DIR=str(project))
        self.appended = []

    def Append(self, **kwargs):
        self.appended.append(kwargs)


class ProductionConfigTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="feel-synthetic-measurements-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        (self.base / "SYNTHETIC-EVIDENCE.txt").write_text(
            "SYNTHETIC TEST DATA ONLY. No physical measurement or production readiness.\n")
        self.path = self.base / config.CONFIG_NAME
        deployment = FIRMWARE / config.CONFIG_NAME
        self.deployment_before = hashlib.sha256(deployment.read_bytes()).hexdigest() if deployment.exists() else None
        self.record = {
            "schema_version": 2, "design_profile": "fs0307-assumed175-even-v4", "board": "esp32-classic", "verified": True,
            "verified_by": "SYNTHETIC_TEST_ONLY", "verified_at": "2026-10-16T12:00:00Z",
            "evidence_file": "SYNTHETIC-EVIDENCE.txt",
            "servos": [{"column": column, "gpio": gpio, "unit_id": "SYNTHETIC-" + str(column),
                        "verified": True, "measured_min_us": 600, "measured_max_us": 2600,
                        "evidence_file": "SYNTHETIC-EVIDENCE.txt"}
                       for column, gpio in enumerate(config.GPIO_BY_COLUMN) if column > 0]}

    def write(self, document=None):
        self.path.write_text(json.dumps(self.record if document is None else document))

    def reject(self, document):
        self.write(document)
        with self.assertRaises(config.MeasurementError):
            config.load_measurements(self.path)

    def hook(self):
        (self.base / "tools").mkdir(exist_ok=True)
        shutil.copyfile(FIRMWARE / "tools/production_config.py", self.base / "tools/production_config.py")
        env = FakeEnvironment(self.base)
        self.last_env = env
        errors = types.ModuleType("SCons.Errors")
        errors.UserError = HookError
        with patch.dict(sys.modules, {"SCons": types.ModuleType("SCons"), "SCons.Errors": errors}):
            with redirect_stdout(io.StringIO()):
                runpy.run_path(str(FIRMWARE / "tools/production_setup.py"),
                               init_globals={"env": env, "Import": lambda name: None})
        return env

    def test_missing_config(self):
        with self.assertRaisesRegex(config.MeasurementError, "Missing.*Six measured"):
            config.load_measurements(self.path)

    def test_tracked_template_is_unverified(self):
        with self.assertRaisesRegex(config.MeasurementError, "verified must be true"):
            config.load_measurements(FIRMWARE / "production-measurements.example.json")

    def test_valid_synthetic_records_use_service_envelope(self):
        self.write()
        result = config.load_measurements(self.path)
        self.assertEqual((result["minimum_us"], result["maximum_us"], result["columns"]), (650,2500,6))
        self.assertEqual(len(result["sha256"]), 64)

    def test_exact_boundaries_and_column_order(self):
        for servo in self.record["servos"]:
            servo["measured_min_us"] = 650
            servo["measured_max_us"] = 2500
        self.record["servos"].reverse()
        self.write()
        self.assertEqual(config.load_measurements(self.path)["columns"], 6)

    def test_missing_extra_duplicate_or_invalid_columns(self):
        for columns in ([0,1,2,3,4,5], [0,1,2,3,4,5,6,6], [0,1,2,3,4,5,5],
                        [0,1,2,3,4,5,7], [True,1,2,3,4,5,6]):
            document = copy.deepcopy(self.record)
            document["servos"] = [dict(document["servos"][min(i,5)], column=value) for i,value in enumerate(columns)]
            with self.subTest(columns=columns): self.reject(document)

    def test_missing_or_wrong_gpio(self):
        for gpio in (None,32,True):
            document = copy.deepcopy(self.record);document["servos"][0]["gpio"] = gpio
            with self.subTest(gpio=gpio): self.reject(document)

    def test_ranges_must_cover_entire_service_envelope(self):
        for minimum,maximum in ((651,2500),(650,2499),(2500,650),(0,2200),(800,20000),
                                (None,2500),(650,None),(True,2500),(650,2500.0)):
            document = copy.deepcopy(self.record)
            document["servos"][5].update(measured_min_us=minimum,measured_max_us=maximum)
            with self.subTest(limits=(minimum,maximum)): self.reject(document)

    def test_unique_nonempty_unit_ids(self):
        for unit in (None,"", "  ", "SYNTHETIC-1"):
            document = copy.deepcopy(self.record);document["servos"][1]["unit_id"] = unit
            with self.subTest(unit=unit): self.reject(document)

    def test_attestations_and_timestamp_required(self):
        for field,value in (("verified",False),("verified",1),("verified_by",None),
                            ("verified_at",None),("verified_at","2026-10-16"),
                            ("verified_at","yesterday"),("board","esp32s3"),("schema_version",True),("schema_version",1),
                            ("design_profile",None),("design_profile","fs0307-120-v2"),("design_profile","fs0307-assumed175-v3")):
            document = copy.deepcopy(self.record);document[field] = value
            with self.subTest(field=field,value=value): self.reject(document)
        document = copy.deepcopy(self.record);document["servos"][4]["verified"] = False
        self.reject(document)

    def test_evidence_must_exist_and_not_be_empty(self):
        (self.base / "empty.txt").write_text("")
        for value in (None,"missing.txt","empty.txt"):
            document = copy.deepcopy(self.record);document["evidence_file"] = value
            with self.subTest(global_evidence=value): self.reject(document)
            document = copy.deepcopy(self.record);document["servos"][5]["evidence_file"] = value
            with self.subTest(servo_evidence=value): self.reject(document)

    def test_duplicate_json_keys_and_nonfinite_values_rejected(self):
        for data in ('{"verified":false,"verified":true}', '{"value":NaN}', 'not JSON'):
            self.path.write_text(data)
            with self.subTest(data=data), self.assertRaises(config.MeasurementError):
                config.load_measurements(self.path)

    def test_hook_refuses_missing_and_invalid_config(self):
        with self.assertRaisesRegex(HookError,"FEEL PRODUCTION BLOCKED"):
            self.hook()
        self.assertEqual(self.last_env.appended, [])
        self.record["verified"] = False;self.write()
        with self.assertRaisesRegex(HookError,"FEEL PRODUCTION BLOCKED"):
            self.hook()
        self.assertEqual(self.last_env.appended, [])

    def test_hook_injects_only_after_synthetic_validation(self):
        self.write();env = self.hook()
        self.assertEqual(env.appended, [{"CPPDEFINES": [
            ("FEEL_ENABLE_SERVO_OUTPUT",1),("FEEL_VERIFIED_PULSE_MIN_US",650),
            ("FEEL_VERIFIED_PULSE_MAX_US",2500),("FEEL_PRODUCTION_MEASUREMENTS_LOADED",1)]}])
        deployment = FIRMWARE / config.CONFIG_NAME
        after = hashlib.sha256(deployment.read_bytes()).hexdigest() if deployment.exists() else None
        self.assertEqual(after, self.deployment_before,
                         "Synthetic tests must never create or change deployment measurements")


if __name__ == "__main__":
    unittest.main(verbosity=2)
