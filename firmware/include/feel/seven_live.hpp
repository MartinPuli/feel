#pragma once
#include "feel/single_live.hpp"
#include "feel/pwm.hpp"

namespace feel {
// Explicit experimental adapter, not the measured production output guard.
// Compute the entire batch before hardware writes; failure has no partial plan.
enum class SevenLiveResult : uint8_t { Off, Ready, Invalid };
struct SevenLivePlan {
    std::array<uint16_t, kColumns> pulses{};
    std::array<uint32_t, kColumns> duties{};
};
inline SevenLiveResult sevenLivePlan(const Snapshot& state, SevenLivePlan& output) {
    output = SevenLivePlan{};
    if (!state.connected || !state.active || state.benchArmed || state.rawPulse)
        return SevenLiveResult::Off;
    SevenLivePlan candidate;
    for (std::size_t column = 0; column < kColumns; ++column) {
        const uint16_t pulse = livePulseForColumn(state, column);
        if (!pulse || !servoDuty(pulse, kMinPulseUs, kSingleLiveMaximumUs, candidate.duties[column]))
            return SevenLiveResult::Invalid;
        candidate.pulses[column] = pulse;
    }
    output = candidate;
    return SevenLiveResult::Ready;
}
} // namespace feel
