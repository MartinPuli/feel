"""SIMULATION ONLY: a packet-boundary specification model based on HANDOFF v7.

No serial, Bluetooth, network, GPIO, or real sensor capabilities are present.
Policies absent from the handoff are explicitly collected in ModelConfig.
"""

from dataclasses import dataclass
import math


COLUMNS = 7
NO_HIGHLIGHT = 255
BAND_ANGLES = (0.0, 58.0, 117.0, 175.0)
GAP_ANGLES = (29.0, 87.5, 146.0)


def integer(value, name, minimum=0, maximum=None):
    if type(value) is not int or value < minimum:
        raise ValueError(f"{name} must be an integer >= {minimum}")
    if maximum is not None and value > maximum:
        raise ValueError(f"{name} must be <= {maximum}")
    return value


@dataclass(frozen=True)
class Packet:
    seq: int
    bands: tuple
    highlight: int = NO_HIGHLIGHT

    def __post_init__(self):
        integer(self.seq, "seq", maximum=255)
        if len(self.bands) != COLUMNS:
            raise ValueError("exactly seven bands required")
        for band in self.bands:
            integer(band, "band", maximum=4)
        integer(self.highlight, "highlight", maximum=255)
        if self.highlight not in (*range(COLUMNS), NO_HIGHLIGHT):
            raise ValueError("highlight must be 0..6 or 255")
        object.__setattr__(self, "bands", tuple(self.bands))

    def encode(self):
        return bytes((self.seq, *self.bands, self.highlight))

    @classmethod
    def decode(cls, payload):
        if not isinstance(payload, (bytes, bytearray)) or len(payload) != 9:
            raise ValueError("packet must contain exactly nine bytes")
        return cls(payload[0], tuple(payload[1:8]), payload[8])


@dataclass(frozen=True)
class ModelConfig:
    # 500 ms comes from the handoff. The >= boundary and accepted-receipt clock
    # are model policies pending the real firmware's implementation.
    timeout_ms: int = 500
    sequence_policy: str = "observe"
    gap_ms: int = 40
    settle_ms: int = 120

    def __post_init__(self):
        integer(self.timeout_ms, "timeout_ms", minimum=1)
        integer(self.gap_ms, "gap_ms")
        integer(self.settle_ms, "settle_ms")
        if self.sequence_policy not in ("observe", "forward_only"):
            raise ValueError("sequence_policy must be observe or forward_only")


def gap_for_band(band):
    """Reference choice: nearest nominal gap; a tie selects the lower gap."""
    integer(band, "band", maximum=4)
    if band == 0:
        return GAP_ANGLES[0]  # unmeasured startup neutral, not a wiring value
    angle = BAND_ANGLES[band - 1]
    return min(GAP_ANGLES, key=lambda gap: (abs(gap - angle), gap))


def tap_dip_angle(band):
    """Nominal 21 degree dip toward the reference gap; no tap scheduler."""
    integer(band, "band", minimum=1, maximum=4)
    angle = BAND_ANGLES[band - 1]
    return angle + (21.0 if gap_for_band(band) > angle else -21.0)


@dataclass
class ColumnCommand:
    target: int = 0
    source: int = 0
    changed_ms: int = 0
    neutral_angle: float = GAP_ANGLES[0]

    def select(self, band, now_ms):
        if band == self.target:
            return
        self.source = self.target
        if self.source:
            self.neutral_angle = gap_for_band(self.source)
        self.target = band
        self.changed_ms = now_ms

    def view(self, now_ms, config):
        elapsed = now_ms - self.changed_ms
        if self.target == 0:
            phase = "neutral_requested"
            angle = self.neutral_angle
        elif self.source and elapsed < config.gap_ms:
            phase = "gap_requested"
            angle = self.neutral_angle
        else:
            start = config.gap_ms if self.source else 0
            phase = "band_requested" if elapsed < start + config.settle_ms else "hold_assumed"
            angle = BAND_ANGLES[self.target - 1]
        return {"target_band": self.target, "phase": phase,
                "nominal_command_degrees": angle,
                "physical_pin_state": "NOT MEASURED"}


