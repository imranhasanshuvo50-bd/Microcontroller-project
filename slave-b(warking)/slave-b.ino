#include <WiFi.h>
#include <esp_now.h>

#define LED_PIN 2
#define SOUND_SPEED 0.034
#define CM_TO_INCH 0.393701

const int trigPin = 18;


// Master MAC (set this to MASTER MAC printed in Serial)
 //14:2B:2F:D9:19:B8
uint8_t masterMAC[] = {0x14, 0x2B, 0x2F, 0xD9, 0x19, 0xB8}; // CHANGE if needed

typedef struct __attribute__((packed)) {
  uint32_t id;
  bool blink;
  bool ack;
} Message;

// NEW send callback signature (IDF v5+)
void onSent(const wifi_tx_info_t *tx_info, esp_now_send_status_t status) {
  Serial.print("ACK send status: ");
  Serial.println(status == ESP_NOW_SEND_SUCCESS ? "SUCCESS" : "FAIL");
}

void onReceive(const esp_now_recv_info *info, const uint8_t *data, int len) {
  if (len < (int)sizeof(Message)) return;

  Message rx;
  memcpy(&rx, data, sizeof(rx));

  // Only act on command packets
  if (rx.blink && !rx.ack) {
    Serial.print("Received BLINK id=");
    Serial.println(rx.id);

    // Action: toggle LED
    digitalWrite(LED_PIN, !digitalRead(LED_PIN));

    digitalWrite(trigPin, LOW);
  delayMicroseconds(2);
  // Sets the trigPin on HIGH state for 10 micro seconds
  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);
  
  // Reads the echoPin, returns the sound wave travel time in microseconds
 


    // Reply ACK
    Message ackMsg;
    ackMsg.id = rx.id;
    ackMsg.blink = false;
    ackMsg.ack = true;

    // Reply to master (either info->src_addr OR masterMAC; both work if peer exists)
    esp_now_send(info->src_addr, (uint8_t*)&ackMsg, sizeof(ackMsg));
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  pinMode(trigPin, OUTPUT); // Sets the trigPin as an Output
  
  WiFi.mode(WIFI_STA);
  Serial.print("SLAVE MAC: ");
  Serial.println(WiFi.macAddress());

  if (esp_now_init() != ESP_OK) {
    Serial.println("ESP-NOW init failed");
    return;
  }

  esp_now_register_send_cb(onSent);
  esp_now_register_recv_cb(onReceive);

  // Add master as peer (recommended)
  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, masterMAC, 6);
  peer.channel = 0;
  peer.encrypt = false;

  if (esp_now_add_peer(&peer) != ESP_OK) {
    Serial.println("Failed to add master peer");
  } else {
    Serial.println("Master peer added");
  }
}

void loop() {
  // callbacks handle everything
}
