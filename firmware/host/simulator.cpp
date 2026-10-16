#include "feel/commands.hpp"

#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <string>
#include <vector>

namespace {
bool number(const std::string& token, uint32_t maximum, uint32_t& value) {
    if (token.empty() || token[0] < '0' || token[0] > '9') return false;
    char* end = nullptr;
    errno = 0;
    const unsigned long long parsed = std::strtoull(token.c_str(), &end,
        token.size() > 2 && token.substr(0, 2) == "0x" ? 16 : 10);
    if (errno || *end != '\0' || parsed > maximum) return false;
    value = static_cast<uint32_t>(parsed);
    return true;
}

template<typename T, std::size_t N>
void array(const std::array<T, N>& values) {
    std::cout << '[';
    for (std::size_t i = 0; i < N; ++i) {
        if (i) std::cout << ',';
        std::cout << +values[i];
    }
    std::cout << ']';
}

void emit(const feel::Controller& controller, uint32_t now, const char* result) {
    const auto& s = controller.snapshot();
    std::cout << "{\"mode\":\"SIMULATION\",\"production_controller\":true,\"now_ms\":" << now
        << ",\"result\":\"" << result << "\",\"bands\":";
    array(s.bands);
    std::cout << ",\"angles_deg\":"; array(s.angles);
    std::cout << ",\"pulses_us\":"; array(s.pulses);
    std::cout << ",\"offsets_deg\":"; array(s.offsets);
    std::cout << ",\"highlight\":" << +s.highlight << ",\"tap_active\":" << s.tapActive
        << ",\"connected\":" << s.connected << ",\"active\":" << s.active
        << ",\"seq_valid\":" << s.sequenceValid << ",\"last_seq\":" << +s.lastSequence
        << ",\"bench_armed\":" << s.benchArmed << ",\"raw_pulse\":" << s.rawPulse
        << ",\"accepted\":" << s.accepted << ",\"rejected\":" << s.rejected
        << ",\"timeouts\":" << s.timeouts << "}\n";
}

void usage() {
    std::cout << "FEEL production controller simulator (no hardware model).\n"
        "One line command => one JSON state. Bytes: decimal or 0x-prefixed hex.\n"
        "CONNECT ms | DISCONNECT ms | TICK ms | STATE ms | RESET ms\n"
        "PACKET ms byte... (pass any length to exercise decoder)\n"
        "DECODE ms byte... (wire decoder only, connection independent)\n"
        "ARM ms | STOP ms | KEEP ms | BAND ms column band\n"
        "HL ms column_or_off | CAL ms column offset | US ms column pulse\n"
        "Unsigned uint32 ms; monotonically increasing modulo 2^32.\n"
        "Start with CONNECT before BLE packets; DISCONNECT before ARM.\n";
}
}

int main(int argc, char** argv) {
    if (argc > 1) {
        usage();
        return std::string(argv[1]) == "--help" && argc == 2 ? 0 : 2;
    }
    std::cout << std::boolalpha << std::setprecision(7);
    feel::Controller controller;
    std::string line;
    uint32_t now = 0;
    while (std::getline(std::cin, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream stream(line);
        std::vector<std::string> words;
        std::string word;
        while (stream >> word) words.push_back(word);
        if (words.size() < 2 || !number(words[1], UINT32_MAX, now)) {
            emit(controller, now, "bad_command");
            continue;
        }
        feel::Result result = feel::Result::Ok;
        if (words[0] == "PACKET" || words[0] == "DECODE") {
            std::vector<uint8_t> bytes;
            bool valid = true;
            for (std::size_t i = 2; i < words.size(); ++i) {
                uint32_t value;
                if (!number(words[i], 255, value)) { valid = false; break; }
                bytes.push_back(static_cast<uint8_t>(value));
            }
            if (!valid) result = feel::Result::BadCommand;
            else if (words[0] == "DECODE") {
                feel::Packet packet;
                result = feel::decodePacket(bytes.data(), bytes.size(), packet);
            } else result = controller.receive(bytes.data(), bytes.size(), now);
        } else if (words.size() == 2 && words[0] == "CONNECT") controller.connect(now);
        else if (words.size() == 2 && words[0] == "DISCONNECT") controller.disconnect(now);
        else if (words.size() == 2 && words[0] == "RESET") controller = feel::Controller();
        else if (words.size() == 2 && (words[0] == "TICK" || words[0] == "STATE")) controller.tick(now);
        else {
            std::string serial = words[0] == "BAND" ? "B" : words[0];
            for (std::size_t i = 2; i < words.size(); ++i) serial += " " + words[i];
            result = feel::executeCommand(controller, feel::parseCommand(serial.c_str()), now);
        }
        emit(controller, now, feel::resultName(result));
    }
}
