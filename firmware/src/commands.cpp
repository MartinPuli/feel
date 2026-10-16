#include "feel/commands.hpp"

#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <cstring>

namespace feel {
namespace {
bool integer(const char* token, unsigned maximum, unsigned& value) {
    if (!token || token[0] < '0' || token[0] > '9') return false;
    char* end = nullptr;
    errno = 0;
    const unsigned long parsed = std::strtoul(token, &end, 10);
    if (errno != 0 || *end != '\0' || parsed > maximum) return false;
    value = static_cast<unsigned>(parsed);
    return true;
}
}

Command parseCommand(const char* line) {
    Command command;
    if (!line || std::strlen(line) >= 96) return command;
    char copy[96];
    std::strcpy(copy, line);
    char* tokens[5]{};
    std::size_t count = 0;
    char* context = nullptr;
    char* token = strtok_r(copy, " \t\r\n", &context);
    while (token && count < 5) {
        tokens[count++] = token;
        token = strtok_r(nullptr, " \t\r\n", &context);
    }
    if (!count || count >= 5) return command;
    if (count == 1) {
        if (!std::strcmp(tokens[0], "ARM")) command.kind = CommandKind::Arm;
        else if (!std::strcmp(tokens[0], "STOP")) command.kind = CommandKind::Stop;
        else if (!std::strcmp(tokens[0], "KEEP")) command.kind = CommandKind::Keep;
        else if (!std::strcmp(tokens[0], "STATUS")) command.kind = CommandKind::Status;
        else if (!std::strcmp(tokens[0], "HELP")) command.kind = CommandKind::Help;
        return command;
    }
    unsigned column = 0;
    unsigned value = 0;
    if (count == 2 && !std::strcmp(tokens[0], "HL")) {
        if (!std::strcmp(tokens[1], "off") || !std::strcmp(tokens[1], "255")) {
            command.kind = CommandKind::Highlight;
            command.column = kNoHighlight;
        } else if (integer(tokens[1], kColumns - 1, column)) {
            command.kind = CommandKind::Highlight;
            command.column = static_cast<uint8_t>(column);
        }
    } else if (count == 2 && !std::strcmp(tokens[0], "CAL") && !std::strcmp(tokens[1], "save")) {
        command.kind = CommandKind::Save;
    } else if (count == 3 && integer(tokens[1], kColumns - 1, column)) {
        command.column = static_cast<uint8_t>(column);
        if (!std::strcmp(tokens[0], "B") && integer(tokens[2], 4, value)) {
            command.kind = CommandKind::Band;
            command.value = static_cast<uint16_t>(value);
        } else if (!std::strcmp(tokens[0], "US") && integer(tokens[2], kMaxPulseUs, value) && value >= kMinPulseUs) {
            command.kind = CommandKind::Pulse;
            command.value = static_cast<uint16_t>(value);
        } else if (!std::strcmp(tokens[0], "CAL")) {
            char* end = nullptr;
            errno = 0;
            const float offset = std::strtof(tokens[2], &end);
            if (errno == 0 && *end == '\0' && end != tokens[2] && std::isfinite(offset) && offset >= -5 && offset <= 5) {
                command.kind = CommandKind::Calibrate;
                command.offset = offset;
            }
        }
    }
    return command;
}

Result executeCommand(Controller& controller, const Command& command, uint32_t now) {
    controller.tick(now);
    switch (command.kind) {
    case CommandKind::Arm: return controller.arm(now);
    case CommandKind::Stop: controller.stop(now); return Result::Ok;
    case CommandKind::Keep: return controller.keepAlive(now);
    case CommandKind::Band: return controller.benchBand(command.column, static_cast<uint8_t>(command.value), now);
    case CommandKind::Highlight: return controller.benchHighlight(command.column, now);
    case CommandKind::Calibrate: return controller.calibrate(command.column, command.offset, now);
    case CommandKind::Pulse: return controller.benchPulse(command.column, command.value, now);
    case CommandKind::Save: return controller.benchArmed() ? Result::SaveRequested : Result::NotArmed;
    case CommandKind::Status:
    case CommandKind::Help: return Result::Ok;
    case CommandKind::Invalid: return Result::BadCommand;
    }
    return Result::BadCommand;
}
} // namespace feel
