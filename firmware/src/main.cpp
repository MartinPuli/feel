#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <esp_arduino_version.h>
#include <driver/ledc.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

#include <atomic>
#include <cstring>

#include "board_config.hpp"
#include "feel/commands.hpp"
#include "feel/calibration.hpp"
#include "feel/output_guard.hpp"
#include "feel/pwm.hpp"
#include "feel/serial_line.hpp"
#if FEEL_SEVEN_SERVO_LIVE
#include "feel/seven_live.hpp"
#if ESP_ARDUINO_VERSION_MAJOR != 2
#error "Seven-live requires the pinned Arduino-ESP32 2 toolchain"
#endif
#elif FEEL_SINGLE_SERVO_LIVE
#include "feel/single_live.hpp"
#elif FEEL_SINGLE_SERVO_DEMO
#include "feel/single_demo.hpp"
#endif

namespace {
feel::Controller controller;
Preferences preferences;
NimBLEServer* server = nullptr;
NimBLECharacteristic* statusCharacteristic = nullptr;
bool preferencesReady = false;
bool pwmReady = false;
feel::OutputGuard outputGuard(FEEL_ENABLE_SERVO_OUTPUT != 0,
    FEEL_VERIFIED_PULSE_MIN_US, FEEL_VERIFIED_PULSE_MAX_US);
constexpr uint8_t kPwmBits = feel::kServoPwmBits;
constexpr uint32_t kPwmFrequency = feel::kServoPwmHz;
uint16_t lastPulse[feel::kColumns]{};
std::atomic<bool> queueFault{false};
std::atomic<int> peerHandle{-1};

enum class EventKind : uint8_t { Connect, Disconnect, Packet };
struct Event {
    EventKind kind;
    uint32_t receivedMs;
    uint16_t connection;
    uint16_t length;
    uint8_t bytes[feel::kPacketBytes];
};
QueueHandle_t events = nullptr;

// Arduino AUTO can choose the 1 MHz reference clock on classic ESP32, yielding
// 49.920 Hz at 14 bits. APB has an exact nominal divider of 25000/256 for 50 Hz.
// Channels 0..6 share timers in pairs on both supported targets. This project
// does not enable dynamic frequency scaling or sleep.
#if SOC_LEDC_SUPPORT_HS_MODE
constexpr ledc_mode_t kPwmMode = LEDC_HIGH_SPEED_MODE;
#else
constexpr ledc_mode_t kPwmMode = LEDC_LOW_SPEED_MODE;
#endif
bool configurePwmTimer(uint8_t index) {
    ledc_timer_config_t timer = {};
    timer.speed_mode = kPwmMode;
    timer.duty_resolution = LEDC_TIMER_14_BIT;
    timer.timer_num = static_cast<ledc_timer_t>(index);
    timer.freq_hz = kPwmFrequency;
    timer.clk_cfg = LEDC_USE_APB_CLK;
    return ledc_timer_config(&timer) == ESP_OK &&
        ledc_get_freq(kPwmMode, timer.timer_num) == kPwmFrequency;
}

#if FEEL_SINGLE_SERVO_DEMO || FEEL_SINGLE_SERVO_LIVE
constexpr uint8_t kDemoPin = 33;
#if FEEL_SINGLE_SERVO_LIVE
#if FEEL_SINGLE_SERVO_WIDE
constexpr const char* kAdvertisedName = "FEEL Wide TEST";
constexpr const char* kSingleMode = "WIDE_UNVERIFIED";
constexpr uint16_t kSingleMinimumUs = 650;
constexpr uint16_t kSingleMaximumUs = feel::kSingleLiveMaximumUs;
constexpr std::size_t kSingleSector = feel::kSingleLiveSector;
constexpr const char* kSingleHelp = "EXPERIMENTAL ONE UNLOADED SERVO GPIO33:650..2648us; NOT verified travel or production; app may command endpoints; zero bands -> gap; serial STOP/disconnect detaches";
#else
constexpr const char* kAdvertisedName = "FEEL Puck";
constexpr const char* kSingleMode = "LIVE189_UNVERIFIED";
constexpr uint16_t kSingleMinimumUs = feel::kMinPulseUs;
constexpr uint16_t kSingleMaximumUs = feel::kSingleLiveMaximumUs;
constexpr std::size_t kSingleSector = feel::kSingleLiveSector;
constexpr const char* kSingleHelp = "ONE SERVO189 EXPERIMENT: center sector3 production band/gap/tap/calibration -> GPIO33, assumed650..2648us; NOT measured travel; STATUS or STOP; no serial motion/calibration";
#endif
#else
constexpr const char* kAdvertisedName = "FEEL Center Demo";
constexpr const char* kSingleMode = "DEMO";
constexpr uint16_t kSingleMinimumUs = 1450;
constexpr uint16_t kSingleMaximumUs = 1550;
constexpr std::size_t kSingleSector = feel::kDemoSector;
constexpr const char* kSingleHelp = "ONE SERVO: live iPhone center sector3 -> GPIO33,1450..1550us; STATUS or STOP; no bench or calibration commands";
#endif
bool demoReady = false;
bool demoAttached = false;
uint16_t demoPulse = 0;
uint32_t demoTimerHz = 0;
void detachDemo() {
    if (demoAttached) {
        ledcWrite(0, 0);
        ledcDetachPin(kDemoPin);
    }
    pinMode(kDemoPin, OUTPUT);
    digitalWrite(kDemoPin, LOW);
    demoAttached = false;
    demoPulse = 0;
}
void setupDemo() {
    detachDemo();
    const bool initialized = ledcSetup(0, kPwmFrequency, kPwmBits) != 0;
    const bool configured = initialized && configurePwmTimer(0);
    demoTimerHz = configured ? ledc_get_freq(kPwmMode, LEDC_TIMER_0) : 0;
    demoReady = configured && demoTimerHz == kPwmFrequency;
    ledcWrite(0, 0);
#if FEEL_SINGLE_SERVO_LIVE
    Serial.println(kSingleHelp);
    Serial.println("Boot output OFF; production center-column pulse only; other five servo GPIOs remain unattached");
#else
    Serial.println("ONE SERVO DEMO: center sector3 -> GPIO33, nominal1450..1550us; boot output OFF; cam mapping NOT enabled");
#endif
}
void writeDemo() {
#if FEEL_SINGLE_SERVO_LIVE
    #if FEEL_SINGLE_SERVO_WIDE
    const uint16_t pulse = feel::singleWidePulse(controller.snapshot());
#else
    const uint16_t pulse = feel::singleLivePulse(controller.snapshot());
#endif
#else
    const uint16_t pulse = feel::singleDemoPulse(controller.snapshot());
#endif
    if (!demoReady || pulse == 0) { detachDemo(); return; }
    uint32_t duty = 0;
    if (!feel::servoDuty(pulse, kSingleMinimumUs, kSingleMaximumUs, duty)) {
        demoReady = false;
        detachDemo();
        return;
    }
    if (!demoAttached) {
        ledcWrite(0, 0);
        ledcAttachPin(kDemoPin, 0);
        demoAttached = true;
    }
    if (demoPulse != pulse) {
        ledcWrite(0, duty);
        demoPulse = pulse;
    }
}
#else
constexpr const char* kAdvertisedName = "FEEL Puck";
#endif
#if FEEL_SEVEN_SERVO_LIVE
bool sevenReady = false;
bool sevenAttached = false;
constexpr const char* kSevenHelp = "SIX LIVE189 EXPERIMENT: GPIO33,25,26,27,14,13; +159us trim capped2648us; NOT measured safe travel; zero bands -> nearest gap; STATUS/HELP/STOP only";
void detachSeven() {
    for (std::size_t column = feel::kFirstActiveColumn; column < feel::kColumns; ++column) {
        if (sevenAttached) {
            ledcWrite(static_cast<uint8_t>(column), 0);
            ledcDetachPin(kServoPins[column]);
        }
        pinMode(kServoPins[column], OUTPUT);
        digitalWrite(kServoPins[column], LOW);
        lastPulse[column] = 0;
    }
    sevenAttached = false;
}
void setupSeven() {
    detachSeven();
    sevenReady = true;
    for (std::size_t column = feel::kFirstActiveColumn; column < feel::kColumns; ++column) {
        if (ledcSetup(static_cast<uint8_t>(column), kPwmFrequency, kPwmBits) == 0) sevenReady = false;
        ledcWrite(static_cast<uint8_t>(column), 0);
    }
    // Configure shared timers only after all sibling channels are initialized.
    for (uint8_t timer = 0; timer < (feel::kColumns + 1) / 2; ++timer) {
        if (!configurePwmTimer(timer)) sevenReady = false;
    }
    detachSeven();
    Serial.println(kSevenHelp);
    Serial.println(sevenReady ? "Six-live ready; boot outputs detached; physical validation pending" : "ERROR six-live timer setup; outputs detached");
}
void writeSeven() {
    if (!sevenReady) { detachSeven(); return; }
    feel::SevenLivePlan plan;
    const auto result = feel::sevenLivePlan(controller.snapshot(), plan);
    if (result != feel::SevenLiveResult::Ready) {
        if (result == feel::SevenLiveResult::Invalid) sevenReady = false; // Latched until reboot.
        detachSeven();
        return;
    }
    // All six active commands and quantized duties are validated before attachment.
    if (!sevenAttached) {
        for (std::size_t column = feel::kFirstActiveColumn; column < feel::kColumns; ++column) {
            ledcWrite(static_cast<uint8_t>(column), 0);
            ledcAttachPin(kServoPins[column], static_cast<uint8_t>(column));
        }
        sevenAttached = true;
    }
    for (std::size_t column = feel::kFirstActiveColumn; column < feel::kColumns; ++column) {
        if (lastPulse[column] != plan.pulses[column]) {
            ledcWrite(static_cast<uint8_t>(column), plan.duties[column]);
            lastPulse[column] = plan.pulses[column];
        }
    }
}
#endif
uint8_t reportedOutputState() {
#if FEEL_SEVEN_SERVO_LIVE
    return sevenReady ? 1 : 2;
#elif FEEL_SINGLE_SERVO_DEMO || FEEL_SINGLE_SERVO_LIVE
    return demoReady ? 1 : 2;
#else
    return static_cast<uint8_t>(outputGuard.state());
#endif
}

void enqueue(const Event& event) {
    if (xQueueSend(events, &event, 0) != pdTRUE) queueFault.store(true);
}

class ServerCallbacks final : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* source, NimBLEConnInfo& info) override {
        int expected = -1;
        if (!peerHandle.compare_exchange_strong(expected, info.getConnHandle())) {
            source->disconnect(info.getConnHandle());
            return;
        }
        Event event{};
        event.kind = EventKind::Connect;
        event.receivedMs = millis();
        event.connection = info.getConnHandle();
        enqueue(event);
    }
    void onDisconnect(NimBLEServer*, NimBLEConnInfo& info, int) override {
        int expected = info.getConnHandle();
        if (!peerHandle.compare_exchange_strong(expected, -1)) return;
        Event event{};
        event.kind = EventKind::Disconnect;
        event.receivedMs = millis();
        event.connection = info.getConnHandle();
        enqueue(event);
        NimBLEDevice::startAdvertising();
    }
};

