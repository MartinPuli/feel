#include "feel/single_demo.hpp"
#include <cassert>
#include <cstdio>

int main() {
    feel::Controller c;
    assert(feel::singleDemoPulse(c.snapshot()) == 0);
    c.connect(0);
    assert(feel::singleDemoPulse(c.snapshot()) == 0);
    feel::Packet p;
    p.bands[0] = 1; // Allows center-empty case while another sector is occupied.
    const unsigned expected[] = {1500,1450,1483,1517,1550};
    for (unsigned band=0; band<=4; ++band) {
        p.sequence = band; p.bands[3] = band;
        auto bytes = feel::encodePacket(p);
        assert(c.receive(bytes.data(), bytes.size(), band*10) == feel::Result::Ok);
        assert(feel::singleDemoPulse(c.snapshot()) == expected[band]);
    }
    c.tick(539); assert(feel::singleDemoPulse(c.snapshot()) == 1550);
    c.tick(540); assert(feel::singleDemoPulse(c.snapshot()) == 0);
    p.sequence=10; p.bands.fill(0);
    auto bytes=feel::encodePacket(p);
    assert(c.receive(bytes.data(),bytes.size(),600)==feel::Result::Ok);
    assert(c.snapshot().active && feel::singleDemoPulse(c.snapshot())==0);
    p.sequence=11;p.bands[3]=1;bytes=feel::encodePacket(p);
    assert(c.receive(bytes.data(),bytes.size(),610)==feel::Result::Ok);
    assert(c.receive(bytes.data(),bytes.size(),900)==feel::Result::Duplicate);
    c.tick(1110);assert(feel::singleDemoPulse(c.snapshot())==0);
    p.sequence=12;p.highlight=3;bytes=feel::encodePacket(p);
    assert(c.receive(bytes.data(),bytes.size(),1200)==feel::Result::Ok);
    assert(feel::singleDemoPulse(c.snapshot())==1450);
    c.disconnect(1201);assert(feel::singleDemoPulse(c.snapshot())==0);
    c.arm(1300);c.benchPulse(0,1500,1301);assert(feel::singleDemoPulse(c.snapshot())==0);
    feel::Snapshot s;s.connected=true;s.active=true;s.bands[3]=5;
    assert(feel::singleDemoPulse(s)==0);
    std::puts("PASS single demo: band mapping, boot/connect off, all-zero STOP, timeout, duplicate freshness, highlight isolation, disconnect, bench isolation, invalid band");
}
