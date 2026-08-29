#include <Arduino.h>
#include "HT_TinyGPS++.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>
#include "HT_SSD1306Wire.h"
#include "LoRaWan_APP.h"

// GNSS wiring confirmed from the board's official GPSToUart example:
// VGNSS_CTRL enables power to the GNSS connector, Serial1 is the UART
// link to the L76K module (RX=33, TX=34).
#define VGNSS_CTRL 3
#define GNSS_RX_PIN 33
#define GNSS_TX_PIN 34

// Change this one line before flashing each board: "AGAKBAY-Hiker" for a
// hiker's unit, "AGAKBAY-TourGuide" for the tour guide's unit. The app
// scans for the name matching its own user's role, so each phone
// connects to the physically correct device instead of any nearby one.
#define DEVICE_NAME "AGAKBAY-TourGuide"

// These five UUIDs must match lib/services/heltec_ble_service.dart
// exactly, or the app will never find the matching service/characteristics.
#define SERVICE_UUID "d64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0001"
#define LOCATION_CHAR_UUID "d64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0002"
#define SOS_CHAR_UUID "d64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0003"
#define HIKE_INFO_CHAR_UUID "d64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0004"
// New: notifies the phone when this board receives an SOS relayed over
// LoRa from another Heltec, so the guide's app can show it with no
// internet/cellular signal at all.
#define SOS_RELAY_CHAR_UUID "d64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0005"

// Confirmed working over the air in the standalone LoRa ping-pong test
// (firmware/agakbay_heltec_lora_test) — keep this in sync with whatever
// frequency that test actually used on both boards.
#define RF_FREQUENCY 915000000 // Hz
#define TX_OUTPUT_POWER 14 // dBm
#define LORA_BANDWIDTH 0 // 0: 125 kHz
#define LORA_SPREADING_FACTOR 7
#define LORA_CODINGRATE 1 // 1: 4/5
#define LORA_PREAMBLE_LENGTH 8
#define LORA_SYMBOL_TIMEOUT 0
#define LORA_FIX_LENGTH_PAYLOAD_ON false
#define LORA_IQ_INVERSION_ON false
#define RX_TIMEOUT_VALUE 1000
#define LORA_BUFFER_SIZE 96

static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

TinyGPSPlus gps;
BLECharacteristic *locationCharacteristic;
BLECharacteristic *sosRelayCharacteristic;
bool deviceConnected = false;
unsigned long lastNotifyMs = 0;
const unsigned long notifyIntervalMs = 5000;

// Set from the phone once it connects (see HikeInfoCallbacks) — empty
// until then, so the screen just shows placeholder "--" values.
// isGuideDevice picks which of the two layouts updateDisplay() draws:
// a hiker's phone sends "H|guideName|mountainName", a tour guide's phone
// sends "G|mountainName|participantCount".
bool isGuideDevice = false;
String hikeGuideName = "";
String hikeMountainName = "";
String hikeParticipantCount = "";

// --- LoRa relay state ---
// Every board runs the same firmware and can act as either the sender
// (SOS trigger) or the relay (receives a neighbor's SOS and forwards it
// to its own phone over BLE) — the two roles aren't hardcoded per board.
static RadioEvents_t RadioEvents;
enum RadioLinkState { RADIO_RX, RADIO_TX };
RadioLinkState radioState = RADIO_RX;
char loraTxBuffer[LORA_BUFFER_SIZE];
char loraRxBuffer[LORA_BUFFER_SIZE];

// Set by SosCallbacks::onWrite (BLE task) and consumed from loop() (Arduino
// task) rather than calling Radio.Send directly from the BLE callback —
// keeps every radio call on the one task that owns Radio.IrqProcess().
volatile bool sosPending = false;
String pendingSosName = "Hiker";
// The phone's own GPS supplies these — the onboard GNSS module is
// unreliable on the current hardware, so this board just relays the
// phone's coordinates over LoRa instead of measuring its own location.
double pendingSosLat = 0;
double pendingSosLng = 0;
// False only for a malformed/legacy write with no coordinates — the app
// itself refuses to call sendSos() without a real phone GPS fix, so this
// should be true in practice, but the firmware doesn't assume that.
bool pendingSosHasFix = false;

