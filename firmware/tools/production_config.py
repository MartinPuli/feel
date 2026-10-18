"""Validate user-supplied physical measurement records, never infer measurements.

Passing validates schema, attestations, evidence-file presence and compatibility;
it cannot independently establish that a physical test actually took place.
"""
from datetime import datetime
import hashlib
import json
from pathlib import Path

GPIO_BY_COLUMN = (None, 33, 25, 26, 27, 14, 13)
NOMINAL_MIN_US = 650
NOMINAL_MAX_US = 2500
CONFIG_NAME = "production-measurements.local.json"


class MeasurementError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise MeasurementError(message)


def text(value, label):
    require(isinstance(value, str) and bool(value.strip()), label + " must be supplied")
    return value.strip()


def evidence(value, base, label):
    name = text(value, label)
    path = Path(name).expanduser()
    if not path.is_absolute():
        path = base / path
    require(path.is_file(), label + " must reference an existing local evidence file")
    require(path.stat().st_size > 0, label + " cannot reference an empty file")


def validate_document(document, base):
    require(isinstance(document, dict), "measurement document must be an object")
    require(type(document.get("schema_version")) is int and document["schema_version"] == 2,
            "schema_version must be2 for the175-degree design")
    require(document.get("design_profile") == "fs0307-assumed175-even-v4",
            "design_profile must be fs0307-assumed175-even-v4; previous records require new verification")
    require(document.get("board") == "esp32-classic", "board must be esp32-classic")
    require(document.get("verified") is True, "verified must be true after the actual physical checks")
    text(document.get("verified_by"), "verified_by")
    stamp = text(document.get("verified_at"), "verified_at")
    try:
        parsed = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError as exc:
        raise MeasurementError("verified_at must be an ISO8601 timestamp with timezone") from exc
    require(parsed.tzinfo is not None, "verified_at must include a timezone")
    evidence(document.get("evidence_file"), base, "evidence_file")
    servos = document.get("servos")
    require(isinstance(servos, list) and len(servos) == 6,
            "servos must contain exactly six measured column records")
    columns = set()
    unit_ids = set()
    for record in servos:
        require(isinstance(record, dict), "each servo record must be an object")
        column = record.get("column")
        require(type(column) is int and 1 <= column < 7, "servo column must be an integer1..6")
        require(column not in columns, "duplicate servo column " + str(column))
        columns.add(column)
        label = "column " + str(column)
        require(type(record.get("gpio")) is int and record["gpio"] == GPIO_BY_COLUMN[column],
                label + " gpio does not match the production board map")
        unit_id = text(record.get("unit_id"), label + " unit_id")
        require(unit_id not in unit_ids, "each measured servo needs a unique unit_id")
        unit_ids.add(unit_id)
        require(record.get("verified") is True, label + " is not verified")
        minimum, maximum = record.get("measured_min_us"), record.get("measured_max_us")
        require(type(minimum) is int and type(maximum) is int,
                label + " needs measured integer pulse limits, not null or assumed values")
        require(0 < minimum < maximum < 20000, label + " measured pulse limits are invalid")
        require(minimum <= NOMINAL_MIN_US and maximum >= NOMINAL_MAX_US,
                label + " measured safe range must include the full assumed650..2500us service envelope")
        evidence(record.get("evidence_file"), base, label + " evidence_file")
    require(columns == set(range(1, 7)), "measured columns1..6 must all be present")
    return {"minimum_us": NOMINAL_MIN_US, "maximum_us": NOMINAL_MAX_US, "columns": 6}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key " + key)
        result[key] = value
    return result


def invalid_constant(value):
    raise MeasurementError("non-finite JSON number " + value)


def load_measurements(path):
    path = Path(path)
    if not path.is_file():
        raise MeasurementError(
            "Missing " + str(path) + ". Six measured servo records are required. "
            "See production-measurements.example.json; do not replace null fields with nominal guesses.")
    try:
        raw = path.read_bytes()
        document = json.loads(raw, object_pairs_hook=unique_object, parse_constant=invalid_constant)
        result = validate_document(document, path.parent)
    except (OSError, UnicodeError, ValueError) as exc:
        if isinstance(exc, MeasurementError):
            raise
        raise MeasurementError("Cannot read measurement records: " + str(exc)) from exc
    result["sha256"] = hashlib.sha256(raw).hexdigest()
    return result
