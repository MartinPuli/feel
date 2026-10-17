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
struct State {
    bool armed = false;
    bool active = false;
    bool exercise = false;
    uint32_t armedAt = 0;
    uint32_t startedAt = 0;
    uint32_t keptAt = 0;
    void stop() { armed = false; active = false; exercise = false; }
    unsigned pulseUs(uint32_t now) const {
        if (!active) return 0;
        if (!exercise) return kCenterUs;
        const uint32_t phase = uint32_t(now - startedAt) / 500;
        if (phase == 0 || phase >= 9) return kCenterUs;
        return phase % 2 ? 1450 : 1550;
    }
    void tick(uint32_t now) {
        if (active && (uint32_t(now - startedAt) >= (exercise ? kExerciseMs : kMaximumRunMs) ||
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
