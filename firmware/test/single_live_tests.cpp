#include "feel/single_live.hpp"
#include "feel/single_demo.hpp"
#include <cassert>
#include <cstdio>

namespace {
void receive(feel::Controller& controller, const feel::Packet& packet, uint32_t now) {
    const auto bytes = feel::encodePacket(packet);
    assert(controller.receive(bytes.data(), bytes.size(), now) == feel::Result::Ok);
}
void bandsAndExpiry() {
    feel::Controller c;
    assert(feel::singleLivePulse(c.snapshot()) == 0);
    c.connect(1);
    assert(feel::singleLivePulse(c.snapshot()) == 0);
    feel::Packet p;
    p.bands[0] = 4; // Center-empty must use the center gap, not a side obstacle.
    const unsigned expected[] = {798,650,1104,1717,2330};
    for (unsigned band = 0; band <= 4; ++band) {
        p.sequence = band; p.bands[3] = band;
        receive(c,p,10 + band*10);
        assert(feel::singleLivePulse(c.snapshot()) == expected[band]);
        assert(feel::singleLivePulse(c.snapshot()) <= c.snapshot().pulses[3]);
    }
    c.tick(549); assert(feel::singleLivePulse(c.snapshot()) == 2330);
    c.tick(550); assert(feel::singleLivePulse(c.snapshot()) == 0);
    p.sequence = 10; p.bands.fill(0);
    receive(c,p,600);
    assert(c.snapshot().active && feel::singleLivePulse(c.snapshot()) == 2024);
    p.sequence = 11; p.bands[3] = 4;
    receive(c,p,610);
    const auto bytes = feel::encodePacket(p);
    assert(c.receive(bytes.data(),bytes.size(),900) == feel::Result::Duplicate);
    assert(c.receive(bytes.data(),bytes.size()-1,925) == feel::Result::BadLength);
    auto malformed = bytes; malformed[4] = 5;
    assert(c.receive(malformed.data(),malformed.size(),950) == feel::Result::BadBand);
    p.sequence = 10;
    const auto stale = feel::encodePacket(p);
    assert(c.receive(stale.data(),stale.size(),1000) == feel::Result::StaleSequence);
    c.tick(1110); assert(feel::singleLivePulse(c.snapshot()) == 0);
    p.sequence = 12;
    receive(c,p,1200);
    c.disconnect(1201); assert(feel::singleLivePulse(c.snapshot()) == 0);
    c.connect(1202); assert(feel::singleLivePulse(c.snapshot()) == 0);
}
void productionTapGapCalibration() {
    feel::Controller c;
    assert(c.loadOffset(3,5) == feel::Result::Ok);
    c.connect(0);
    feel::Packet p; p.bands[0] = 1; p.bands[3] = 2;
    receive(c,p,1);
    assert(feel::singleLivePulse(c.snapshot()) == 1157); //58deg +5deg offset.
    assert(feel::singleDemoPulse(c.snapshot()) == 1483); // Old demo unchanged.
    p.sequence = 1; p.highlight = 3;
    receive(c,p,10);
    assert(c.snapshot().tapActive && feel::singleLivePulse(c.snapshot()) == 1020);
    c.tick(110);
    assert(!c.snapshot().tapActive && feel::singleLivePulse(c.snapshot()) == 1157);
    p.sequence = 2; p.bands[3] = 4; p.highlight = feel::kNoHighlight;
    receive(c,p,200);
    assert(feel::singleLivePulse(c.snapshot()) == 2341); // Endpoint offset clamp.
    p.sequence = 3; p.bands[3] = 0;
    receive(c,p,210);
    assert(feel::singleLivePulse(c.snapshot()) == 2077); //145deg gap +5deg offset.
    p.sequence = 4; p.bands.fill(0);
    receive(c,p,220);
    assert(c.snapshot().pulses[3] == 2236 && feel::singleLivePulse(c.snapshot()) == 2077);
    c.stop(221); assert(feel::singleLivePulse(c.snapshot()) == 0);
}
void allZeroReturnsEverySelectionToGap() {
    const unsigned gaps[] = {798,798,1411,2024};
    for (unsigned band = 1; band <= 4; ++band) {
        feel::Controller c; c.connect(0);
        feel::Packet p; p.bands[3] = band;
        receive(c,p,1);
        p.sequence = 1; p.bands.fill(0);
        receive(c,p,2);
        assert(feel::singleLivePulse(c.snapshot()) == gaps[band-1]);
        assert(!c.snapshot().tapActive);
        c.tick(501); assert(feel::singleLivePulse(c.snapshot()) == gaps[band-1]);
        c.tick(502); assert(feel::singleLivePulse(c.snapshot()) == 0);
    }
}
void lowerBoundClipsFirstHighlight() {
    feel::Controller c; c.connect(0);
    feel::Packet p; p.bands[3] = 1; p.highlight = 3;
    receive(c,p,1);
    assert(c.snapshot().tapActive);
    assert(feel::singleLivePulse(c.snapshot()) == 650);
    c.tick(101);
    assert(!c.snapshot().tapActive);
    assert(feel::singleLivePulse(c.snapshot()) == 650);
}
void isolationAndInvalid() {
    feel::Controller c;
    c.arm(0);c.benchPulse(3,1500,1);
    assert(feel::singleLivePulse(c.snapshot()) == 0);
    feel::Snapshot s;
    s.connected = true; s.active = true; s.bands[3] = 1; s.pulses[3] = 650;
    assert(feel::singleLivePulse(s) == 650);
    s.benchArmed = true; assert(feel::singleLivePulse(s) == 0); s.benchArmed = false;
    s.rawPulse = true; assert(feel::singleLivePulse(s) == 0); s.rawPulse = false;
    s.pulses[3] = 649; assert(feel::singleLivePulse(s) == 0);
    s.pulses[3] = 2501; assert(feel::singleLivePulse(s) == 0);
    s.pulses[3] = 650; s.bands[0] = 5; assert(feel::singleLivePulse(s) == 0);
}
void rollover() {
    feel::Controller c;
    c.connect(0xfffffff0u);
    feel::Packet p;p.bands[3] = 1;
    receive(c,p,0xfffffff1u);
    c.tick(uint32_t(0xfffffff1u + 499u)); assert(feel::singleLivePulse(c.snapshot()) == 650);
    c.tick(uint32_t(0xfffffff1u + 500u)); assert(feel::singleLivePulse(c.snapshot()) == 0);
}
}
int main() {
    bandsAndExpiry();productionTapGapCalibration();allZeroReturnsEverySelectionToGap();lowerBoundClipsFirstHighlight();isolationAndInvalid();rollover();
    std::puts("PASS single live: production center bands/gaps/taps/calibration, demo isolation, boot/connect off, STOP, freshness, disconnect, bench rejection, invalid bounds, rollover");
}
