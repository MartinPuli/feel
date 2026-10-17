#include <Arduino.h>
#include <driver/ledc.h>
#include "bench.hpp"

// Standalone classic ESP32 characterization build. No BLE or production control.
#if !defined(CONFIG_IDF_TARGET_ESP32)
#error "This bench build is only for the classic ESP32, GPIO32"
#endif
constexpr uint8_t kPin = 32;
constexpr uint8_t kChannel = 0;
constexpr uint32_t kPeriodUs = 20000;
constexpr uint8_t kBits = 14;
single_servo::State state;
bool attached = false;
unsigned lastPulseUs = 0;
bool timerReady = false;
uint32_t timerHz = 0;
char line[24];
size_t used = 0;
bool discard = false;

void applyOutput() {
    if (state.active && timerReady) {
        const unsigned pulse = state.pulseUs(millis());
        if (!attached) {
            ledcWrite(kChannel, 0);
            ledcAttachPin(kPin, kChannel);
            attached = true;
            lastPulseUs = 0;
        }
        if (pulse != lastPulseUs) {
            const uint32_t duty = (pulse * (1UL << kBits) + kPeriodUs / 2) / kPeriodUs;
            ledcWrite(kChannel, duty);
            lastPulseUs = pulse;
        }
    } else if (!state.active && attached) {
        ledcWrite(kChannel, 0);
        ledcDetachPin(kPin);
        pinMode(kPin, OUTPUT);
        digitalWrite(kPin, LOW);
        attached = false;
        lastPulseUs = 0;
    }
}
void reply(const char* text) {
    const size_t size = std::strlen(text);
    // Drop an observation rather than block the motion watchdog on a full TX queue.
    if (Serial.availableForWrite() >= static_cast<int>(size)) Serial.write(reinterpret_cast<const uint8_t*>(text), size);
}
void status() {
    char message[128];
    snprintf(message, sizeof(message), "SINGLE_BENCH ready=%u armed=%u active=%u attached=%u gpio=32 pulseUs=%u timerHz=%u\n",
             timerReady, state.armed, state.active, attached, state.pulseUs(millis()), timerHz);
    reply(message);
}
void setup() {
    pinMode(kPin, OUTPUT);
    digitalWrite(kPin, LOW);
    Serial.begin(115200);
    const bool initialized = ledcSetup(kChannel, 50, kBits) != 0;
    // Arduino AUTO selected a quantized reference clock and reported49 Hz on
    // this board. Pin channel0/timer0 to APB: 80 MHz / (97.65625 * 16384) =50 Hz.
    // No dynamic frequency scaling or sleep is enabled in this bench project.
    ledc_timer_config_t timer = {};
    timer.speed_mode = LEDC_HIGH_SPEED_MODE;
    timer.duty_resolution = LEDC_TIMER_14_BIT;
    timer.timer_num = LEDC_TIMER_0;
    timer.freq_hz = 50;
    timer.clk_cfg = LEDC_USE_APB_CLK;
    const bool configured = initialized && ledc_timer_config(&timer) == ESP_OK;
    timerHz = configured ? ledc_get_freq(LEDC_HIGH_SPEED_MODE, LEDC_TIMER_0) : 0;
    timerReady = configured && timerHz == 50;
    ledcWrite(kChannel, 0); // Do not attach on boot.
    Serial.println("FEEL SINGLE BENCH: output OFF; ARM then CENTER, TEST5, SWEEP 1 (up) or SWEEP 0 (down); STOP always available");
    status();
}
void loop() {
    state.tick(millis());
    applyOutput();
    // Bounded parsing: even a serial flood cannot starve the timeout check.
    for (unsigned budget = 0; budget < 32 && Serial.available(); ++budget) {
        const char c = static_cast<char>(Serial.read());
        if (c == '\r') continue;
        if (c == '\n') {
            if (!discard) {
                line[used] = '\0';
                bool ok = timerReady && state.command(line, millis());
                if (!ok) state.stop();
                applyOutput(); // Apply stop before any potentially blocking serial output.
                if (!std::strcmp(line, "STATUS")) status();
                else reply(ok ? "ok\n" : "error: stopped\n");
            } else {
                reply("error: invalid line; stopped\n");
            }
            used = 0; discard = false;
            break;
        }
        if (discard) continue;
        if (c < 32 || c > 126 || used >= sizeof(line) - 1) {
            state.stop(); applyOutput(); used = 0; discard = true;
        } else line[used++] = c;
    }
    delay(1);
}
