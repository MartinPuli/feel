#pragma once

#include "feel/controller.hpp"

namespace feel {
enum class CommandKind { Invalid, Arm, Stop, Keep, Band, Highlight, Calibrate, Save, Pulse, Status, Help };
struct Command {
    CommandKind kind = CommandKind::Invalid;
    uint8_t column = 0;
    uint16_t value = 0;
    float offset = 0;
};
// Bounded, strict, allocation-free parser shared by the physical serial adapter
// and host tests. No trailing text, negative indexes, NaNs, or numeric overflow.
Command parseCommand(const char* line);
Result executeCommand(Controller& controller, const Command& command, uint32_t now);
} // namespace feel
