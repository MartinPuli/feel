#include "feel/commands.hpp"
#include "feel/output_guard.hpp"
#include "feel/calibration.hpp"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using feel::Controller;
using feel::Result;
struct Test { const char* name; void (*run)(); };
std::vector<Test>& tests() { static std::vector<Test> entries; return entries; }
struct Register { Register(const char* name, void (*run)()) { tests().push_back({name, run}); } };
#define TEST(name) void name(); Register register_##name(#name, name); void name()
#define CHECK(condition) do { if (!(condition)) throw std::runtime_error(std::string(__FILE__) + ":" + std::to_string(__LINE__) + " " #condition); } while (false)
#define CLOSE(a,b) CHECK(std::fabs((a) - (b)) < 0.001F)

std::array<uint8_t, 9> wire(uint8_t seq = 0, uint8_t band = 1, uint8_t highlight = 255) {
    return {{seq, band, band, band, band, band, band, band, highlight}};
}
Result send(Controller& c, uint8_t seq, uint8_t band, uint32_t now, uint8_t highlight = 255) {
    const auto bytes = wire(seq, band, highlight);
    return c.receive(bytes.data(), bytes.size(), now);
}
void neutral(const Controller& c) {
    for (const auto band : c.snapshot().bands) CHECK(band == 0);
    CHECK(!c.snapshot().active);
    CHECK(!c.snapshot().sequenceValid);
    CHECK(c.snapshot().highlight == 255);
}

TEST(boot_is_neutral_disconnected) {
    Controller c;
    neutral(c);
    CHECK(!c.snapshot().connected);
    for (float angle : c.snapshot().angles) CLOSE(angle, 20);
    CHECK(send(c, 0, 1, 0) == Result::Disconnected);
}

TEST(decode_roundtrip_preserves_nine_wire_bytes) {
    const std::array<uint8_t, 9> bytes{{255, 0, 1, 2, 3, 4, 2, 1, 4}};
    feel::Packet p;
    CHECK(feel::decodePacket(bytes.data(), bytes.size(), p) == Result::Ok);
    CHECK(feel::encodePacket(p) == bytes);
}

TEST(decoder_length_and_null_are_rejected) {
    const auto bytes = wire();
    for (std::size_t length = 0; length <= 64; ++length) {
        if (length == 9) continue;
        feel::Packet p;
        p.sequence = 42;
        CHECK(feel::decodePacket(bytes.data(), length, p) == Result::BadLength);
        CHECK(p.sequence == 42);
    }
    feel::Packet p;
    CHECK(feel::decodePacket(nullptr, 9, p) == Result::BadLength);
}

TEST(all_band_values_checked_in_every_column_atomically) {
    for (std::size_t column = 0; column < 7; ++column) {
        for (unsigned value = 0; value <= 255; ++value) {
            auto bytes = wire();
            bytes[column + 1] = static_cast<uint8_t>(value);
            feel::Packet p;
            p.sequence = 99;
            const auto result = feel::decodePacket(bytes.data(), 9, p);
            CHECK(result == (value <= 4 ? Result::Ok : Result::BadBand));
            if (value > 4) CHECK(p.sequence == 99);
        }
    }
}

TEST(all_highlight_values_checked) {
    for (unsigned value = 0; value <= 255; ++value) {
        const auto bytes = wire(0, 0, static_cast<uint8_t>(value));
        feel::Packet p;
        CHECK(feel::decodePacket(bytes.data(), 9, p) ==
            (value < 7 || value == 255 ? Result::Ok : Result::BadHighlight));
    }
}

TEST(empty_highlight_is_wire_legal_but_effective_off) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 0, 0, 1, 4) == Result::Ok);
    CHECK(c.snapshot().highlight == 255);
    CHECK(!c.snapshot().tapActive);
    CHECK(c.snapshot().active);
}

TEST(all_bands_map_to_expected_angles) {
    Controller c;
    c.connect(0);
    const float expected[] = {0, 40, 80, 120};
    for (uint8_t b = 1; b <= 4; ++b) {
        CHECK(send(c, b, b, b * 10) == Result::Ok);
        for (float angle : c.snapshot().angles) CLOSE(angle, expected[b - 1]);
    }
}

