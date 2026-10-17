#pragma once
#include <cstddef>
#include <cstdint>

namespace feel {
// Byte-oriented framing before the C-string command parser. Invalid input must
// never turn into a valid prefix (e.g. a command followed by NUL and garbage).
class SerialLine {
public:
    enum class Event { None, Line, Fault };
    Event push(uint8_t byte) {
        if (byte == '\n') {
            const bool invalid = discarding_;
            line_[used_] = '\0';
            used_ = 0;
            discarding_ = false;
            return invalid ? Event::None : Event::Line;
        }
        if (discarding_) return Event::None;
        if ((byte != '\t' && byte != '\r' && (byte < 32 || byte > 126)) ||
            used_ >= sizeof(line_) - 1) {
            used_ = 0;
            discarding_ = true;
            return Event::Fault;
        }
        line_[used_++] = static_cast<char>(byte);
        return Event::None;
    }
    const char* line() const { return line_; }
private:
    char line_[96]{};
    std::size_t used_ = 0;
    bool discarding_ = false;
};
} // namespace feel
