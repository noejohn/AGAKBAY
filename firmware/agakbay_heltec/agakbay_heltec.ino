#include <Arduino.h>
#include "HT_TinyGPS++.h"
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>
#include "HT_SSD1306Wire.h"

// GNSS wiring confirmed from the board's official GPSToUart example:
// VGNSS_CTRL enables power to the GNSS connector, Serial1 is the UART
// link to the L76K module (RX=33, TX=34).
#define VGNSS_CTRL 3
#define GNSS_RX_PIN 33
#define GNSS_TX_PIN 34

#define DEVICE_NAME "AGAKBAY-Heltec"

// These four UUIDs must match lib/services/heltec_ble_service.dart
// exactly, or the app will never find the matching service/characteristics.
#define SERVICE_UUID "d64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0001"
#define LOCATION_CHAR_UUID "d64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0002"
#define SOS_CHAR_UUID "d64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0003"
#define HIKE_INFO_CHAR_UUID "d64d4a5c-8ad6-4b71-9f1a-3e6c9f2b0004"

static SSD1306Wire display(0x3c, 500000, SDA_OLED, SCL_OLED, GEOMETRY_128_64, RST_OLED);

TinyGPSPlus gps;
BLECharacteristic *locationCharacteristic;
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
    Serial.println("SOS triggered from phone app.");
    // Once the buzzer/LED and LoRa send are wired up, trigger them here.
  }
};

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

  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  BLEDevice::startAdvertising();
}

void setup() {
  Serial.begin(115200);
  delay(500);
  setupDisplay();
  setupGnss();
  setupBle();
  updateDisplay();
  Serial.println("AGAKBAY Heltec ready, advertising as " DEVICE_NAME);
}

void loop() {
  while (Serial1.available() > 0) {
    gps.encode(Serial1.read());
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
}