class CommandCallbacks final : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* characteristic, NimBLEConnInfo& info) override {
        if (peerHandle.load() != info.getConnHandle()) return;
        const auto value = characteristic->getValue();
        Event event{};
        event.kind = EventKind::Packet;
        event.receivedMs = millis();
        event.connection = info.getConnHandle();
        // Preserve invalid length for decoder but never copy beyond nine bytes.
        event.length = static_cast<uint16_t>(value.size());
        if (value.size() == feel::kPacketBytes) std::memcpy(event.bytes, value.data(), feel::kPacketBytes);
        enqueue(event);
    }
};
ServerCallbacks serverCallbacks;
CommandCallbacks commandCallbacks;

void disablePWM() {
#if FEEL_SEVEN_SERVO_LIVE
    sevenReady = false;
    detachSeven();
    return;
#elif FEEL_SINGLE_SERVO_DEMO || FEEL_SINGLE_SERVO_LIVE
    demoReady = false;
    detachDemo();
    return;
#endif
    pwmReady = false;
    outputGuard.fault();
    // Leaving a failed channel's previous waveform running would bypass the
    // software watchdog. Detach every output; passive pin return still needs
    // physical validation and this is NOT an electrical power disconnect.
    for (uint8_t pin : kServoPins) { if (pin == 255) continue;
#if ESP_ARDUINO_VERSION_MAJOR >= 3
        ledcDetach(pin);
#else
        ledcDetachPin(pin);
#endif
        pinMode(pin, OUTPUT);
        digitalWrite(pin, LOW);
    }
}