TEST(disappearing_pin_uses_nearest_last_band_gap) {
    const float gaps[] = {20, 20, 60, 100};
    for (uint8_t b = 1; b <= 4; ++b) {
        Controller c;
        c.connect(0);
        CHECK(send(c, 0, b, 1) == Result::Ok);
        CHECK(send(c, 1, 0, 2) == Result::Ok);
        for (float angle : c.snapshot().angles) CLOSE(angle, gaps[b - 1]);
        CHECK(send(c, 2, 0, 3) == Result::Ok);
        for (float angle : c.snapshot().angles) CLOSE(angle, gaps[b - 1]);
    }
    CLOSE(feel::nearestGap(60), 60);
    CLOSE(feel::nearestGap(40), 20);
    CLOSE(feel::nearestGap(80), 60);
    CLOSE(feel::nearestGap(40.01F), 60);
    CLOSE(feel::nearestGap(80.01F), 100);
}

TEST(rejection_does_not_partially_apply_bands_or_highlight) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 10, 3, 10) == Result::Ok);
    auto bad = wire(11, 1, 1);
    bad[7] = 5;
    CHECK(c.receive(bad.data(), bad.size(), 20) == Result::BadBand);
    for (auto b : c.snapshot().bands) CHECK(b == 3);
    CHECK(c.snapshot().lastSequence == 10);
    CHECK(c.snapshot().highlight == 255);
}

TEST(duplicate_does_not_extend_watchdog) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 10, 4, 1) == Result::Ok);
    CHECK(send(c, 10, 1, 400) == Result::Duplicate);
    c.tick(501);
    neutral(c);
    CLOSE(c.snapshot().angles[0], 100);
}

TEST(stale_and_half_range_sequences_rejected) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 10, 1, 1) == Result::Ok);
    CHECK(send(c, 9, 2, 10) == Result::StaleSequence);
    CHECK(send(c, 138, 2, 20) == Result::StaleSequence);
    CHECK(send(c, 137, 3, 30) == Result::Ok);
    CHECK(c.snapshot().bands[0] == 3);
}

TEST(every_sequence_delta_matches_modular_contract) {
    for (unsigned start = 0; start <= 255; ++start) {
        for (unsigned delta = 0; delta <= 255; ++delta) {
            Controller c;
            c.connect(0);
            CHECK(send(c, static_cast<uint8_t>(start), 1, 0) == Result::Ok);
            const auto result = send(c, static_cast<uint8_t>(start + delta), 2, 1);
            CHECK(result == (delta == 0 ? Result::Duplicate : delta < 128 ? Result::Ok : Result::StaleSequence));
        }
    }
}

TEST(sequence_rollover_254_255_0_1) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 254, 1, 0) == Result::Ok);
    CHECK(send(c, 255, 2, 100) == Result::Ok);
    CHECK(send(c, 0, 3, 200) == Result::Ok);
    CHECK(send(c, 1, 4, 300) == Result::Ok);
    CHECK(c.snapshot().lastSequence == 1);
}

TEST(watchdog_boundary_is_greater_or_equal_500) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 1, 2, 50) == Result::Ok);
    c.tick(549);
    CHECK(c.snapshot().active);
    c.tick(550);
    neutral(c);
    CHECK(c.snapshot().timeouts == 1);
    c.tick(9999);
    CHECK(c.snapshot().timeouts == 1);
}

TEST(watchdog_resets_sequence_baseline_even_inside_receive) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 180, 1, 1) == Result::Ok);
    CHECK(send(c, 180, 2, 501) == Result::Ok);
    CHECK(c.snapshot().timeouts == 1);
    CHECK(c.snapshot().bands[0] == 2);
}

TEST(invalid_traffic_cannot_keep_motion_alive) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 0, 2, 0) == Result::Ok);
    for (uint32_t t = 100; t <= 400; t += 100) {
        const auto bad = wire(1, 5);
        CHECK(c.receive(bad.data(), 9, t) == Result::BadBand);
    }
    c.tick(500);
    neutral(c);
}

TEST(disconnect_clears_state_and_reconnect_accepts_any_sequence) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 99, 3, 10, 2) == Result::Ok);
    c.disconnect(11);
    neutral(c);
    CHECK(!c.snapshot().connected);
    CHECK(send(c, 100, 4, 12) == Result::Disconnected);
    c.connect(13);
    CHECK(send(c, 0, 1, 14) == Result::Ok);
}

