#include "feel/seven_live.hpp"
#include <cassert>
#include <cstdio>

using feel::SevenLivePlan;
using feel::SevenLiveResult;
void receive(feel::Controller& c, const feel::Packet& packet, uint32_t now) {
    const auto bytes = feel::encodePacket(packet);
    assert(c.receive(bytes.data(), bytes.size(), now) == feel::Result::Ok);
}
void assertOff(const feel::Snapshot& state) {
    SevenLivePlan plan;
    plan.pulses.fill(1234); plan.duties.fill(1234);
    assert(feel::sevenLivePlan(state, plan) == SevenLiveResult::Off);
    for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) assert(!plan.pulses[i] && !plan.duties[i]);
}
int main() {
    feel::Controller c;
    assertOff(c.snapshot()); c.connect(0); assertOff(c.snapshot());
    const uint16_t expected[] = {1116, 809, 1422, 2035, 2648};
    // Every column independently consumes its own sector; no center replication.
    for (std::size_t column = feel::kFirstActiveColumn; column < feel::kColumns; ++column) {
        for (uint8_t band = 0; band <= 4; ++band) {
            feel::Controller trial; trial.connect(0);
            feel::Packet packet; packet.bands[column] = band;
            receive(trial, packet, 1);
            SevenLivePlan plan;
            assert(feel::sevenLivePlan(trial.snapshot(), plan) == SevenLiveResult::Ready);
            for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) {
                assert(plan.pulses[i] == (i == column ? expected[band] : expected[0]));
                assert(plan.pulses[i] == feel::livePulseForColumn(trial.snapshot(), i));
                const uint32_t scaled = plan.duties[i] * feel::kServoPeriodUs;
                assert(scaled >= feel::kMinPulseUs * feel::kServoPwmCounts);
                assert(scaled <= feel::kSingleLiveMaximumUs * feel::kServoPwmCounts);
            }
        }
    }
    feel::Packet packet; packet.bands = {{1, 2, 3, 4, 1, 2, 3}};
    receive(c, packet, 1);
    SevenLivePlan plan;
    assert(feel::sevenLivePlan(c.snapshot(), plan) == SevenLiveResult::Ready);
    assert(plan.pulses[0] == 0 && plan.duties[0] == 0);
    auto missing = c.snapshot(); missing.pulses[0] = 65535;
    assert(feel::sevenLivePlan(missing, plan) == SevenLiveResult::Ready);
    assert(plan.pulses[0] == 0 && plan.duties[0] == 0);
    for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) assert(plan.pulses[i] == expected[packet.bands[i]]);
    // A single bad late channel must invalidate the entire batch, never partially write.
    for (std::size_t column = feel::kFirstActiveColumn; column < feel::kColumns; ++column) {
        for (uint16_t invalid : {uint16_t(0), uint16_t(649), uint16_t(2501), uint16_t(65535)}) {
            auto state = c.snapshot(); state.pulses[column] = invalid;
            plan.pulses.fill(1234); plan.duties.fill(1234);
            assert(feel::sevenLivePlan(state, plan) == SevenLiveResult::Invalid);
            for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) assert(!plan.pulses[i] && !plan.duties[i]);
        }
        auto state = c.snapshot(); state.bands[column] = 5;
        assert(feel::sevenLivePlan(state, plan) == SevenLiveResult::Invalid);
    }
    auto state = c.snapshot(); state.benchArmed = true; assertOff(state);
    state = c.snapshot(); state.rawPulse = true; assertOff(state);
    state = c.snapshot(); state.connected = false; assertOff(state);
    assert(feel::livePulseForColumn(c.snapshot(), 7) == 0);
    // Fresh clear packets lower to each column's own previous nearest gap.
    packet.sequence = 1; packet.bands.fill(0); receive(c, packet, 100);
    assert(feel::sevenLivePlan(c.snapshot(), plan) == SevenLiveResult::Ready);
    const uint16_t cleared[] = {1116, 1116, 1729, 2342, 1116, 1116, 1729};
    for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) assert(plan.pulses[i] == cleared[i]);
    c.tick(599); assert(feel::sevenLivePlan(c.snapshot(), plan) == SevenLiveResult::Ready);
    c.tick(600); assertOff(c.snapshot());
    packet.sequence = 2; packet.bands.fill(4); receive(c, packet, 601);
    c.disconnect(602); assertOff(c.snapshot()); c.connect(603); assertOff(c.snapshot());
    packet.sequence = 3; receive(c, packet, 604); c.stop(605); assertOff(c.snapshot());
    c.disconnect(606); c.arm(607); c.benchPulse(0, 1500, 608); assertOff(c.snapshot());
    // Rejected packets cannot extend freshness, including across millis rollover.
    feel::Controller rollover; rollover.connect(0xfffffff0u);
    receive(rollover, packet, 0xfffffff1u);
    const auto bytes = feel::encodePacket(packet);
    assert(rollover.receive(bytes.data(), bytes.size(), uint32_t(0xfffffff1u + 499u)) == feel::Result::Duplicate);
    rollover.tick(uint32_t(0xfffffff1u + 500u)); assertOff(rollover.snapshot());
    puts("PASS seven-live: six independent active slots, reserved slot zero disabled, trim/cap, atomic validation, off/bench/raw guards, zero gaps, timeout/disconnect/STOP, rollover and duplicate freshness");
}
