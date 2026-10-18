#pragma once
#include <cstdint>
#include <cstring>

namespace single_servo {
// Nominal center from the FS0307 datasheet; NOT a measured safe travel range.
constexpr unsigned kCenterUs = 1500;
constexpr uint32_t kArmMs = 10000;
constexpr uint32_t kWatchdogMs = 250;
constexpr uint32_t kMaximumRunMs = 1000;
constexpr uint32_t kExerciseMs = 5000;
// Travel sweep: from center, one 50 us step every 500 ms toward an end, until the user STOPs.
// The limits are generous on purpose (Pololu measured ~180 deg at 650..2500 us); the user
// stops at the first buzz or stall, and reads the last pulse from STATUS.
constexpr unsigned kSweepStepUs = 50;
constexpr uint32_t kSweepStepMs = 500;
constexpr uint32_t kSweepSettleMs = 1000;
constexpr unsigned kSweepLowUs = 500;
constexpr unsigned kSweepHighUs = 2500;
constexpr uint32_t kSweepMs = kSweepSettleMs + kSweepStepMs * ((kSweepHighUs - kCenterUs) / kSweepStepUs + 1);
struct State {
    bool armed = false;
    bool active = false;
    bool exercise = false;
    int sweep = 0; // 0 = none, +1 toward kSweepHighUs, -1 toward kSweepLowUs
    uint32_t armedAt = 0;
    uint32_t startedAt = 0;
    uint32_t keptAt = 0;
    void stop() { armed = false; active = false; exercise = false; sweep = 0; }
    unsigned pulseUs(uint32_t now) const {
        if (!active) return 0;
        if (sweep) {
            const uint32_t elapsed = uint32_t(now - startedAt);
            if (elapsed < kSweepSettleMs) return kCenterUs;
            const unsigned steps = (elapsed - kSweepSettleMs) / kSweepStepMs + 1;
            const unsigned offset = steps * kSweepStepUs;
            if (sweep > 0) return kCenterUs + offset > kSweepHighUs ? kSweepHighUs : kCenterUs + offset;
            return offset >= kCenterUs - kSweepLowUs ? kSweepLowUs : kCenterUs - offset;
        }
        if (!exercise) return kCenterUs;
        const uint32_t phase = uint32_t(now - startedAt) / 500;
        if (phase == 0 || phase >= 9) return kCenterUs;
        return phase % 2 ? 1450 : 1550;
    }
    void tick(uint32_t now) {
        if (active && (uint32_t(now - startedAt) >= (sweep ? kSweepMs : exercise ? kExerciseMs : kMaximumRunMs) ||
                       uint32_t(now - keptAt) >= kWatchdogMs)) stop();
        if (armed && uint32_t(now - armedAt) >= kArmMs) stop();
    }
    bool command(const char* text, uint32_t now) {
        tick(now); // Expired motion cannot be revived by KEEP.
        if (!std::strcmp(text, "STOP")) { stop(); return true; }
        if (!std::strcmp(text, "STATUS")) return true;
        if (!std::strcmp(text, "ARM") && !active) {
            armed = true; armedAt = now; return true;
        }
        if ((!std::strcmp(text, "SWEEP 1") || !std::strcmp(text, "SWEEP 0")) && armed && !active) {
            sweep = text[6] == '1' ? 1 : -1;
            armed = false; active = true; startedAt = keptAt = now; return true;
        }
        if ((!std::strcmp(text, "CENTER") || !std::strcmp(text, "TEST5")) && armed && !active) {
            exercise = !std::strcmp(text, "TEST5");
            armed = false; active = true; startedAt = keptAt = now; return true;
        }
        if (!std::strcmp(text, "KEEP") && active) { keptAt = now; return true; }
        stop(); // Unknown or out-of-order command is fail-closed.
        return false;
    }
};
}
