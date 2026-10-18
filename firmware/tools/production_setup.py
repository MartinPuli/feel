"""Production-only PlatformIO gate; no fabricated default measurement records."""
from pathlib import Path
import importlib.util
from SCons.Errors import UserError

Import("env")

project = Path(env["PROJECT_DIR"])
spec = importlib.util.spec_from_file_location("feel_production_config", project / "tools" / "production_config.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
try:
    measurements = validator.load_measurements(project / validator.CONFIG_NAME)
except validator.MeasurementError as exc:
    raise UserError("FEEL PRODUCTION BLOCKED: " + str(exc)) from exc

# The deployed service envelope is the intersection of the nominal design and
# all six supplied measured-safe ranges. Validation requires full coverage.
env.Append(CPPDEFINES=[
    ("FEEL_ENABLE_SERVO_OUTPUT", 1),
    ("FEEL_VERIFIED_PULSE_MIN_US", measurements["minimum_us"]),
    ("FEEL_VERIFIED_PULSE_MAX_US", measurements["maximum_us"]),
    ("FEEL_PRODUCTION_MEASUREMENTS_LOADED", 1),
])
print("FEEL production: six supplied measurement records accepted; config SHA256=" + measurements["sha256"])
print("Record validation is not independent physical verification; compiled waveform and mechanics still require testing.")