TEST(millis_rollover_preserves_watchdog_boundary) {
    Controller c;
    const uint32_t start = UINT32_MAX - 200;
    c.connect(start);
    CHECK(send(c, 0, 4, start) == Result::Ok);
    c.tick(start + 499U);
    CHECK(c.snapshot().active);
    c.tick(start + 500U);
    neutral(c);
}

TEST(highlight_taps_toward_gap_for_all_bands) {
    const float expected[] = {13, 27, 67, 107};
    for (uint8_t band = 1; band <= 4; ++band) {
        Controller c;
        c.connect(0);
        CHECK(send(c, 0, band, 0, 3) == Result::Ok);
        CHECK(c.snapshot().tapActive);
        CLOSE(c.snapshot().angles[3], expected[band - 1]);
        CLOSE(c.snapshot().angles[2], feel::bandAngle(band));
        c.tick(99);
        CHECK(c.snapshot().tapActive);
        c.tick(100);
        CHECK(!c.snapshot().tapActive);
        CLOSE(c.snapshot().angles[3], feel::bandAngle(band));
    }
}

TEST(repeated_packets_do_not_restart_tap_phase) {
    Controller c;
    c.connect(0);
    for (uint8_t i = 0; i <= 6; ++i) {
        CHECK(send(c, i, 2, i * 100U, 0) == Result::Ok);
        CHECK(c.snapshot().tapActive == (i == 0 || i == 6));
    }
}

TEST(changing_highlight_or_its_band_restarts_tap) {
    Controller c;
    c.connect(0);
    CHECK(send(c, 0, 1, 0, 0) == Result::Ok);
    CHECK(send(c, 1, 1, 200, 0) == Result::Ok);
    CHECK(!c.snapshot().tapActive);
    CHECK(send(c, 2, 1, 210, 1) == Result::Ok);
    CHECK(c.snapshot().tapActive);
    CHECK(send(c, 3, 2, 400, 1) == Result::Ok);
    CHECK(c.snapshot().tapActive);
    CLOSE(c.snapshot().angles[1], 27);
}

TEST(tap_millis_rollover_works) {
    Controller c;
    const uint32_t start = UINT32_MAX - 50;
    c.connect(start);
    CHECK(send(c, 0, 1, start, 0) == Result::Ok);
    c.tick(start + 99U);
    CHECK(c.snapshot().tapActive);
    c.tick(start + 100U);
    CHECK(!c.snapshot().tapActive);
}

TEST(calibration_requires_arm_and_valid_finite_offset) {
    Controller c;
    CHECK(c.calibrate(0, 1, 0) == Result::NotArmed);
    CHECK(c.arm(0) == Result::Ok);
    CHECK(c.calibrate(0, 5, 1) == Result::Ok);
    CHECK(c.calibrate(0, 5.01F, 2) == Result::BadOffset);
    CHECK(c.calibrate(0, -5.01F, 3) == Result::BadOffset);
    CHECK(c.calibrate(0, std::numeric_limits<float>::quiet_NaN(), 4) == Result::BadOffset);
    CHECK(c.calibrate(0, std::numeric_limits<float>::infinity(), 5) == Result::BadOffset);
    CHECK(c.calibrate(7, 0, 6) == Result::BadColumn);
    CLOSE(c.snapshot().offsets[0], 5);
}

TEST(calibration_clamps_both_servo_endpoints) {
    Controller c;
    CHECK(c.loadOffset(0, -5) == Result::Ok);
    CHECK(c.loadOffset(1, 5) == Result::Ok);
    c.connect(0);
    CHECK(send(c, 0, 1, 1) == Result::Ok);
    CLOSE(c.snapshot().angles[0], 0);
    CLOSE(c.snapshot().angles[1], 5);
    CHECK(send(c, 1, 4, 2) == Result::Ok);
    CLOSE(c.snapshot().angles[0], 115);
    CLOSE(c.snapshot().angles[1], 120);
}

TEST(calibration_does_not_extend_motion_watchdog) {
    Controller c;
    CHECK(c.arm(0) == Result::Ok);
    CHECK(c.benchBand(0, 4, 0) == Result::Ok);
    CHECK(c.calibrate(0, 1, 400) == Result::Ok);
    c.tick(500);
    neutral(c);
    CLOSE(c.snapshot().angles[0], 101);
}