void writePWM() {
#if FEEL_SEVEN_SERVO_LIVE
    writeSeven();
    return;
#elif FEEL_SINGLE_SERVO_DEMO || FEEL_SINGLE_SERVO_LIVE
    writeDemo();
    return;
#endif
    if (!pwmReady) return;
    const auto& state = controller.snapshot();
    if (!outputGuard.admit(state.pulses)) {
        disablePWM();
        controller.stop(millis());
        Serial.println("ERROR commanded pulse outside measured range; all outputs detached; remove servo power");
        return;
    }
    uint32_t duties[feel::kColumns]{};
    // Validate every quantized pulse before updating any channel.
    for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) {
        if (!feel::servoDuty(state.pulses[i], FEEL_VERIFIED_PULSE_MIN_US,
                             FEEL_VERIFIED_PULSE_MAX_US, duties[i])) {
            disablePWM();
            controller.stop(millis());
            Serial.println("ERROR pulse interval cannot be represented; all outputs detached");
            return;
        }
    }
    for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) {
        if (state.pulses[i] == lastPulse[i]) continue;
        const uint32_t duty = duties[i];
#if ESP_ARDUINO_VERSION_MAJOR >= 3
        if (!ledcWrite(kServoPins[i], duty)) {
            disablePWM();
            controller.stop(millis());
            Serial.println("ERROR PWM write failed; all outputs detached; remove servo power");
            return;
        }
#else
        ledcWrite(static_cast<uint8_t>(i), duty);
#endif
        lastPulse[i] = state.pulses[i];
    }
}