class ReceiverModel:
    """Decode complete application packets, never simulate a BLE radio.

    Default observe policy records sequence anomalies but accepts all valid
    packets: sequence ordering behavior is not specified by the handoff.
    forward_only is an optional, explicitly synthetic half-range policy.
    """

    def __init__(self, config=None):
        self.config = config or ModelConfig()
        self.now_ms = 0
        self.connected = True
        self.status = "awaiting_packet"
        self.bands = (0,) * COLUMNS
        self.highlight = NO_HIGHLIGHT
        self.last_received_ms = None
        self.last_seq = None
        self.columns = [ColumnCommand() for _ in range(COLUMNS)]
        self.counts = {"accepted": 0, "invalid": 0, "sequence_rejected": 0,
                       "duplicates": 0, "forward_gap_events": 0,
                       "possible_missing_packets": 0, "ambiguous_sequence": 0,
                       "timeouts": 0, "while_disconnected": 0}

    def _clear(self, status):
        self.bands = (0,) * COLUMNS
        self.highlight = NO_HIGHLIGHT
        for column in self.columns:
            column.select(0, self.now_ms)
        self.status = status
        self.last_seq = None

    def advance(self, now_ms):
        integer(now_ms, "now_ms")
        if now_ms < self.now_ms:
            raise ValueError("simulation time must be monotonic")
        self.now_ms = now_ms
        if (self.connected and self.status == "active"
                and self.last_received_ms is not None
                and now_ms - self.last_received_ms >= self.config.timeout_ms):
            self.counts["timeouts"] += 1
            self._clear("failsafe_timeout")
        return self.snapshot()

    def set_connected(self, connected, now_ms):
        if type(connected) is not bool:
            raise ValueError("connected must be a bool")
        self.advance(now_ms)
        self.connected = connected
        self.last_received_ms = None
        self._clear("awaiting_packet" if connected else "disconnected")
        return self.snapshot()

    def receive(self, payload, now_ms):
        self.advance(now_ms)
        try:
            packet = Packet.decode(payload)
        except ValueError as exc:
            self.counts["invalid"] += 1
            return {"accepted": False, "reason": str(exc), "sequence": None}
        if not self.connected:
            self.counts["while_disconnected"] += 1
            return {"accepted": False, "reason": "disconnected", "sequence": None}
        delta = None if self.last_seq is None else (packet.seq - self.last_seq) % 256
        sequence = "first" if delta is None else "expected"
        if delta == 0:
            sequence = "duplicate"
            self.counts["duplicates"] += 1
        elif delta is not None and 2 <= delta <= 127:
            sequence = "forward_gap"
            self.counts["forward_gap_events"] += 1
            self.counts["possible_missing_packets"] += delta - 1
        elif delta is not None and delta >= 128:
            sequence = "ambiguous_backward_or_large_gap"
            self.counts["ambiguous_sequence"] += 1
        if (self.config.sequence_policy == "forward_only"
                and delta is not None and (delta == 0 or delta >= 128)):
            self.counts["sequence_rejected"] += 1
            return {"accepted": False, "reason": "reference sequence policy",
                    "sequence": sequence}
        self.bands = packet.bands
        self.highlight = packet.highlight
        for column, band in zip(self.columns, packet.bands):
            column.select(band, now_ms)
        self.last_seq = packet.seq
        self.last_received_ms = now_ms
        self.status = "active"
        self.counts["accepted"] += 1
        return {"accepted": True, "reason": "valid packet", "sequence": sequence}

    def snapshot(self):
        return {"mode": "SIMULATION — specification model",
                "time_ms": self.now_ms, "connected": self.connected,
                "status": self.status, "bands": list(self.bands),
                "highlight": self.highlight, "last_seq": self.last_seq,
                "last_accepted_receipt_ms": self.last_received_ms,
                "logical_pin_selection": [[int(b == row) for row in range(1, 5)]
                                          for b in self.bands],
                "columns": [{**column.view(self.now_ms, self.config),
                             "highlight_requested": i == self.highlight,
                             "nominal_tap_dip_degrees": tap_dip_angle(column.target)
                             if i == self.highlight and column.target else None}
                            for i, column in enumerate(self.columns)],
                "counts": dict(self.counts)}


