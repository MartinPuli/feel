#pragma once

#include <array>
#include <cstddef>
#include <cstdint>

namespace feel {
constexpr std::size_t kColumns = 7;
constexpr std::size_t kPacketBytes = 9;
constexpr uint8_t kNoHighlight = 255;
constexpr uint32_t kWatchdogMs = 500;
constexpr uint32_t kTapPeriodMs = 600;
constexpr uint32_t kTapDipMs = 100;
constexpr uint32_t kBenchArmMs = 30000;
// FS0307 175-degree design assumption; actual travel remains unmeasured.
constexpr float kMinAngleDeg = 0.0F;
constexpr float kMaxAngleDeg = 175.0F;
constexpr float kAngleSpanDeg = kMaxAngleDeg - kMinAngleDeg;
constexpr float kBandAnglesDeg[] = {0.0F, 58.0F, 116.0F, 174.0F};
constexpr float kGapAnglesDeg[] = {29.0F, 87.0F, 145.0F};
constexpr float kDefaultNeutralDeg = kGapAnglesDeg[0];
constexpr float kTapAngleDeg = 13.0F;
constexpr float kMaxCalibrationOffsetDeg = 5.0F;
constexpr uint16_t kMinPulseUs = 650;
constexpr uint16_t kMaxPulseUs = 2500;

struct Packet {
    uint8_t sequence = 0;
    std::array<uint8_t, kColumns> bands{};
    uint8_t highlight = kNoHighlight;
};

enum class Result : uint8_t {
    Ok, BadLength, BadBand, BadHighlight, Disconnected, Duplicate, StaleSequence,
    BenchLocked, NotArmed, BadColumn, BadOffset, BadPulse, NoActiveCommand,
    BadCommand, SaveRequested
};

const char* resultName(Result result);
// No partial write to output on malformed input. Empty highlighted bands are
// wire-legal; the controller normalizes their effective highlight to 255.
Result decodePacket(const uint8_t* data, std::size_t length, Packet& output);
std::array<uint8_t, kPacketBytes> encodePacket(const Packet& packet);
float bandAngle(uint8_t band);
float nearestGap(float angle);
uint16_t angleToPulse(float degrees);

struct Snapshot {
    std::array<uint8_t, kColumns> bands{};
    std::array<float, kColumns> angles{};
    std::array<uint16_t, kColumns> pulses{};
    std::array<float, kColumns> offsets{};
    uint8_t highlight = kNoHighlight;
    uint8_t lastSequence = 0;
    bool connected = false;
    bool active = false;
    bool sequenceValid = false;
    bool benchArmed = false;
    bool rawPulse = false;
    bool tapActive = false;
    uint32_t accepted = 0;
    uint32_t rejected = 0;
    uint32_t timeouts = 0;
};

// Single-thread owner. Adapter queues BLE events; only loop() calls this class.
// Times are unsigned millis; all durations use subtraction, including rollover.
class Controller {
public:
    Controller();
    void connect(uint32_t now);
    void disconnect(uint32_t now);
    void stop(uint32_t now);
    void tick(uint32_t now);
    Result receive(const uint8_t* data, std::size_t length, uint32_t now);
    Result arm(uint32_t now);
    Result benchBand(std::size_t column, uint8_t band, uint32_t now);
    Result benchHighlight(uint8_t column, uint32_t now);
    Result benchPulse(std::size_t column, uint16_t pulse, uint32_t now);
    Result keepAlive(uint32_t now);
    Result calibrate(std::size_t column, float offset, uint32_t now);
    // Boot/NVS only: validates finite ±5 degrees; does not arm or refresh timer.
    Result loadOffset(std::size_t column, float offset);
    bool benchArmed() const { return state_.benchArmed; }
    const Snapshot& snapshot() const { return state_; }

private:
    Snapshot state_{};
    std::array<float, kColumns> neutral_{};
    uint32_t lastCommandMs_ = 0;
    uint32_t tapEpochMs_ = 0;
    uint32_t armEpochMs_ = 0;
    uint8_t rawColumn_ = 0;
    uint16_t rawPulseUs_ = kMinPulseUs;
    void neutralize();
    void apply(const std::array<uint8_t, kColumns>& bands, uint8_t highlight, uint32_t now);
    void updateOutput(uint32_t now);
    Result reject(Result result);
};
} // namespace feel