String lastRelayHikerName = "";
bool lastRelayHasFix = false;
double lastRelayLat = 0;
double lastRelayLng = 0;
unsigned long sosBannerUntilMs = 0;
const unsigned long sosBannerDurationMs = 30000;

void VextOn() {
  pinMode(Vext, OUTPUT);
  digitalWrite(Vext, LOW);
}

// Redraws the whole screen from current state. Called on every state change
// (BLE connect/disconnect, hike info received, GPS fix acquired) rather than
// on a timer — the status only needs to change when something actually
// changed, and redrawing constantly would just flicker for no reason.
void updateDisplay() {
  display.clear();
  display.setTextAlignment(TEXT_ALIGN_LEFT);
  display.setFont(ArialMT_Plain_10);

  // A relayed SOS takes over the whole screen for a while — this is the
  // one state a tour guide needs to see even with the phone put away.
  if (sosBannerUntilMs != 0 && millis() < sosBannerUntilMs) {
    display.drawString(0, 0, "!!! SOS RECEIVED !!!");
    display.drawStringMaxWidth(0, 16, 128, "From: " + lastRelayHikerName);
    display.drawString(
        0, 34,
        lastRelayHasFix
            ? String(lastRelayLat, 5) + "," + String(lastRelayLng, 5)
            : "Location: no GPS fix yet");
    display.drawString(0, 50, "via LoRa - no signal");
    display.display();
    return;
  }

  display.drawString(0, 0, deviceConnected ? "BLE: Connected" : "BLE: Advertising...");
  display.drawString(0, 12, gps.location.isValid() ? "GPS: Locked" : "GPS: Waiting...");

  if (isGuideDevice) {
    display.drawStringMaxWidth(
        0, 26, 128,
        "Mountain: " + (hikeMountainName.length() > 0 ? hikeMountainName : "--"));
    display.drawStringMaxWidth(
        0, 44, 128,
        "Hikers: " + (hikeParticipantCount.length() > 0 ? hikeParticipantCount : "--"));
  } else {
    display.drawStringMaxWidth(
        0, 26, 128,
        "Guide: " + (hikeGuideName.length() > 0 ? hikeGuideName : "--"));
    display.drawStringMaxWidth(
        0, 44, 128,
        "Mountain: " + (hikeMountainName.length() > 0 ? hikeMountainName : "--"));
  }

  display.display();
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    deviceConnected = true;
    updateDisplay();
  }

  void onDisconnect(BLEServer *server) override {
    deviceConnected = false;
    hikeGuideName = "";
    hikeMountainName = "";
    hikeParticipantCount = "";
    updateDisplay();
    // A connected central stops advertising automatically, so it has to be
    // restarted here or the phone can never reconnect after a drop.
    server->getAdvertising()->start();
  }
};

class SosCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    // Phone writes "SOS|<hikerName>|<lat>|<lng>" — coordinates come from
    // the PHONE's own GPS now, not this board's (unreliable) onboard
    // GNSS module. Falls back to "Hiker"/0,0 for any malformed/older
    // write so a bad parse never silently drops the SOS trigger itself.
    String value = String(characteristic->getValue().c_str());
    String hikerName = "Hiker";
    double lat = 0;
    double lng = 0;
    bool hasFix = false;
    int p1 = value.indexOf('|');
    if (p1 != -1) {
      int p2 = value.indexOf('|', p1 + 1);
      int p3 = p2 == -1 ? -1 : value.indexOf('|', p2 + 1);
      if (p2 != -1 && p3 != -1) {
        hikerName = value.substring(p1 + 1, p2);
        lat = value.substring(p2 + 1, p3).toDouble();
        lng = value.substring(p3 + 1).toDouble();
        hasFix = true;
      } else if (p1 + 1 < (int)value.length()) {
        hikerName = value.substring(p1 + 1);
      }
    }
    Serial.printf("SOS triggered from phone app: %s at %.6f,%.6f (fix=%s)\n",
                  hikerName.c_str(), lat, lng, hasFix ? "yes" : "NO");
    pendingSosName = hikerName;
    pendingSosLat = lat;
    pendingSosLng = lng;
    pendingSosHasFix = hasFix;
    sosPending = true;
  }
};

// --- LoRa radio callbacks ---
// Half-duplex on a single antenna: the state machine below alternates
// between listening (RADIO_RX, the normal resting state) and a brief
// transmit window only when an SOS is actually pending.

