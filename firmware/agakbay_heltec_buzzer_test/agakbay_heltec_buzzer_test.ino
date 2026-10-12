#include <Arduino.h>

// Standalone buzzer test for the AGAKBAY Heltec firmware.
// No BLE, LoRa, phone, or second board is needed. The SOS and STOP buzzer
// patterns run automatically after boot; Serial commands can replay them.
#define BUZZER_PIN 47

void buzzSOS() {
  Serial.println("Dummy SOS: buzzer on for 10 seconds");
  digitalWrite(BUZZER_PIN, HIGH);
  delay(10000);
  digitalWrite(BUZZER_PIN, LOW);
  Serial.println("Dummy SOS complete");
}

void buzzStop() {
  Serial.println("Dummy STOP: two short beeps");
  for (int i = 0; i < 2; i++) {
    digitalWrite(BUZZER_PIN, HIGH);
    delay(200);
    digitalWrite(BUZZER_PIN, LOW);
    delay(150);
  }
  Serial.println("Dummy STOP complete");
}

void setup() {
  Serial.begin(115200);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);
  delay(500);

  Serial.println();
  Serial.println("AGAKBAY buzzer test ready");
  Serial.println("Running dummy STOP pattern...");
  buzzStop();
  delay(1000);
  Serial.println("Running dummy SOS pattern...");
  buzzSOS();
  Serial.println("Startup buzzer test finished");
  Serial.println("Send SOS or STOP to replay either pattern");
}

void loop() {
  if (!Serial.available()) return;

  String command = Serial.readStringUntil('\n');
  command.trim();
  command.toUpperCase();

  if (command == "SOS") {
    buzzSOS();
  } else if (command == "STOP") {
    buzzStop();
  } else if (command.length() > 0) {
    Serial.println("Unknown command. Send SOS or STOP.");
  }
}