TEST(raw_pulse_requires_arm_and_bounds) {
    Controller c;
    CHECK(c.benchPulse(0, 1500, 0) == Result::NotArmed);
    CHECK(c.arm(0) == Result::Ok);
    CHECK(c.benchPulse(0, 899, 1) == Result::BadPulse);
    CHECK(c.benchPulse(0, 2101, 2) == Result::BadPulse);
    CHECK(c.benchPulse(7, 1000, 3) == Result::BadColumn);
    CHECK(c.benchPulse(0, 2100, 4) == Result::Ok);
    CHECK(c.snapshot().rawPulse);
    CHECK(c.snapshot().pulses[0] == 2100);
    c.tick(504);
    neutral(c);
    CHECK(!c.snapshot().rawPulse);
    CLOSE(c.snapshot().angles[0], 100);
}

TEST(raw_pulse_is_exclusive_and_stop_clears_it) {
    Controller c;
    CHECK(c.arm(0) == Result::Ok);
    CHECK(c.benchBand(2, 4, 0) == Result::Ok);
    CHECK(c.benchPulse(0, 900, 10) == Result::Ok);
    for (auto band : c.snapshot().bands) CHECK(band == 0);
    CLOSE(c.snapshot().angles[2], 100);
    c.stop(20);
    neutral(c);
    CHECK(!c.snapshot().benchArmed);
    CHECK(!c.snapshot().rawPulse);
}

TEST(bench_cannot_arm_while_ble_connected) {
    Controller c;
    c.connect(0);
    CHECK(c.arm(1) == Result::BenchLocked);
    CHECK(c.benchBand(0, 1, 2) == Result::NotArmed);
    c.disconnect(3);
    CHECK(c.arm(4) == Result::Ok);
}

TEST(keepalive_cannot_resurrect_expired_motion) {
    Controller c;
    CHECK(c.arm(0) == Result::Ok);
    CHECK(c.keepAlive(0) == Result::NoActiveCommand);
    CHECK(c.benchBand(0, 1, 0) == Result::Ok);
    CHECK(c.keepAlive(499) == Result::Ok);
    CHECK(c.keepAlive(998) == Result::Ok);
    CHECK(c.keepAlive(1498) == Result::NoActiveCommand);
    neutral(c);
}

TEST(bench_arm_expires_even_with_keepalives) {
    Controller c;
    const uint32_t start = UINT32_MAX - 100;
    CHECK(c.arm(start) == Result::Ok);
    CHECK(c.benchBand(0, 4, start) == Result::Ok);
    for (uint32_t elapsed = 100; elapsed < 30000; elapsed += 100) CHECK(c.keepAlive(start + elapsed) == Result::Ok);
    CHECK(c.keepAlive(start + 30000U) == Result::NotArmed);
    neutral(c);
}

TEST(pulse_conversion_is_bounded_and_monotonic) {
    CHECK(feel::angleToPulse(0) == 900);
    CHECK(feel::angleToPulse(60) == 1500);
    CHECK(feel::angleToPulse(120) == 2100);
    CHECK(feel::angleToPulse(-10) == 900);
    CHECK(feel::angleToPulse(1000) == 2100);
    uint16_t previous = 0;
    for (int tenth = 0; tenth <= 1200; ++tenth) {
        const auto pulse = feel::angleToPulse(tenth / 10.0F);
        CHECK(pulse >= previous && pulse >= 900 && pulse <= 2100);
        previous = pulse;
    }
}

TEST(serial_parser_valid_commands) {
    using feel::CommandKind;
    CHECK(feel::parseCommand(" ARM \r\n").kind == CommandKind::Arm);
    CHECK(feel::parseCommand("B 6 4").kind == CommandKind::Band);
    CHECK(feel::parseCommand("B 6 4").column == 6);
    CHECK(feel::parseCommand("HL off").column == 255);
    CHECK(feel::parseCommand("HL 255").column == 255);
    CHECK(feel::parseCommand("CAL 3 -4.5").kind == CommandKind::Calibrate);
    CLOSE(feel::parseCommand("CAL 3 -4.5").offset, -4.5F);
    CHECK(feel::parseCommand("CAL save").kind == CommandKind::Save);
    CHECK(feel::parseCommand("US 0 900").kind == CommandKind::Pulse);
    CHECK(feel::parseCommand("US 6 2100").kind == CommandKind::Pulse);
}

