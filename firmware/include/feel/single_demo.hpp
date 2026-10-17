#pragma once
#include "feel/controller.hpp"

namespace feel {
constexpr std::size_t kDemoSector = 3; // Center of the seven iPhone sectors.
// Physical adapter for one unloaded servo, NOT the production cam mapping.
// Only the nominal midpoint neighborhood has user-reported motion evidence.
inline uint16_t singleDemoPulse(const Snapshot& state) {
    if (!state.connected || !state.active || state.benchArmed || state.rawPulse) return 0;
    bool anyBand = false;
    for (auto band : state.bands) {
        if (band > 4) return 0;
        anyBand = anyBand || band != 0;
    }
    if (!anyBand) return 0; // App STOP and tracking-loss packets detach immediately.
    constexpr uint16_t pulses[] = {1500, 1450, 1483, 1517, 1550};
    return pulses[state.bands[kDemoSector]];
}
} // namespace feel