void setupPWM() {
#if FEEL_SEVEN_SERVO_LIVE
    setupSeven();
    return;
#elif FEEL_SINGLE_SERVO_DEMO || FEEL_SINGLE_SERVO_LIVE
    setupDemo();
    return;
#endif
    if (outputGuard.state() == feel::OutputGuard::State::Disabled) {
        for (uint8_t pin : kServoPins) { if (pin == 255) continue; pinMode(pin, OUTPUT); digitalWrite(pin, LOW); }
        Serial.println("SERVO OUTPUT DISABLED: FEEL_ENABLE_SERVO_OUTPUT=0; BLE/controller runs without physical PWM");
        return;
    }
    if (!outputGuard.admit(controller.snapshot().pulses)) {
        disablePWM();
        Serial.println("ERROR measured pulse range excludes initial neutral; outputs disabled");
        return;
    }
    pwmReady = true;
    for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
        if (!ledcAttachChannel(kServoPins[i], kPwmFrequency, kPwmBits, static_cast<int8_t>(i)) ||
            !ledcWrite(kServoPins[i], 0)) pwmReady = false;
#else
        // Initialize Arduino channel metadata while outputs remain detached.
        if (ledcSetup(static_cast<uint8_t>(i), kPwmFrequency, kPwmBits) == 0) pwmReady = false;
        ledcWrite(static_cast<uint8_t>(i), 0);
#endif
    }
    // Override AUTO only after every channel is initialized: initializing its
    // sibling channel would otherwise overwrite that shared timer's clock.
    if (pwmReady) {
        for (uint8_t timer = 0; timer < (feel::kColumns + 1) / 2; ++timer) {
            if (!configurePwmTimer(timer)) pwmReady = false;
        }
    }
    if (!pwmReady) {
        disablePWM();
        Serial.println("ERROR PWM setup failed; outputs detached; remove servo power");
        return;
    }
#if ESP_ARDUINO_VERSION_MAJOR < 3
    for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) {
        ledcAttachPin(kServoPins[i], static_cast<uint8_t>(i));
    }
#endif
    writePWM();
}

