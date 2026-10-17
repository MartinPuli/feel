#include "feel/pwm.hpp"
#include "feel/serial_line.hpp"
#include "feel/commands.hpp"
#include <cassert>
#include <cstring>
#include <cstdio>

namespace {
void pwmTests() {
    uint32_t duty = 9999;
    assert(!feel::servoDuty(899, 900, 2100, duty) && duty == 9999);
    assert(!feel::servoDuty(2101, 900, 2100, duty) && duty == 9999);
    assert(!feel::servoDuty(1500, 1500, 1500, duty));
    assert(!feel::servoDuty(1500, 2000, 1000, duty));
    assert(!feel::servoDuty(0, 0, 2000, duty));
    assert(!feel::servoDuty(1500, 900, 20000, duty));
    assert(feel::servoDuty(1500, 900, 2100, duty) && duty == 1229);
    assert(feel::servoDuty(900, 900, 2100, duty) && duty == 738);
    assert(feel::servoDuty(2100, 900, 2100, duty) && duty == 1720);
    const unsigned intervals[][2] = {{900,2100},{1000,2000},{1450,1550}};
    for (const auto& interval : intervals) {
        uint32_t previous = 0;
        for (unsigned pulse = interval[0]; pulse <= interval[1]; ++pulse) {
            assert(feel::servoDuty(pulse, interval[0], interval[1], duty));
            assert(duty >= previous);
            previous = duty;
            // Cross-multiply the physical time inequality, avoiding rounded
            // integer microseconds that could hide an out-of-bound waveform.
            const uint32_t numerator = duty * 20000u;
            assert(numerator >= interval[0] * 16384u);
            assert(numerator <= interval[1] * 16384u);
            const int error = int(numerator) - int(pulse * 16384u);
            assert(error > -20000 && error < 20000); // Less than one timer tick.
        }
    }
    // Some one-microsecond intervals contain no 14-bit timer tick. Discover
    // representability independently by enumerating integer counter positions.
    for (unsigned minimum = 900; minimum < 2100; ++minimum) {
        bool exists = false;
        for (unsigned tick = 700; tick <= 1800; ++tick) {
            if (tick * 20000u >= minimum * 16384u &&
                tick * 20000u <= (minimum + 1) * 16384u) exists = true;
        }
        assert(feel::servoDuty(minimum, minimum, minimum + 1, duty) == exists);
        if (exists) {
            assert(duty * 20000u >= minimum * 16384u);
            assert(duty * 20000u <= (minimum + 1) * 16384u);
        }
    }
}
struct Harness {
    feel::SerialLine input;
    feel::Controller controller;
    unsigned lines = 0;
    unsigned faults = 0;
    uint32_t now = 0;
    void byte(uint8_t value) {
        const auto event = input.push(value);
        ++now;
        if (event == feel::SerialLine::Event::Fault) {
            ++faults;
            controller.stop(now);
        } else if (event == feel::SerialLine::Event::Line) {
            ++lines;
            feel::executeCommand(controller, feel::parseCommand(input.line()), now);
        }
    }
    void text(const char* text) { while (*text) byte(static_cast<uint8_t>(*text++)); }
};
void framingTests() {
    Harness h;
    h.text("ARM\r\nUS\t0 1500\r\n");
    assert(h.lines == 2 && h.faults == 0 && h.controller.snapshot().active);
    // A NUL must stop immediately and discard the rest, not execute US2100.
    h.text("US 0 2100");
    h.byte(0);
    assert(h.faults == 1 && !h.controller.snapshot().active && !h.controller.benchArmed());
    h.text("garbage ARM\n");
    assert(h.lines == 2 && !h.controller.benchArmed());
    h.text("ARM\n");
    assert(h.lines == 3 && h.controller.benchArmed());
    h.byte(0xff); h.text("ARM\n");
    assert(h.faults == 2 && h.lines == 3 && !h.controller.benchArmed());
    h.text("ARM\n");
    for (unsigned n = 0; n < 96; ++n) h.byte('A');
    assert(h.faults == 3 && !h.controller.benchArmed());
    h.text("ARM\n"); // Still inside the overlong, discarded line.
    assert(h.lines == 4 && !h.controller.benchArmed());
    h.text("AR\rM\n"); // CR is whitespace, not silently deleted to make ARM.
    assert(h.lines == 5 && !h.controller.benchArmed());
    h.text("ARM\nSTOP\n");
    assert(h.lines == 7 && !h.controller.benchArmed());
    h.text("ARM\n"); h.byte(0x1b);
    assert(h.faults == 4 && !h.controller.benchArmed());
    h.text("[0m\nARM\n");
    assert(h.lines == 9 && h.controller.benchArmed());
    // Maximum allowed line is95 bytes; byte96 is rejected, never truncated.
    feel::SerialLine boundary;
    for (unsigned n = 0; n < 95; ++n) assert(boundary.push('X') == feel::SerialLine::Event::None);
    assert(boundary.push('\n') == feel::SerialLine::Event::Line);
    assert(std::strlen(boundary.line()) == 95);
}
}
int main() {
    pwmTests();
    framingTests();
    std::puts("PASS adapters: PWM endpoints/monotonicity/representability; serial NUL, control bytes, overflow, CRLF, recovery and fail-closed controller integration");
}
