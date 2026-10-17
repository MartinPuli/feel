#pragma once
#include "feel/controller.hpp"

namespace feel {
constexpr std::size_t kSingleLiveSector = 3;
// Explicitly selected single-servo adapter: use the production center column's
// band/gap/tap/calibration pulse, within its nominal120-degree design envelope.
// These limits are NOT measured travel or a claim about physical calibration.
inline uint16_t singleLivePulse(const Snapshot& state) {
    if (!state.connected || !state.active || state.benchArmed || state.rawPulse) return 0;
    bool anyBand = false;
    for (auto band : state.bands) {
        if (band > 4) return 0;
        anyBand = anyBand || band != 0;
    }
    if (!anyBand) return 0; // STOP/tracking-loss packet: detach, do not sweep home.
    const uint16_t pulse = state.pulses[kSingleLiveSector];
    return pulse >= kMinPulseUs && pulse <= kMaxPulseUs ? pulse : 0;
}
} // namespace feel
