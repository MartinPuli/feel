#pragma once
#include "feel/controller.hpp"

namespace feel {
// Board-side admission policy, also tested on the host. The packet controller
// keeps handoff geometry; it cannot certify that a particular servo supports it.
// Validate the entire output set before writing any individual channel.
class OutputGuard {
public:
    enum class State : uint8_t { Disabled = 0, Ready = 1, Fault = 2 };
    OutputGuard(bool enabled, uint16_t minimum, uint16_t maximum)
        : state_(enabled ? State::Ready : State::Disabled), minimum_(minimum), maximum_(maximum) {
        if (enabled && (minimum < kMinPulseUs || maximum > kMaxPulseUs || minimum >= maximum)) fault();
    }
    bool admit(const std::array<uint16_t, kColumns>& pulses) {
        if (state_ != State::Ready) return false;
        for (auto pulse : pulses) {
            if (pulse < minimum_ || pulse > maximum_) { fault(); return false; }
        }
        return true;
    }
    void fault() { state_ = State::Fault; }
    State state() const { return state_; }
private:
    State state_;
    uint16_t minimum_;
    uint16_t maximum_;
};
} // namespace feel
