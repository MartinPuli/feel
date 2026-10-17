#pragma once
#include "feel/controller.hpp"

namespace feel {
constexpr std::size_t kSingleLiveSector = 3;
// Connected-unit trim: approximately +15 degrees on the assumed175-degree span.
constexpr int kSingleLiveTrimUs = 159;
// User-authorized189-degree command experiment; not measured safe travel.
constexpr uint16_t kSingleLiveMaximumUs = 2648;
// Explicitly selected single-servo adapter: use the production center column's
// band/gap/tap/calibration input within its assumed175-degree design envelope.
// The connected-unit trim extends experimental output to the189-degree command.
// These limits are NOT measured travel or a claim about physical calibration.
inline uint16_t singleLivePulse(const Snapshot& state) {
    if (!state.connected || !state.active || state.benchArmed || state.rawPulse) return 0;
    for (auto band : state.bands) {
        if (band > 4) return 0;
    }
    // A fresh zero-band packet requests the nearest empty cam gap.
    // Detaching here would leave a previously selected pin raised.
    // Disconnect, timeout and explicit serial STOP still detach above.
    const uint16_t pulse = state.pulses[kSingleLiveSector];
    if (pulse < kMinPulseUs || pulse > kMaxPulseUs) return 0;
    const int adjusted = static_cast<int>(pulse) + kSingleLiveTrimUs;
    return static_cast<uint16_t>(adjusted < kMinPulseUs ? kMinPulseUs :
                                 adjusted > kSingleLiveMaximumUs ? kSingleLiveMaximumUs : adjusted);
}
// Compatibility alias for the existing experimental BLE name/environment.
// The shared controller already emits the175-degree design envelope. Never
// expand it a second time. Limits remain assumptions, not measured safe travel.
inline uint16_t singleWidePulse(const Snapshot& state) {
    return singleLivePulse(state);
}
} // namespace feel
