#include <Arduino.h>
#include "LoRaWan_APP.h"
#include <Wire.h>
#include "HT_SSD1306Wire.h"

// ============================================================
// STEP 1 TEST: two boards, LoRa only — no phone, no BLE.
// Flash this SAME file to both Heltec boards, changing only
// DEVICE_ID below before each upload ("A" on board 1, "B" on
// board 2). Each board sends a ping every few seconds and
// listens the rest of the time, so you can watch both boards
// hear each other over Serial and on the OLED.
// ============================================================

// Change this one line per board before flashing.
#define DEVICE_ID "B" // <-- set to "B" on the second board

// Confirm this matches your antenna's rated band before testing.
// 433 MHz is a common choice for LoRa projects in the Philippines.
#define RF_FREQUENCY 433000000 // Hz
#define TX_OUTPUT_POWER 14 // dBm
#define LORA_BANDWIDTH 0 // 0: 125 kHz
#define LORA_SPREADING_FACTOR 7
#define LORA_CODINGRATE 1 // 1: 4/5
#define LORA_PREAMBLE_LENGTH 8
#define LORA_SYMBOL_TIMEOUT 0
#define LORA_FIX_LENGTH_PAYLOAD_ON false
#define LORA_IQ_INVERSION_ON false
#define RX_TIMEOUT_VALUE 1000
#define BUFFER_SIZE 64

static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

char txBuffer[BUFFER_SIZE];
char rxBuffer[BUFFER_SIZE];
static RadioEvents_t RadioEvents;

enum RadioState { STATE_TX, STATE_RX };
RadioState state = STATE_RX;

int sentCount = 0;
int receivedCount = 0;
String lastReceived = "";
int16_t lastRssi = 0;
int8_t lastSnr = 0;
unsigned long lastTxMs = 0;
const unsigned long txIntervalMs = 4000;

void VextOn() {
  pinMode(Vext, OUTPUT);
  digitalWrite(Vext, LOW);
}

void updateDisplay() {
  display.clear();
  display.setTextAlignment(TEXT_ALIGN_LEFT);
  display.setFont(ArialMT_Plain_10);
  display.drawString(0, 0, "LoRa test - unit " DEVICE_ID);
  display.drawString(0, 14, "Sent: " + String(sentCount));
  display.drawString(0, 26, "Received: " + String(receivedCount));
  if (lastReceived.length() > 0) {
    display.drawStringMaxWidth(0, 38, 128, "Last: " + lastReceived);
    display.drawString(0, 52, "RSSI " + String(lastRssi) + " SNR " + String(lastSnr));
  }
  display.display();
}

void OnTxDone(void) {
  Serial.println("TX done");
  sentCount++;
  updateDisplay();
  state = STATE_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void OnTxTimeout(void) {
  Serial.println("TX timeout");
  Radio.Sleep();
  state = STATE_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  Radio.Sleep();
  uint16_t len = size < BUFFER_SIZE - 1 ? size : BUFFER_SIZE - 1;
  memcpy(rxBuffer, payload, len);
  rxBuffer[len] = '\0';
  lastReceived = String(rxBuffer);
  lastRssi = rssi;
  lastSnr = snr;
  receivedCount++;
  Serial.printf("RX: \"%s\"  RSSI=%d  SNR=%d\n", rxBuffer, rssi, snr);
  updateDisplay();
  state = STATE_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void OnRxTimeout(void) {
  state = STATE_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void OnRxError(void) {
  Serial.println("RX error");
  state = STATE_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void setup() {
  Serial.begin(115200);
  delay(500);

  VextOn();
  delay(100);
  display.init();
  display.setFont(ArialMT_Plain_10);
  updateDisplay();

  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.TxDone = OnTxDone;
  RadioEvents.TxTimeout = OnTxTimeout;
  RadioEvents.RxDone = OnRxDone;
  RadioEvents.RxTimeout = OnRxTimeout;
  RadioEvents.RxError = OnRxError;

  Radio.Init(&RadioEvents);
  Radio.SetChannel(RF_FREQUENCY);
  Radio.SetTxConfig(MODEM_LORA, TX_OUTPUT_POWER, 0, LORA_BANDWIDTH,
                     LORA_SPREADING_FACTOR, LORA_CODINGRATE,
                     LORA_PREAMBLE_LENGTH, LORA_FIX_LENGTH_PAYLOAD_ON,
                     true, 0, 0, LORA_IQ_INVERSION_ON, 3000);
  Radio.SetRxConfig(MODEM_LORA, LORA_BANDWIDTH, LORA_SPREADING_FACTOR,
                     LORA_CODINGRATE, 0, LORA_PREAMBLE_LENGTH,
                     LORA_SYMBOL_TIMEOUT, LORA_FIX_LENGTH_PAYLOAD_ON,
                     0, true, 0, 0, LORA_IQ_INVERSION_ON, true);

  Serial.println("LoRa ping-pong test ready - unit " DEVICE_ID);
  state = STATE_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
  lastTxMs = millis();
}

void loop() {
  if (state == STATE_RX && millis() - lastTxMs > txIntervalMs) {
    Radio.Sleep();
    snprintf(txBuffer, BUFFER_SIZE, "AGAKBAY-TEST %s #%d", DEVICE_ID, sentCount + 1);
    Serial.print("Sending: ");
    Serial.println(txBuffer);
    Radio.Send((uint8_t *)txBuffer, strlen(txBuffer));
    state = STATE_TX;
    lastTxMs = millis();
  }
  Radio.IrqProcess();
}
