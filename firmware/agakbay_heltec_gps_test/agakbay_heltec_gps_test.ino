#include "Arduino.h"
#include "HT_TinyGPS++.h"

// Isolated GPS-only test — no BLE, no LoRa, no OLED. If this doesn't show
// real NMEA data either, the problem is hardware (module/cable/power),
// not our combined agakbay_heltec.ino sketch. Matches Heltec's own
// official GPS_test() example almost exactly.

TinyGPSPlus GPS;

#define VGNSS_CTRL 3

void GPS_test(void) {
  pinMode(VGNSS_CTRL, OUTPUT);
  digitalWrite(VGNSS_CTRL, HIGH);
  Serial1.begin(115200, SERIAL_8N1, 33, 34);
  Serial.println("GPS_test starting");

  delay(100);

  unsigned long lastRawPrintMs = 0;

  while (1) {
    if (Serial1.available() > 0) {
      char c = Serial1.read();
      Serial.write(c); // raw passthrough so we see everything, not just parsed fixes
      GPS.encode(c);
    }

    if (millis() - lastRawPrintMs > 5000) {
      lastRawPrintMs = millis();
      Serial.println();
      Serial.print("[status] chars processed: ");
      Serial.print(GPS.charsProcessed());
      Serial.print(" | sentences with fix: ");
      Serial.print(GPS.sentencesWithFix());
      Serial.print(" | location valid: ");
      Serial.println(GPS.location.isValid() ? "YES" : "no");
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("GPS_test sketch ready");
  GPS_test();
}

void loop() {
  // GPS_test() never returns — everything happens in its own while(1).
}
