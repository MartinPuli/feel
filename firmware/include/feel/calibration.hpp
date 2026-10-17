#pragma once
#include "feel/controller.hpp"

namespace feel {
// New key AND schema prevent the old 175-degree calibration from being reused.
// NVS keys are limited to 15 characters. No migration from offsets_v1 is valid.
constexpr char kCalibrationKey[] = "offsets_120_v2";
constexpr uint32_t kCalibrationVersion = 2;
struct CalibrationRecord {
    uint32_t version = kCalibrationVersion;
    std::array<float, kColumns> offsets{};
};

inline CalibrationRecord calibrationRecord(const Controller& controller) {
    CalibrationRecord record;
    record.offsets = controller.snapshot().offsets;
    return record;
}

// Boot only. Validate the whole record first, so a corrupt later column cannot
// leave earlier columns partially calibrated. This never arms physical output.
inline bool loadCalibration(Controller& controller, const CalibrationRecord& record) {
    if (record.version != kCalibrationVersion) return false;
    Controller verifier;
    for (std::size_t i = 0; i < kColumns; ++i) {
        if (verifier.loadOffset(i, record.offsets[i]) != Result::Ok) return false;
    }
    for (std::size_t i = 0; i < kColumns; ++i) controller.loadOffset(i, record.offsets[i]);
    return true;
}
} // namespace feel
