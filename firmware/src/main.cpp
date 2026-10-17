#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <esp_arduino_version.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

#include <atomic>
#include <cstring>

#include "board_config.hpp"
#include "feel/commands.hpp"
#include "feel/calibration.hpp"
#include "feel/output_guard.hpp"
#if FEEL_SINGLE_SERVO_DEMO
#include <driver/ledc.h>
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
constexpr uint8_t kPwmBits = 14; // S3 supports 14, not classic's optional 20.
constexpr uint32_t kPwmFrequency = 50;
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

#if FEEL_SINGLE_SERVO_DEMO
constexpr uint8_t kDemoPin = 32;
constexpr const char* kAdvertisedName = "FEEL Center Demo";
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
    ledc_timer_config_t timer = {};
    timer.speed_mode = LEDC_HIGH_SPEED_MODE;
    timer.duty_resolution = LEDC_TIMER_14_BIT;
    timer.timer_num = LEDC_TIMER_0;
    timer.freq_hz = kPwmFrequency;
    timer.clk_cfg = LEDC_USE_APB_CLK;
    const bool configured = initialized && ledc_timer_config(&timer) == ESP_OK;
    demoTimerHz = configured ? ledc_get_freq(LEDC_HIGH_SPEED_MODE, LEDC_TIMER_0) : 0;
    demoReady = configured && demoTimerHz == kPwmFrequency;
    ledcWrite(0, 0);
    Serial.println("ONE SERVO DEMO: center sector3 -> GPIO32, nominal1450..1550us; boot output OFF; cam mapping NOT enabled");
}
void writeDemo() {
    const uint16_t pulse = feel::singleDemoPulse(controller.snapshot());
    if (!demoReady || pulse == 0) { detachDemo(); return; }
    if (pulse < 1450 || pulse > 1550) {
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
        const uint32_t duty = (static_cast<uint32_t>(pulse) * (1UL << kPwmBits) + 10000UL) / 20000UL;
        ledcWrite(0, duty);
        demoPulse = pulse;
    }
}
#else
constexpr const char* kAdvertisedName = "FEEL Puck";
#endif
uint8_t reportedOutputState() {
#if FEEL_SINGLE_SERVO_DEMO
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
#if FEEL_SINGLE_SERVO_DEMO
    demoReady = false;
    detachDemo();
    return;
#endif
    pwmReady = false;
    outputGuard.fault();
    // Leaving a failed channel's previous waveform running would bypass the
    // software watchdog. Detach every output; passive pin return still needs
    // physical validation and this is NOT an electrical power disconnect.
    for (uint8_t pin : kServoPins) {
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
#if FEEL_SINGLE_SERVO_DEMO
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
    for (std::size_t i = 0; i < feel::kColumns; ++i) {
        if (state.pulses[i] == lastPulse[i]) continue;
        const uint32_t duty = (static_cast<uint32_t>(state.pulses[i]) * ((1UL << kPwmBits) - 1UL) + 10000UL) / 20000UL;
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
#if FEEL_SINGLE_SERVO_DEMO
    setupDemo();
    return;
#endif
    if (outputGuard.state() == feel::OutputGuard::State::Disabled) {
        for (uint8_t pin : kServoPins) { pinMode(pin, OUTPUT); digitalWrite(pin, LOW); }
        Serial.println("SERVO OUTPUT DISABLED: FEEL_ENABLE_SERVO_OUTPUT=0; BLE/controller runs without physical PWM");
        return;
    }
    if (!outputGuard.admit(controller.snapshot().pulses)) {
        disablePWM();
        Serial.println("ERROR measured pulse range excludes initial neutral; outputs disabled");
        return;
    }
    pwmReady = true;
    for (std::size_t i = 0; i < feel::kColumns; ++i) {
#if ESP_ARDUINO_VERSION_MAJOR >= 3
        if (!ledcAttachChannel(kServoPins[i], kPwmFrequency, kPwmBits, static_cast<int8_t>(i))) pwmReady = false;
#else
        if (ledcSetup(static_cast<uint8_t>(i), kPwmFrequency, kPwmBits) == 0) pwmReady = false;
        ledcAttachPin(kServoPins[i], static_cast<uint8_t>(i));
#endif
    }
    if (!pwmReady) {
        disablePWM();
        Serial.println("ERROR PWM setup failed; outputs detached; remove servo power");
        return;
    }
    writePWM();
}

void sendStatus(bool serial) {
    const auto& s = controller.snapshot();
    // Versioned auxiliary status; command characteristic remains exactly 9 bytes.
    uint8_t status[15] = {1, static_cast<uint8_t>(s.connected), static_cast<uint8_t>(s.active),
        static_cast<uint8_t>(s.sequenceValid), s.lastSequence, s.highlight,
        static_cast<uint8_t>(s.benchArmed), reportedOutputState()};
    for (std::size_t i = 0; i < feel::kColumns; ++i) status[8 + i] = s.bands[i];
    if (statusCharacteristic) {
        statusCharacteristic->setValue(status, sizeof(status));
        if (s.connected) statusCharacteristic->notify();
    }
    if (serial) {
#if FEEL_SINGLE_SERVO_DEMO
        Serial.printf("DEMO connected=%u active=%u ready=%u attached=%u gpio=32 sector=3 band=%u pulseUs=%u timerHz=%lu accepted=%lu rejected=%lu timeouts=%lu\n",
            s.connected, s.active, demoReady, demoAttached, s.bands[feel::kDemoSector], demoPulse,
            static_cast<unsigned long>(demoTimerHz), static_cast<unsigned long>(s.accepted),
            static_cast<unsigned long>(s.rejected), static_cast<unsigned long>(s.timeouts));
        return;
#endif
        Serial.printf("STATUS active=%d connected=%d armed=%d outputState=%u(0disabled/1ready/2fault) seq=%u accepted=%lu rejected=%lu timeouts=%lu\n",
            s.active, s.connected, s.benchArmed, static_cast<unsigned>(outputGuard.state()), s.lastSequence,
            static_cast<unsigned long>(s.accepted), static_cast<unsigned long>(s.rejected), static_cast<unsigned long>(s.timeouts));
        for (std::size_t i = 0; i < feel::kColumns; ++i) Serial.printf("c%u b%u %.1fdeg %uus offset=%.1f\n",
            static_cast<unsigned>(i), s.bands[i], s.angles[i], s.pulses[i], s.offsets[i]);
    }
}

void serialCommand(const char* line, uint32_t now) {
    const auto command = feel::parseCommand(line);
#if FEEL_SINGLE_SERVO_DEMO
    if (command.kind != feel::CommandKind::Status && command.kind != feel::CommandKind::Stop && command.kind != feel::CommandKind::Help) {
        controller.stop(now);
        writePWM();
        Serial.println("ERROR demo accepts only STATUS, STOP, HELP; motion comes from live BLE");
        return;
    }
    if (command.kind == feel::CommandKind::Help) {
        Serial.println("ONE SERVO: live iPhone center sector3 -> GPIO32,1450..1550us; STATUS or STOP; no bench or calibration commands");
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
    static char line[96]{};
    static std::size_t used = 0;
    static bool overflow = false;
    // Bound work per loop; serial flooding cannot starve packet expiry.
    for (int budget = 0; budget < 96 && Serial.available(); ++budget) {
        const char c = static_cast<char>(Serial.read());
        if (c == '\n') {
            if (!overflow) { line[used] = '\0'; serialCommand(line, now); }
            else Serial.println("bad_command (line too long)");
            used = 0;
            overflow = false;
            return; // At most one command per loop.
        }
        if (c == '\r') continue;
        if (used < sizeof(line) - 1 && !overflow) line[used++] = c;
        else overflow = true;
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
            Serial.println("ERROR stored 120-degree calibration invalid; all offsets default to0");
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