@dataclass(frozen=True)
class InputPolicy:
    # These are synthetic upstream choices, not ARKit or production behavior.
    depth_max_age_ms: int = 250
    target_max_age_ms: int = 250
    fov_degrees: float = 90.0
    close_policy: str = "nearest_band"

    def __post_init__(self):
        integer(self.depth_max_age_ms, "depth_max_age_ms")
        integer(self.target_max_age_ms, "target_max_age_ms")
        if (isinstance(self.fov_degrees, bool)
                or not isinstance(self.fov_degrees, (int, float))
                or not math.isfinite(self.fov_degrees)
                or not 0 < self.fov_degrees < 180):
            raise ValueError("synthetic field of view must be between 0 and 180")
        if self.close_policy not in ("nearest_band", "none"):
            raise ValueError("close_policy must be nearest_band or none")


def distance_band(distance, policy=None):
    """Half-open [0.3,0.9), [0.9,1.6), [1.6,2.5), [2.5,4.0] model edges.

    None, NaN, infinities, negative and zero are unknown. Positive <0.3 m
    saturates to band 1 by default. Unknown is NOT evidence of free space.
    """
    policy = policy or InputPolicy()
    if distance is None:
        return 0
    if isinstance(distance, bool) or not isinstance(distance, (int, float)):
        raise ValueError("distance must be a number or null")
    if not math.isfinite(distance) or distance <= 0 or distance > 4.0:
        return 0
    if distance < 0.3:
        return 1 if policy.close_policy == "nearest_band" else 0
    if distance < 0.9:
        return 1
    if distance < 1.6:
        return 2
    if distance < 2.5:
        return 3
    return 4


def bearing_column(bearing_degrees, policy=None):
    policy = policy or InputPolicy()
    if (isinstance(bearing_degrees, bool) or not isinstance(bearing_degrees, (int, float))
            or not math.isfinite(bearing_degrees)):
        raise ValueError("bearing must be a finite number")
    half = policy.fov_degrees / 2
    if not -half <= bearing_degrees <= half:
        return None
    return min(6, int((bearing_degrees + half) / policy.fov_degrees * COLUMNS))


def encode_synthetic_frame(frame, now_ms, seq, policy=None):
    """Already-sectorized synthetic observations -> packet + policy evidence.

    Pose is retained as fixture metadata only. This does not implement ARKit
    transforms, depth projection, confidence filters, object detection, or UWB.
    Conflicting targets suppress highlight; target presence never changes the
    obstacle bands. hl on an empty column is legal but cannot select a pin.
    """
    policy = policy or InputPolicy()
    integer(now_ms, "now_ms")
    integer(frame["captured_ms"], "captured_ms")
    if frame["captured_ms"] > now_ms:
        raise ValueError("synthetic frame cannot come from the future")
    distances = frame["distances_m"]
    if len(distances) != COLUMNS:
        raise ValueError("synthetic frame needs seven sector distances")
    if type(frame["tracking"]) is not bool:
        raise ValueError("tracking must be a bool")
    reason = "synthetic_observations"
    if not frame["tracking"]:
        bands, reason = (0,) * COLUMNS, "tracking_lost"
    elif now_ms - frame["captured_ms"] > policy.depth_max_age_ms:
        bands, reason = (0,) * COLUMNS, "stale_depth"
    else:
        bands = tuple(distance_band(d, policy) for d in distances)
    candidates = []
    target_notes = []
    for target in frame.get("targets", []):
        integer(target["observed_ms"], "target observed_ms")
        if target["observed_ms"] > now_ms:
            raise ValueError("synthetic target cannot come from the future")
        if now_ms - target["observed_ms"] > policy.target_max_age_ms:
            target_notes.append("stale_target_ignored")
            continue
        column = bearing_column(target["bearing_degrees"], policy)
        if column is not None:
            candidates.append(column)
    highlight = NO_HIGHLIGHT
    if reason == "synthetic_observations" and len(candidates) == 1:
        highlight = candidates[0]
        target_notes.append("one_target")
    elif len(candidates) > 1:
        target_notes.append("conflicting_targets_highlight_suppressed")
    else:
        target_notes.append("no_current_target")
    return Packet(seq, bands, highlight), {"upstream_policy": reason,
                                          "target_policy": target_notes,
                                          "pose_metadata_only": frame.get("pose")}
