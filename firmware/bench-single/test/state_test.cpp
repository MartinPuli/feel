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
    std::puts("PASS: boot off, arming, expiry, keepalive, absolute cap, invalid commands, STOP, rollover");
}