void sendStatus(bool serial) {
    const auto& s = controller.snapshot();
    // Versioned auxiliary status; command characteristic remains exactly 9 bytes.
    uint8_t status[15] = {1, static_cast<uint8_t>(s.connected), static_cast<uint8_t>(s.active),
        static_cast<uint8_t>(s.sequenceValid), s.lastSequence, static_cast<uint8_t>(s.highlight == 0 ? feel::kNoHighlight : s.highlight),
        static_cast<uint8_t>(s.benchArmed), reportedOutputState()};
    for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) status[8 + i] = s.bands[i];
    if (statusCharacteristic) {
        statusCharacteristic->setValue(status, sizeof(status));
        if (s.connected) statusCharacteristic->notify();
    }
    if (serial) {
#if FEEL_SEVEN_SERVO_LIVE
        Serial.printf("SIX_LIVE189_UNVERIFIED connected=%u active=%u ready=%u attached=%u accepted=%lu rejected=%lu timeouts=%lu\n",
            s.connected, s.active, sevenReady, sevenAttached,
            static_cast<unsigned long>(s.accepted), static_cast<unsigned long>(s.rejected), static_cast<unsigned long>(s.timeouts));
        for (std::size_t column = feel::kFirstActiveColumn; column < feel::kColumns; ++column) {
            Serial.printf("c%u gpio=%u band=%u pulseUs=%u timerHz=%lu\n", static_cast<unsigned>(column), kServoPins[column], s.bands[column], lastPulse[column],
                static_cast<unsigned long>(ledc_get_freq(kPwmMode, static_cast<ledc_timer_t>(column / 2))));
        }
        return;
#elif FEEL_SINGLE_SERVO_DEMO || FEEL_SINGLE_SERVO_LIVE
        Serial.printf("%s connected=%u active=%u ready=%u attached=%u gpio=33 sector=3 band=%u pulseUs=%u timerHz=%lu accepted=%lu rejected=%lu timeouts=%lu\n",
            kSingleMode, s.connected, s.active, demoReady, demoAttached, s.bands[kSingleSector], demoPulse,
            static_cast<unsigned long>(demoTimerHz), static_cast<unsigned long>(s.accepted),
            static_cast<unsigned long>(s.rejected), static_cast<unsigned long>(s.timeouts));
        return;
#endif
        Serial.printf("STATUS active=%d connected=%d armed=%d outputState=%u(0disabled/1ready/2fault) seq=%u accepted=%lu rejected=%lu timeouts=%lu\n",
            s.active, s.connected, s.benchArmed, static_cast<unsigned>(outputGuard.state()), s.lastSequence,
            static_cast<unsigned long>(s.accepted), static_cast<unsigned long>(s.rejected), static_cast<unsigned long>(s.timeouts));
        for (std::size_t i = feel::kFirstActiveColumn; i < feel::kColumns; ++i) Serial.printf("c%u b%u %.1fdeg %uus offset=%.1f\n",
            static_cast<unsigned>(i), s.bands[i], s.angles[i], s.pulses[i], s.offsets[i]);
    }
}

void serialCommand(const char* line, uint32_t now) {
    const auto command = feel::parseCommand(line);
#if FEEL_SEVEN_SERVO_LIVE || FEEL_SINGLE_SERVO_DEMO || FEEL_SINGLE_SERVO_LIVE
    if (command.kind != feel::CommandKind::Status && command.kind != feel::CommandKind::Stop && command.kind != feel::CommandKind::Help) {
        controller.stop(now);
        writePWM();
        Serial.println("ERROR live adapter accepts only STATUS, STOP, HELP; motion comes from live BLE");
        return;
    }
    if (command.kind == feel::CommandKind::Help) {
#if FEEL_SEVEN_SERVO_LIVE
        Serial.println(kSevenHelp);
#else
        Serial.println(kSingleHelp);
#endif
        return;
    }
#endif
    auto result = feel::executeCommand(controller, command, now);
    writePWM();
    if (result == feel::Result::SaveRequested) {
        // NVS writes only by explicit request; one versioned blob replaces all
        // offsets atomically within NVS, not seven separate writes.
        const auto record = feel::calibrationRecord(controller);
        controller.stop(millis());
        writePWM();
        const bool saved = preferencesReady && preferences.putBytes(feel::kCalibrationKey, &record, sizeof(record)) == sizeof(record);
        Serial.println(saved ? "OK offsets saved; outputs neutral; ARM again for bench" : "ERROR NVS save failed; offsets not persisted");
        return;
    }
    if (command.kind == feel::CommandKind::Help) {
        Serial.printf("ARM (disconnect BLE first; 30s bench lease), B c 0..4, HL c|off, CAL c -5..5, CAL save, US c %u..%u, KEEP, STOP, STATUS\n", feel::kMinPulseUs, feel::kMaxPulseUs);
        Serial.println("Motion expires at 500ms. Repeat KEEP every100ms only while supervising bench; ARM does not keep motion alive.");
    } else if (command.kind == feel::CommandKind::Status) sendStatus(true);
    else Serial.printf("%s\n", feel::resultName(result));
}

