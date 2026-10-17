#pragma once
#include <cstdint>

namespace feel {
constexpr uint8_t kServoPwmBits = 14;
constexpr uint32_t kServoPwmHz = 50;
constexpr uint32_t kServoPeriodUs = 20000;
constexpr uint32_t kServoPwmCounts = 1UL << kServoPwmBits;

// Requires a nominal 50 Hz timer. Keep the quantized pulse inside the supplied
// interval, including at either endpoint. This is arithmetic, not a measurement
// of the oscillator or actual waveform; electrical validation remains required.
inline bool servoDuty(uint16_t pulseUs, uint16_t minimumUs, uint16_t maximumUs,
                      uint32_t& duty) {
    if (!minimumUs || minimumUs >= maximumUs || maximumUs >= kServoPeriodUs ||
        pulseUs < minimumUs || pulseUs > maximumUs) return false;
    const uint32_t first = (uint32_t(minimumUs) * kServoPwmCounts + kServoPeriodUs - 1) / kServoPeriodUs;
    const uint32_t last = uint32_t(maximumUs) * kServoPwmCounts / kServoPeriodUs;
    if (first > last) return false;
    uint32_t candidate = (uint32_t(pulseUs) * kServoPwmCounts + kServoPeriodUs / 2) / kServoPeriodUs;
    if (candidate < first) candidate = first;
    if (candidate > last) candidate = last;
    duty = candidate;
    return true;
}
} // namespace feel
