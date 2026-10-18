// Every physical pin, every band, through the real controller: a packet that raises one wire
// slot must move that slot's servo to the band angle and pulse, leave the other five at their
// neutral gap, never touch slot zero, and drop again when the watchdog expires.
#include "feel/controller.hpp"
#include "feel/seven_live.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>

namespace {
void receive(feel::Controller& c, const feel::Packet& packet, uint32_t now) {
    const auto bytes = feel::encodePacket(packet);
    assert(c.receive(bytes.data(), bytes.size(), now) == feel::Result::Ok);
}
bool near(float a, float b) { return std::fabs(a - b) < 1e-3F; }
}

int main() {
    // Band angles and the pulses the servo driver receives for them (650..2500 us over 175 degrees).
    const uint16_t pulses[] = {0, 650, 1263, 1876, 2489};
    for (uint8_t band = 1; band <= 4; ++band) {
        assert(near(feel::bandAngle(band), feel::kBandAnglesDeg[band - 1]));
        assert(feel::angleToPulse(feel::bandAngle(band)) == pulses[band]);
    }
    const uint16_t neutralPulse = feel::angleToPulse(feel::kDefaultNeutralDeg);

    for (std::size_t column = feel::kFirstActiveColumn; column < feel::kColumns; ++column) {
        for (uint8_t band = 1; band <= 4; ++band) {
            feel::Controller c; c.connect(0);
            const auto rest = c.snapshot();
            feel::Packet packet; packet.bands[column] = band;
            receive(c, packet, 1);
            c.tick(2);
            const auto& s = c.snapshot();
            assert(s.active && s.connected && s.accepted == 1 && s.rejected == 0);
            // The commanded pin.
            assert(s.bands[column] == band);
            assert(near(s.angles[column], feel::kBandAnglesDeg[band - 1]));
            assert(s.pulses[column] == pulses[band]);
            // Every other active pin stays down at its neutral gap.
            for (std::size_t other = feel::kFirstActiveColumn; other < feel::kColumns; ++other) {
                if (other == column) continue;
                assert(s.bands[other] == 0);
                assert(near(s.angles[other], feel::kDefaultNeutralDeg));
                assert(s.pulses[other] == neutralPulse);
            }
            // Slot zero has no servo: nothing about it changes.
            assert(s.bands[0] == 0);
            assert(near(s.angles[0], rest.angles[0]) && s.pulses[0] == rest.pulses[0]);
            // Without a fresh packet the watchdog lowers the pin.
            c.tick(1 + feel::kWatchdogMs - 1);
            assert(c.snapshot().active);
            c.tick(1 + feel::kWatchdogMs);
            assert(!c.snapshot().active);
        }
    }

    // Raising one pin after another on the same connection: each new packet moves only its own slot.
    feel::Controller c; c.connect(0);
    uint32_t now = 1;
    for (std::size_t column = feel::kFirstActiveColumn; column < feel::kColumns; ++column) {
        feel::Packet packet; packet.sequence = static_cast<uint8_t>(column); packet.bands[column] = 4;
        receive(c, packet, now); c.tick(now + 1);
        const auto& s = c.snapshot();
        for (std::size_t other = feel::kFirstActiveColumn; other < feel::kColumns; ++other) {
            assert(s.bands[other] == (other == column ? 4 : 0));
            assert(s.pulses[other] == (other == column ? pulses[4] : feel::angleToPulse(s.angles[other])));
        }
        now += 50;
    }

    // Slot zero asked to rise: the packet is legal on the wire (legacy apps), the controller tracks
    // it, but the output plan that drives the servos never emits a pulse for slot zero.
    {
        feel::Controller z; z.connect(0);
        feel::Packet packet; packet.bands[0] = 4;
        receive(z, packet, 1); z.tick(2);
        feel::SevenLivePlan plan;
        assert(feel::sevenLivePlan(z.snapshot(), plan) == feel::SevenLiveResult::Ready);
        assert(plan.pulses[0] == 0 && plan.duties[0] == 0);
        for (std::size_t other = feel::kFirstActiveColumn; other < feel::kColumns; ++other) {
            assert(z.snapshot().bands[other] == 0);
            assert(plan.pulses[other] == feel::livePulseForColumn(z.snapshot(), other));
        }
    }

    puts("PASS pin-rise: each of six pins rises alone to bands 1-4 with the right angle and pulse, neighbours stay at neutral, slot zero never moves, watchdog lowers");
}
