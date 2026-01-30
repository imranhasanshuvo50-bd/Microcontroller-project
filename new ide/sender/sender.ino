#include <WiFi.h>
#include <esp_now.h>

#define BOOT_BTN 0   // BOOT button
#define LED_PIN 2    // Optional master LED
//C0:49:EF:DE:99:0C
uint8_t slaveMAC[] = {0xC0, 0x49, 0xEF, 0xDE, 0x99, 0x0C};

typedef struct {
  bool blink;
} Message;

Message msg;

void onReceive(const esp_now_recv_info *info, const uint8_t *data, int len) {
  memcpy(&msg, data, sizeof(msg));
  if (msg.blink) {
    digitalWrite(LED_PIN, !digitalRead(LED_PIN));
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(BOOT_BTN, INPUT_PULLUP);
  pinMode(LED_PIN, OUTPUT);

  WiFi.mode(WIFI_STA);
  Serial.println(WiFi.macAddress());

  if (esp_now_init() != ESP_OK) {
    Serial.println("ESP-NOW init failed");
    return;
  }

  esp_now_register_recv_cb(onReceive);

  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, slaveMAC, 6);
  peer.channel = 0;
  peer.encrypt = false;

  esp_now_add_peer(&peer);
}

void loop() {
  static bool lastState = HIGH;
  bool state = digitalRead(BOOT_BTN);

  if (lastState == HIGH && state == LOW) {
    msg.blink = true;
    esp_now_send(slaveMAC, (uint8_t*)&msg, sizeof(msg));
    delay(300);
  }

  lastState = state;
}