void onLoraTxDone() {
  Serial.println("LoRa: SOS sent.");
  radioState = RADIO_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void onLoraTxTimeout() {
  Serial.println("LoRa: SOS send timed out, will retry on next loop.");
  Radio.Sleep();
  radioState = RADIO_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

// Wire format from a neighbor board: "SOS|<hikerName>|<hasFix 0/1>|<lat>|<lng>".
// hasFix matters: a board with no GPS lock yet (common right after power-on,
// or indoors) would otherwise send 0.0,0.0 — a real spot in the ocean — and
// the guide could mistake that for the hiker's actual position.
void handleReceivedLoraPacket(const String &packet, int16_t rssi) {
  if (!packet.startsWith("SOS|")) return;
  int p1 = packet.indexOf('|', 4);
  int p2 = p1 == -1 ? -1 : packet.indexOf('|', p1 + 1);
  int p3 = p2 == -1 ? -1 : packet.indexOf('|', p2 + 1);
  if (p1 == -1 || p2 == -1 || p3 == -1) return;

  lastRelayHikerName = packet.substring(4, p1);
  String fixStr = packet.substring(p1 + 1, p2);
  String latStr = packet.substring(p2 + 1, p3);
  String lngStr = packet.substring(p3 + 1);
  bool hasFix = fixStr == "1";
  lastRelayHasFix = hasFix;
  lastRelayLat = latStr.toDouble();
  lastRelayLng = lngStr.toDouble();
  sosBannerUntilMs = millis() + sosBannerDurationMs;

  Serial.printf("LoRa: SOS received from %s, fix=%s, at %s,%s (RSSI %d)\n",
                lastRelayHikerName.c_str(), hasFix ? "yes" : "NO", latStr.c_str(),
                lngStr.c_str(), rssi);

  // Forward to this board's own connected phone — "hikerName|hasFix|lat|lng".
  String relayPayload = lastRelayHikerName + "|" + fixStr + "|" + latStr + "|" + lngStr;
  sosRelayCharacteristic->setValue((uint8_t *)relayPayload.c_str(), relayPayload.length());
  sosRelayCharacteristic->notify();

  updateDisplay();
}

void onLoraRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
  Radio.Sleep();
  uint16_t len = size < LORA_BUFFER_SIZE - 1 ? size : LORA_BUFFER_SIZE - 1;
  memcpy(loraRxBuffer, payload, len);
  loraRxBuffer[len] = '\0';
  handleReceivedLoraPacket(String(loraRxBuffer), rssi);
  radioState = RADIO_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void onLoraRxTimeout() {
  radioState = RADIO_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void onLoraRxError() {
  radioState = RADIO_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

// Phone writes "H|guideName|mountainName" (hiker) or "G|mountainName|
// participantCount" (tour guide) once connected, so the device can show
// hike context even if no one is looking at the app.
class HikeInfoCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    String value = characteristic->getValue().c_str();
    int firstSep = value.indexOf('|');
    if (firstSep == -1) {
      return;
    }
    String mode = value.substring(0, firstSep);
    String rest = value.substring(firstSep + 1);
    int secondSep = rest.indexOf('|');
    if (secondSep == -1) {
      return;
    }

    if (mode == "G") {
      isGuideDevice = true;
      hikeMountainName = rest.substring(0, secondSep);
      hikeParticipantCount = rest.substring(secondSep + 1);
    } else {
      isGuideDevice = false;
      hikeGuideName = rest.substring(0, secondSep);
      hikeMountainName = rest.substring(secondSep + 1);
    }
    updateDisplay();
  }
};

void setupGnss() {
  pinMode(VGNSS_CTRL, OUTPUT);
  digitalWrite(VGNSS_CTRL, HIGH);
  // Confirmed against Heltec's own official GPS_test() example: this
  // board's L76K module talks at 115200, not the 9600 some L76K modules
  // default to elsewhere — an earlier guess of 9600 here was wrong.
  Serial1.begin(115200, SERIAL_8N1, GNSS_RX_PIN, GNSS_TX_PIN);
}

void setupDisplay() {
  VextOn();
  delay(100);
  display.init();
  display.setFont(ArialMT_Plain_10);
}

void setupBle() {
  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);

  locationCharacteristic = service->createCharacteristic(
      LOCATION_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  locationCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *sosCharacteristic = service->createCharacteristic(
      SOS_CHAR_UUID, BLECharacteristic::PROPERTY_WRITE);
  sosCharacteristic->setCallbacks(new SosCallbacks());

  BLECharacteristic *hikeInfoCharacteristic = service->createCharacteristic(
      HIKE_INFO_CHAR_UUID, BLECharacteristic::PROPERTY_WRITE);
  hikeInfoCharacteristic->setCallbacks(new HikeInfoCallbacks());

  sosRelayCharacteristic = service->createCharacteristic(
      SOS_RELAY_CHAR_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  sosRelayCharacteristic->addDescriptor(new BLE2902());

  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void setupLora() {
  Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

  RadioEvents.TxDone = onLoraTxDone;
  RadioEvents.TxTimeout = onLoraTxTimeout;
  RadioEvents.RxDone = onLoraRxDone;
  RadioEvents.RxTimeout = onLoraRxTimeout;
  RadioEvents.RxError = onLoraRxError;

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

  radioState = RADIO_RX;
  Radio.Rx(RX_TIMEOUT_VALUE);
}

void setup() {
  Serial.begin(115200);
  delay(500);
  // Temporary checkpoint prints — whichever line prints LAST before the
  // Monitor goes silent tells us exactly which setup step is hanging.
  // Safe to delete once boot completes reliably.
  Serial.println("[boot] Serial ready");
  setupDisplay();
  Serial.println("[boot] Display ready");
  setupGnss();
  Serial.println("[boot] GNSS ready");
  setupBle();
  Serial.println("[boot] BLE ready");
  setupLora();
  Serial.println("[boot] LoRa ready");
  updateDisplay();
  Serial.println("AGAKBAY Heltec ready, advertising as " DEVICE_NAME);
}

void loop() {
  // Temporary debug aid: mirrors raw GPS module output to the Serial
  // Monitor. Readable text starting with "$" (e.g. "$GNRMC,...") means
  // the module is talking and the baud rate is right — TinyGPS++ just
  // hasn't gotten a satellite lock yet, so wait it out under open sky.
  // Garbage/binary-looking characters mean the baud rate or wiring is
  // still wrong. Safe to delete once you've confirmed a fix.
  while (Serial1.available() > 0) {
    char c = Serial1.read();
    Serial.write(c);
    gps.encode(c);
  }

  if (millis() - lastNotifyMs > notifyIntervalMs) {
    if (gps.location.isValid()) {
      if (deviceConnected) {
        char payload[32];
        snprintf(payload, sizeof(payload), "%.6f,%.6f", gps.location.lat(),
                  gps.location.lng());
        locationCharacteristic->setValue((uint8_t *)payload, strlen(payload));
        locationCharacteristic->notify();
        Serial.println(payload);
      }
    }
    updateDisplay();
    lastNotifyMs = millis();
  }

  // Send is deferred to here (rather than done inside SosCallbacks::onWrite)
  // so every Radio.* call happens on this one task, alongside IrqProcess.
  if (sosPending && radioState == RADIO_RX) {
    sosPending = false;
    // Coordinates come from the triggering phone's own GPS (see
    // SosCallbacks::onWrite) — this board's onboard GNSS module is
    // unreliable on the current hardware, so it's not used here at all.
    // hasFix is sent explicitly (0/1) rather than inferred from 0.0,0.0 on
    // the receiving end — a real GPS fix at exactly null island is
    // astronomically unlikely, but "0.0,0.0 means no fix" is still a
    // fragile assumption to bake into the receiver.
    snprintf(loraTxBuffer, LORA_BUFFER_SIZE, "SOS|%s|%d|%.6f|%.6f",
             pendingSosName.c_str(), pendingSosHasFix ? 1 : 0, pendingSosLat,
             pendingSosLng);
    Serial.print("LoRa: sending SOS -> ");
    Serial.println(loraTxBuffer);
    if (!pendingSosHasFix) {
      Serial.println("LoRa: WARNING - no location from phone, sending without one.");
    }
    Radio.Sleep();
    Radio.Send((uint8_t *)loraTxBuffer, strlen(loraTxBuffer));
    radioState = RADIO_TX;
  }

  Radio.IrqProcess();
}