void readSerial(uint32_t now) {
    static feel::SerialLine input;
    // Bound work per loop; serial flooding cannot starve packet expiry.
    for (int budget = 0; budget < 96 && Serial.available(); ++budget) {
        const auto event = input.push(static_cast<uint8_t>(Serial.read()));
        if (event == feel::SerialLine::Event::Fault) {
            controller.stop(millis());
            writePWM();
            Serial.println("bad_command (invalid byte or line too long); stopped");
            return;
        }
        if (event == feel::SerialLine::Event::Line) {
            serialCommand(input.line(), now);
            return; // At most one command per loop.
        }
    }
}

void drainBLE() {
    if (queueFault.exchange(false)) {
        // Do not resurrect motion from queued data after transport overload.
        controller.disconnect(millis());
        writePWM();
        xQueueReset(events);
        const int peer = peerHandle.load();
        if (peer >= 0) server->disconnect(static_cast<uint16_t>(peer));
        Serial.println("ERROR BLE event overflow; neutral and disconnect");
        return;
    }
    Event event{};
    for (int budget = 0; budget < 16 && xQueueReceive(events, &event, 0) == pdTRUE; ++budget) {
        const uint32_t now = millis();
        if (event.kind == EventKind::Disconnect) controller.disconnect(now);
        else if (event.kind == EventKind::Connect) controller.connect(now);
        else if (static_cast<uint32_t>(now - event.receivedMs) < feel::kWatchdogMs) {
            // Receipt time, never drain time, controls freshness.
            controller.receive(event.bytes, event.length, event.receivedMs);
        }
    }
    controller.tick(millis());
    // No intermediate PWM between queue entries. Expired queued packets can
    // never briefly actuate the output while the loop catches up.
}
}

void setup() {
    Serial.begin(115200);
    Serial.printf("FEEL V1 greenfield | %s | physical validation pending\n", kBoardName);
    preferencesReady = preferences.begin("feel", false);
    if (preferencesReady && preferences.getBytesLength(feel::kCalibrationKey) == sizeof(feel::CalibrationRecord)) {
        feel::CalibrationRecord record;
        if (preferences.getBytes(feel::kCalibrationKey, &record, sizeof(record)) != sizeof(record) ||
            !feel::loadCalibration(controller, record)) {
            Serial.println("ERROR stored 175-degree calibration invalid; all offsets default to0");
        }
    }
    controller.tick(millis());
    setupPWM();
    events = xQueueCreate(16, sizeof(Event));
    if (!events) {
        Serial.println("ERROR event queue allocation; BLE disabled, remove servo power");
        return;
    }
    NimBLEDevice::init(kAdvertisedName);
    server = NimBLEDevice::createServer();
    server->setCallbacks(&serverCallbacks, false);
    NimBLEService* service = server->createService(kServiceUUID);
    auto* command = service->createCharacteristic(kCommandUUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR, 512);
    command->setCallbacks(&commandCallbacks);
    statusCharacteristic = service->createCharacteristic(kStatusUUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    service->start();
    auto* advertising = NimBLEDevice::getAdvertising();
    advertising->addServiceUUID(kServiceUUID);
    advertising->setName(kAdvertisedName);
    advertising->enableScanResponse(true);
    advertising->start();
    sendStatus(false);
    Serial.println("Ready; HELP for bench instructions; PWM positions unverified on real FS0307.");
}

void loop() {
    if (events) drainBLE();
    const uint32_t now = millis();
    controller.tick(now);
    writePWM();
    readSerial(now);
    static uint32_t lastStatus = 0;
    if (static_cast<uint32_t>(now - lastStatus) >= 200) {
        lastStatus = now;
        sendStatus(false);
    }
    delay(2);
}
