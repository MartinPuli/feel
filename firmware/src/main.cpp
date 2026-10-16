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
#include "feel/output_guard.hpp"

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
        static_cast<uint8_t>(s.benchArmed), static_cast<uint8_t>(outputGuard.state())};
    for (std::size_t i = 0; i < feel::kColumns; ++i) status[8 + i] = s.bands[i];
    if (statusCharacteristic) {
        statusCharacteristic->setValue(status, sizeof(status));
        if (s.connected) statusCharacteristic->notify();
    }
    if (serial) {
        Serial.printf("STATUS active=%d connected=%d armed=%d outputState=%u(0disabled/1ready/2fault) seq=%u accepted=%lu rejected=%lu timeouts=%lu\n",
            s.active, s.connected, s.benchArmed, static_cast<unsigned>(outputGuard.state()), s.lastSequence,
            static_cast<unsigned long>(s.accepted), static_cast<unsigned long>(s.rejected), static_cast<unsigned long>(s.timeouts));
        for (std::size_t i = 0; i < feel::kColumns; ++i) Serial.printf("c%u b%u %.1fdeg %uus offset=%.1f\n",
            static_cast<unsigned>(i), s.bands[i], s.angles[i], s.pulses[i], s.offsets[i]);
    }
}

void serialCommand(const char* line, uint32_t now) {
    const auto command = feel::parseCommand(line);
    auto result = feel::executeCommand(controller, command, now);
    writePWM();
    if (result == feel::Result::SaveRequested) {
        // NVS writes only by explicit request; one versioned blob replaces all
        // offsets atomically within NVS, not seven separate writes.
        const auto offsets = controller.snapshot().offsets;
        controller.stop(millis());
        writePWM();
        const bool saved = preferencesReady && preferences.putBytes("offsets_v1", offsets.data(), sizeof(offsets)) == sizeof(offsets);
        Serial.println(saved ? "OK offsets saved; outputs neutral; ARM again for bench" : "ERROR NVS save failed; offsets not persisted");
        return;
    }
    if (command.kind == feel::CommandKind::Help) {
        Serial.println("ARM (disconnect BLE first; 30s bench lease), B c 0..4, HL c|off, CAL c -5..5, CAL save, US c 650..2500, KEEP, STOP, STATUS");
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
    if (preferencesReady && preferences.getBytesLength("offsets_v1") == sizeof(std::array<float, feel::kColumns>)) {
        std::array<float, feel::kColumns> offsets{};
        if (preferences.getBytes("offsets_v1", offsets.data(), sizeof(offsets)) == sizeof(offsets)) {
            bool valid = true;
            feel::Controller verifier;
            for (std::size_t i = 0; i < feel::kColumns; ++i) {
                if (verifier.loadOffset(i, offsets[i]) != feel::Result::Ok) valid = false;
            }
            if (valid) for (std::size_t i = 0; i < feel::kColumns; ++i) controller.loadOffset(i, offsets[i]);
            else Serial.println("ERROR stored calibration invalid; all offsets default to0");
        }
    }
    controller.tick(millis());
    setupPWM();
    events = xQueueCreate(16, sizeof(Event));
    if (!events) {
        Serial.println("ERROR event queue allocation; BLE disabled, remove servo power");
        return;
    }
    NimBLEDevice::init("FEEL Puck");
    server = NimBLEDevice::createServer();
    server->setCallbacks(&serverCallbacks, false);
    NimBLEService* service = server->createService(kServiceUUID);
    auto* command = service->createCharacteristic(kCommandUUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR, 512);
    command->setCallbacks(&commandCallbacks);
    statusCharacteristic = service->createCharacteristic(kStatusUUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    service->start();
    auto* advertising = NimBLEDevice::getAdvertising();
    advertising->addServiceUUID(kServiceUUID);
    advertising->setName("FEEL Puck");
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