TEST(serial_parser_rejects_unbounded_and_ambiguous_input) {
    const char* invalid[] = {"", "B", "B 0", "B 0 1 junk", "B -1 1", "B 7 1", "B 0 5", "B 0 1x",
        "B 0 999999999999999999999999", "HL 7", "HL -1", "CAL 0 nan", "CAL 0 inf", "CAL 0 5.1",
        "CAL 0 1e999", "CAL 0 -6", "CAL save junk", "US 0 650", "US 0 2500", "US 0 899", "US 0 2101", "US 0 65536", "ARM extra"};
    for (const char* line : invalid) CHECK(feel::parseCommand(line).kind == feel::CommandKind::Invalid);
    CHECK(feel::parseCommand(nullptr).kind == feel::CommandKind::Invalid);
    CHECK(feel::parseCommand(std::string(1000, 'A').c_str()).kind == feel::CommandKind::Invalid);
}

TEST(serial_commands_share_controller_watchdog_and_save_gate) {
    Controller c;
    CHECK(feel::executeCommand(c, feel::parseCommand("CAL save"), 0) == Result::NotArmed);
    CHECK(feel::executeCommand(c, feel::parseCommand("ARM"), 0) == Result::Ok);
    CHECK(feel::executeCommand(c, feel::parseCommand("B 1 4"), 0) == Result::Ok);
    CHECK(feel::executeCommand(c, feel::parseCommand("STATUS"), 500) == Result::Ok);
    neutral(c);
    CHECK(feel::executeCommand(c, feel::parseCommand("CAL save"), 501) == Result::SaveRequested);
}

TEST(seed_0xc0ffee_packet_fault_fuzz_preserves_output_bounds) {
    uint32_t seed = 0xC0FFEE;
    auto random = [&seed]() { seed = seed * 1664525U + 1013904223U; return seed; };
    Controller c;
    c.connect(0);
    for (uint32_t step = 0; step < 10000; ++step) {
        auto bytes = wire(static_cast<uint8_t>(step), static_cast<uint8_t>(step % 5));
        if (random() % 2) bytes[random() % 9] = static_cast<uint8_t>(random() >> 24);
        const uint32_t now = step * 17;
        const auto before = c.snapshot();
        const Result result = c.receive(bytes.data(), bytes.size(), now);
        const auto& after = c.snapshot();
        for (std::size_t i = 0; i < 7; ++i) {
            CHECK(after.bands[i] <= 4);
            CHECK(after.angles[i] >= 0 && after.angles[i] <= 120);
            CHECK(after.pulses[i] >= 900 && after.pulses[i] <= 2100);
        }
        if (result != Result::Ok && before.active && after.active) CHECK(before.bands == after.bands);
        CHECK(after.highlight < 7 || after.highlight == 255);
    }
}

TEST(calibration_records_reject_old_schema_and_corruption_atomically) {
    Controller original;
    CHECK(original.loadOffset(0, 4) == Result::Ok);
    auto record = feel::calibrationRecord(original);
    CHECK(std::string(feel::kCalibrationKey) == "offsets_120_v2");
    CHECK(std::string(feel::kCalibrationKey).size() <= 15);
    Controller restored;
    record.version = 1;
    CHECK(!feel::loadCalibration(restored, record));
    for (auto offset : restored.snapshot().offsets) CLOSE(offset, 0);
    record.version = feel::kCalibrationVersion;
    record.offsets[6] = std::numeric_limits<float>::quiet_NaN();
    CHECK(!feel::loadCalibration(restored, record));
    for (auto offset : restored.snapshot().offsets) CLOSE(offset, 0);
    record.offsets[6] = 5.01F;
    CHECK(!feel::loadCalibration(restored, record));
    for (auto offset : restored.snapshot().offsets) CLOSE(offset, 0);
    record.offsets[6] = -5;
    CHECK(feel::loadCalibration(restored, record));
    CLOSE(restored.snapshot().offsets[0], 4);
    CLOSE(restored.snapshot().offsets[6], -5);
    CHECK(!restored.snapshot().benchArmed && !restored.snapshot().active);
}

