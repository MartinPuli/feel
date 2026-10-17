#pragma once
#include <cstdint>
#include "feel/controller.hpp"

#ifndef FEEL_ENABLE_SERVO_OUTPUT
#define FEEL_ENABLE_SERVO_OUTPUT 0
#endif
#ifndef FEEL_SINGLE_SERVO_DEMO
#define FEEL_SINGLE_SERVO_DEMO 0
#endif
#if FEEL_SINGLE_SERVO_DEMO && FEEL_ENABLE_SERVO_OUTPUT
#error "Single-servo demo cannot enable the production seven-servo output"
#endif
#if FEEL_SINGLE_SERVO_DEMO && (!defined(FEEL_BOARD_CLASSIC) || defined(FEEL_BOARD_S3))
#error "Single-servo demo requires the explicit classic ESP32 board"
#endif
#if FEEL_ENABLE_SERVO_OUTPUT
#ifndef FEEL_VERIFIED_PULSE_MIN_US
#error "Servo output requires explicit FEEL_VERIFIED_PULSE_MIN_US from the actual unit's measured safe range"
#endif
#ifndef FEEL_VERIFIED_PULSE_MAX_US
#error "Servo output requires explicit FEEL_VERIFIED_PULSE_MAX_US from the actual unit's measured safe range"
#endif
static_assert(FEEL_VERIFIED_PULSE_MIN_US >= feel::kMinPulseUs && FEEL_VERIFIED_PULSE_MAX_US <= feel::kMaxPulseUs &&
    FEEL_VERIFIED_PULSE_MIN_US < FEEL_VERIFIED_PULSE_MAX_US,
    "Measured output guard must be ordered within the controller's 900..2100us service range");
#else
#define FEEL_VERIFIED_PULSE_MIN_US 0
#define FEEL_VERIFIED_PULSE_MAX_US 0
#endif

// FEEL's handoff only specified classic ESP32 pins. The S3 assignment is NEW,
// board-specific and must be checked against the actual module before wiring.
#if defined(FEEL_BOARD_CLASSIC) || defined(CONFIG_IDF_TARGET_ESP32)
constexpr uint8_t kServoPins[] = {32, 33, 25, 26, 27, 14, 13};
constexpr const char* kBoardName = "ESP32 classic";
#elif defined(FEEL_BOARD_S3) || defined(CONFIG_IDF_TARGET_ESP32S3)
constexpr uint8_t kServoPins[] = {4, 5, 6, 7, 8, 9, 10};
constexpr const char* kBoardName = "ESP32-S3 DevKitC-1 (assumed GPIO4-10)";
#else
#error "Select supported FEEL ESP32 classic or ESP32-S3 board and verify its pins"
#endif
constexpr const char* kServiceUUID = "7D2A0001-5C6B-4F9A-8E21-0BCE7F0A1000";
constexpr const char* kCommandUUID = "7D2A0002-5C6B-4F9A-8E21-0BCE7F0A1000";
constexpr const char* kStatusUUID = "7D2A0003-5C6B-4F9A-8E21-0BCE7F0A1000";
