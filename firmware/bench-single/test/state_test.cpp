#include "bench.hpp"
#include <cassert>
#include <cstdio>
#include <initializer_list>
using single_servo::State;
int main() {
    State s;
    assert(!s.active && !s.armed);
    assert(s.command("STATUS", 0) && !s.active);
    assert(!s.command("CENTER", 0) && !s.active);
    assert(s.command("ARM", 0) && !s.active);
    assert(s.command("CENTER", 1) && s.active && !s.armed);
    assert(s.command("KEEP", 250) && s.active);
    s.tick(499); assert(s.active);
    assert(!s.command("KEEP", 500) && !s.active);
    assert(!s.command("CENTER", 501));
    assert(s.command("ARM", 600));
    assert(!s.command("CENTER", 10600));
    assert(s.command("ARM", 11000));
    assert(s.command("CENTER", 11001));
    for (uint32_t t=11101; t<12001; t+=100) assert(s.command("KEEP", t));
    assert(!s.command("KEEP", 12001) && !s.active); // hard cap despite keepalives
    for (const char* bad : {"ARM", "CENTER", "1500", "CENTER 1500", "", "P2100"}) {
        assert(s.command("ARM", 13000));
        assert(s.command("CENTER", 13001));
        assert(!s.command(bad, 13002) && !s.active && !s.armed);
    }
    assert(s.command("ARM", 14000));
    assert(s.command("CENTER", 14001));
    assert(s.command("STOP", 14002) && !s.active && !s.armed);
    assert(s.command("ARM", 0xffffff00u));
    assert(s.command("CENTER", 0xfffffff0u));
    assert(s.command("KEEP", 0x50u) && s.active);
    s.tick(0x14au); assert(!s.active); // watchdog across millis wrap
    assert(s.command("ARM", 20000));
    assert(s.command("TEST5", 20001));
    assert(s.pulseUs(20001) == 1500);
    for (uint32_t elapsed=100; elapsed<5000; elapsed+=100) {
        assert(s.command("KEEP", 20001+elapsed));
        unsigned expected = elapsed<500 || elapsed>=4500 ? 1500 : (elapsed/500)%2 ? 1450 : 1550;
        assert(s.pulseUs(20001+elapsed) == expected);
    }
    assert(!s.command("KEEP", 25001) && !s.active && s.pulseUs(25001)==0);
    for (const char* bad : {"ARM", "CENTER", "TEST5", "garbage"}) {
        assert(s.command("ARM", 30000));
        assert(s.command("TEST5", 30001));
        assert(!s.command(bad, 30002) && !s.active && !s.armed);
    }
    assert(s.command("ARM", 40000));
    assert(s.command("TEST5", 40001));
    assert(!s.command("KEEP", 40251) && !s.active);
    assert(s.command("ARM", 0xfffff000u));
    assert(s.command("TEST5", 0xfffff001u));
    for (uint32_t e=100; e<5000; e+=100) assert(s.command("KEEP", uint32_t(0xfffff001u+e)));
    s.tick(uint32_t(0xfffff001u+5000));assert(!s.active);
    // SWEEP 1: center for 1 s, then +50 us every 500 ms, capped at 2500 us; watchdog and STOP still apply.
    assert(!s.command("SWEEP 1", 50000)); // needs ARM
    assert(s.command("ARM", 50000));
    assert(s.command("SWEEP 1", 50001) && s.active && s.sweep == 1);
    assert(s.pulseUs(50001) == 1500 && s.pulseUs(50001+999) == 1500);
    assert(s.pulseUs(50001+1000) == 1550 && s.pulseUs(50001+1499) == 1550);
    assert(s.pulseUs(50001+1500) == 1600);
    for (uint32_t e=100; e<=11000; e+=100) assert(s.command("KEEP", 50001+e));
    assert(s.pulseUs(50001+11000) == 2500); // 1000 + 20 steps * 500 = 11000 ms reaches the top
    assert(s.pulseUs(50001+11400) == 2500); // and holds there
    assert(s.command("STOP", 50001+11450) && !s.active && s.pulseUs(50001+11450) == 0);
    // SWEEP 0 goes the other way and the hard cap ends it even with keepalives.
    assert(s.command("ARM", 70000));
    assert(s.command("SWEEP 0", 70001) && s.sweep == -1);
    assert(s.pulseUs(70001+1000) == 1450 && s.pulseUs(70001+1500) == 1400);
    for (uint32_t e=100; e<=11000; e+=100) assert(s.command("KEEP", 70001+e));
    assert(s.pulseUs(70001+11000) == 500);
    assert(!s.command("KEEP", 70001+uint32_t(single_servo::kSweepMs)) && !s.active);
    // Watchdog during a sweep.
    assert(s.command("ARM", 90000));
    assert(s.command("SWEEP 1", 90001));
    assert(!s.command("KEEP", 90001+251) && !s.active && s.sweep == 0);
    // A second motion command during a sweep stops it.
    assert(s.command("ARM", 95000));
    assert(s.command("SWEEP 1", 95001));
    assert(!s.command("CENTER", 95002) && !s.active);
    assert(!s.command("SWEEP 2", 95100) && !s.active); // only 0 or 1
    std::puts("PASS: boot off, arming, expiry, keepalive, absolute cap, invalid commands, STOP, rollover, TEST5 phase sequence and caps, SWEEP steps/caps/watchdog");
}