TEST(raw_pulse_roundtrip_and_timeout_cover_entire_120_degree_range) {
    for (uint16_t pulse = 900; pulse <= 2100; ++pulse) {
        Controller c;
        CHECK(c.loadOffset(0, 5) == Result::Ok);
        CHECK(c.arm(0) == Result::Ok);
        CHECK(c.benchPulse(0, pulse, 1) == Result::Ok);
        // Raw pulse bypasses calibration, including at the endpoints.
        CHECK(c.snapshot().pulses[0] == pulse);
        CLOSE(c.snapshot().angles[0], (pulse - 900) / 10.0F);
        CHECK(feel::angleToPulse(c.snapshot().angles[0]) == pulse);
        c.tick(501);
        neutral(c);
        const float angle = (pulse - 900) / 10.0F;
        const float gap = angle <= 40 ? 20 : angle <= 80 ? 60 : 100;
        CLOSE(c.snapshot().angles[0], gap + 5);
        CHECK(c.snapshot().pulses[0] >= 900 && c.snapshot().pulses[0] <= 2100);
    }
}

TEST(calibrated_bands_taps_and_failure_paths_never_exceed_design_range) {
    const float gaps[] = {20, 20, 60, 100};
    const float taps[] = {13, 27, 67, 107};
    for (int offset = -5; offset <= 5; ++offset) {
        for (uint8_t band = 1; band <= 4; ++band) {
            for (unsigned failure = 0; failure < 3; ++failure) {
                Controller c;
                CHECK(c.loadOffset(0, static_cast<float>(offset)) == Result::Ok);
                c.connect(0);
                CHECK(send(c, 0, band, 1, 0) == Result::Ok);
                CLOSE(c.snapshot().angles[0], taps[band - 1] + offset);
                c.tick(101);
                CHECK(c.snapshot().angles[0] >= 0 && c.snapshot().angles[0] <= 120);
                CHECK(c.snapshot().pulses[0] >= 900 && c.snapshot().pulses[0] <= 2100);
                if (failure == 0) c.tick(501);
                else if (failure == 1) c.disconnect(102);
                else c.stop(102);
                neutral(c);
                CLOSE(c.snapshot().angles[0], gaps[band - 1] + offset);
                CHECK(c.snapshot().pulses[0] >= 900 && c.snapshot().pulses[0] <= 2100);
            }
        }
    }
}

TEST(disabled_output_guard_rejects_all_physical_commands) {
    feel::OutputGuard guard(false, 0, 0);
    std::array<uint16_t, 7> pulses;
    pulses.fill(1500);
    CHECK(!guard.admit(pulses));
    CHECK(guard.state() == feel::OutputGuard::State::Disabled);
}

TEST(output_guard_latches_fault_for_any_out_of_measured_range_channel) {
    std::array<uint16_t, 7> pulses;
    pulses.fill(1500);
    for (std::size_t column = 0; column < 7; ++column) {
        feel::OutputGuard guard(true, 900, 2100);
        CHECK(guard.admit(pulses));
        pulses[column] = 899; // Outside this design and the configured measured range.
        CHECK(!guard.admit(pulses));
        CHECK(guard.state() == feel::OutputGuard::State::Fault);
        pulses[column] = 1500;
        CHECK(!guard.admit(pulses)); // Never silently recover motion after a fault.
    }
}

TEST(output_guard_rejects_bad_config_and_accepts_measured_boundary_only) {
    std::array<uint16_t, 7> pulses;
    pulses.fill(1500);
    feel::OutputGuard invalid(true, 2100, 900);
    CHECK(!invalid.admit(pulses));
    CHECK(invalid.state() == feel::OutputGuard::State::Fault);
    feel::OutputGuard guard(true, 900, 2100);
    pulses[0] = 900;
    pulses[6] = 2100;
    CHECK(guard.admit(pulses));
    pulses[6] = 2101;
    CHECK(!guard.admit(pulses));
}
}

int main() {
    unsigned failures = 0;
    for (const auto& test : tests()) {
        try { test.run(); std::cout << "PASS " << test.name << '\n'; }
        catch (const std::exception& e) { ++failures; std::cerr << "FAIL " << test.name << ": " << e.what() << '\n'; }
    }
    std::cout << tests().size() - failures << '/' << tests().size() << " firmware host tests passed; physical hardware NOT VERIFIED\n";
    return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
