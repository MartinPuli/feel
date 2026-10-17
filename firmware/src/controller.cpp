#include "feel/controller.hpp"

#include <algorithm>
#include <cmath>

namespace feel {
const char* resultName(Result result) {
    switch (result) {
    case Result::Ok: return "ok";
    case Result::BadLength: return "bad_length";
    case Result::BadBand: return "bad_band";
    case Result::BadHighlight: return "bad_highlight";
    case Result::Disconnected: return "disconnected";
    case Result::Duplicate: return "duplicate";
    case Result::StaleSequence: return "stale_sequence";
    case Result::BenchLocked: return "bench_locked";
    case Result::NotArmed: return "not_armed";
    case Result::BadColumn: return "bad_column";
    case Result::BadOffset: return "bad_offset";
    case Result::BadPulse: return "bad_pulse";
    case Result::NoActiveCommand: return "no_active_command";
    case Result::BadCommand: return "bad_command";
    case Result::SaveRequested: return "save_requested";
    }
    return "unknown";
}

Result decodePacket(const uint8_t* data, std::size_t length, Packet& output) {
    if (length != kPacketBytes || data == nullptr) return Result::BadLength;
    Packet candidate;
    candidate.sequence = data[0];
    for (std::size_t i = 0; i < kColumns; ++i) {
        if (data[i + 1] > 4) return Result::BadBand;
        candidate.bands[i] = data[i + 1];
    }
    if (data[8] >= kColumns && data[8] != kNoHighlight) return Result::BadHighlight;
    candidate.highlight = data[8];
    output = candidate;
    return Result::Ok;
}

std::array<uint8_t, kPacketBytes> encodePacket(const Packet& packet) {
    std::array<uint8_t, kPacketBytes> bytes{};
    bytes[0] = packet.sequence;
    for (std::size_t i = 0; i < kColumns; ++i) bytes[i + 1] = packet.bands[i];
    bytes[8] = packet.highlight;
    return bytes;
}

float bandAngle(uint8_t band) {
    return band >= 1 && band <= 4 ? kBandAnglesDeg[band - 1] : kDefaultNeutralDeg;
}

float nearestGap(float angle) {
    float best = kGapAnglesDeg[0];
    for (float gap : kGapAnglesDeg) {
        if (std::fabs(gap - angle) < std::fabs(best - angle)) best = gap;
    }
    return best;
}

uint16_t angleToPulse(float degrees) {
    const float clamped = std::max(kMinAngleDeg, std::min(kMaxAngleDeg, degrees));
    return static_cast<uint16_t>(std::lround(kMinPulseUs + (clamped - kMinAngleDeg) *
        static_cast<float>(kMaxPulseUs - kMinPulseUs) / kAngleSpanDeg));
}

Controller::Controller() {
    neutral_.fill(kDefaultNeutralDeg);
    updateOutput(0);
}

void Controller::neutralize() {
    // Use the last selected band's adjacent gap, not a sweep to one end null.
    // Crossing other bands during large transitions is physically unavoidable.
    state_.bands.fill(0);
    state_.highlight = kNoHighlight;
    state_.active = false;
    state_.sequenceValid = false;
    state_.rawPulse = false;
    state_.tapActive = false;
}

void Controller::connect(uint32_t now) {
    neutralize();
    state_.benchArmed = false;
    state_.connected = true;
    updateOutput(now);
}

void Controller::disconnect(uint32_t now) {
    neutralize();
    state_.benchArmed = false;
    state_.connected = false;
    updateOutput(now);
}

void Controller::stop(uint32_t now) {
    neutralize();
    state_.benchArmed = false;
    updateOutput(now);
}

void Controller::tick(uint32_t now) {
    if (state_.benchArmed && static_cast<uint32_t>(now - armEpochMs_) >= kBenchArmMs) {
        neutralize();
        state_.benchArmed = false;
        ++state_.timeouts;
    }
    if (state_.active && static_cast<uint32_t>(now - lastCommandMs_) >= kWatchdogMs) {
        neutralize();
        ++state_.timeouts;
    }
    updateOutput(now);
}

Result Controller::reject(Result result) {
    ++state_.rejected;
    return result;
}

void Controller::apply(const std::array<uint8_t, kColumns>& bands,
                       uint8_t highlight, uint32_t now) {
    const uint8_t effective = highlight < kColumns && bands[highlight] != 0 ?
        highlight : kNoHighlight;
    const bool differentTarget = effective != state_.highlight ||
        (effective < kColumns && bands[effective] != state_.bands[effective]);
    if (differentTarget) tapEpochMs_ = now;
    for (std::size_t i = 0; i < kColumns; ++i) {
        if (bands[i] != 0) neutral_[i] = nearestGap(bandAngle(bands[i]));
    }
    state_.bands = bands;
    state_.highlight = effective;
    state_.rawPulse = false;
    state_.active = true;
    lastCommandMs_ = now;
    updateOutput(now);
}

Result Controller::receive(const uint8_t* data, std::size_t length, uint32_t now) {
    tick(now); // Expiry resets sequence baseline even if no separate tick ran.
    Packet packet;
    const Result decoded = decodePacket(data, length, packet);
    if (decoded != Result::Ok) return reject(decoded);
    if (!state_.connected) return reject(Result::Disconnected);
    if (state_.benchArmed) return reject(Result::BenchLocked);
    if (state_.sequenceValid) {
        const uint8_t delta = static_cast<uint8_t>(packet.sequence - state_.lastSequence);
        if (delta == 0) return reject(Result::Duplicate);
        if (delta >= 128) return reject(Result::StaleSequence);
    }
    apply(packet.bands, packet.highlight, now);
    state_.lastSequence = packet.sequence;
    state_.sequenceValid = true;
    ++state_.accepted;
    return Result::Ok;
}

Result Controller::arm(uint32_t now) {
    tick(now);
    if (state_.connected) return reject(Result::BenchLocked);
    neutralize();
    state_.benchArmed = true;
    armEpochMs_ = now;
    updateOutput(now);
    return Result::Ok;
}

Result Controller::benchBand(std::size_t column, uint8_t band, uint32_t now) {
    tick(now);
    if (!state_.benchArmed) return reject(Result::NotArmed);
    if (column >= kColumns) return reject(Result::BadColumn);
    if (band > 4) return reject(Result::BadBand);
    auto bands = state_.bands;
    bands[column] = band;
    apply(bands, state_.highlight, now);
    return Result::Ok;
}

Result Controller::benchHighlight(uint8_t column, uint32_t now) {
    tick(now);
    if (!state_.benchArmed) return reject(Result::NotArmed);
    if (column >= kColumns && column != kNoHighlight) return reject(Result::BadHighlight);
    apply(state_.bands, column, now);
    return Result::Ok;
}

Result Controller::benchPulse(std::size_t column, uint16_t pulse, uint32_t now) {
    tick(now);
    if (!state_.benchArmed) return reject(Result::NotArmed);
    if (column >= kColumns) return reject(Result::BadColumn);
    if (pulse < kMinPulseUs || pulse > kMaxPulseUs) return reject(Result::BadPulse);
    // Raw bench mode is exclusive: other columns go neutral, never held stale.
    neutralize();
    rawColumn_ = static_cast<uint8_t>(column);
    rawPulseUs_ = pulse;
    neutral_[column] = nearestGap(kMinAngleDeg + (pulse - kMinPulseUs) * kAngleSpanDeg /
        static_cast<float>(kMaxPulseUs - kMinPulseUs));
    state_.rawPulse = true;
    state_.active = true;
    lastCommandMs_ = now;
    updateOutput(now);
    return Result::Ok;
}

Result Controller::keepAlive(uint32_t now) {
    tick(now);
    if (!state_.benchArmed) return reject(Result::NotArmed);
    if (!state_.active) return reject(Result::NoActiveCommand);
    lastCommandMs_ = now;
    return Result::Ok;
}

Result Controller::loadOffset(std::size_t column, float offset) {
    if (column >= kColumns) return Result::BadColumn;
    if (!std::isfinite(offset) || offset < -kMaxCalibrationOffsetDeg || offset > kMaxCalibrationOffsetDeg) return Result::BadOffset;
    state_.offsets[column] = offset;
    return Result::Ok;
}

Result Controller::calibrate(std::size_t column, float offset, uint32_t now) {
    tick(now);
    if (!state_.benchArmed) return reject(Result::NotArmed);
    const Result result = loadOffset(column, offset);
    if (result != Result::Ok) return reject(result);
    updateOutput(now);
    return result; // Calibration is not a motion keepalive.
}

void Controller::updateOutput(uint32_t now) {
    state_.tapActive = state_.active && state_.highlight < kColumns &&
        static_cast<uint32_t>(now - tapEpochMs_) % kTapPeriodMs < kTapDipMs;
    for (std::size_t i = 0; i < kColumns; ++i) {
        float angle = state_.bands[i] == 0 ? neutral_[i] : bandAngle(state_.bands[i]);
        if (state_.tapActive && state_.highlight == i) angle += neutral_[i] > angle ? kTapAngleDeg : -kTapAngleDeg;
        state_.angles[i] = std::max(kMinAngleDeg, std::min(kMaxAngleDeg, angle + state_.offsets[i]));
        state_.pulses[i] = angleToPulse(state_.angles[i]);
    }
    if (state_.rawPulse) {
        state_.pulses[rawColumn_] = rawPulseUs_;
        state_.angles[rawColumn_] = kMinAngleDeg + (rawPulseUs_ - kMinPulseUs) * kAngleSpanDeg /
            static_cast<float>(kMaxPulseUs - kMinPulseUs);
    }
}
} // namespace feel
