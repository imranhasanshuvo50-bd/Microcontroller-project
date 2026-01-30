/*******************************************************
 * ESP-NOW MASTER + Bluetooth Serial (SPP)
 *
 * USB Serial  : Full status/debug logs
 * Bluetooth   : ONLY mean distance (inch)
 *
 * Filtering   : Dominant cluster filter
 *              - Take N samples
 *              - Sort them
 *              - Keep the largest "similar" group where
 *                consecutive difference <= THRESHOLD_CM
 *              - mean = sum / kept_count
 *
 * Mobile App  : Serial Bluetooth Terminal
 * Device name : ESP32-MASTER
 *******************************************************/

#include <WiFi.h>
#include <esp_now.h>
#include "BluetoothSerial.h"
#include <math.h>

#define BOOT_BTN 0
#define LED_PIN  13

#define trigPin  18
#define echoPin  19

// Sound speed (cm/us)
#define SOUND_SPEED 0.034
#define CM_TO_INCH  0.393700787

// ---- Your similarity threshold (in cm) ----
// Values are considered "almost similar" if the gap between
// consecutive sorted values is <= this threshold.
#define THRESHOLD_CM 2.0f

long duration;
unsigned long rtt = 0;

// Slave MAC
uint8_t slaveMAC[] = {0xC0, 0x49, 0xEF, 0xDE, 0x99, 0x0C};

typedef struct __attribute__((packed)) {
  uint32_t id;
  bool blink;
  bool ack;
} Message;

BluetoothSerial SerialBT;
Message tx;

volatile bool gotAck = false;
uint32_t lastSentId = 0;
unsigned long sendMicros = 0;

// ---------- USB STATUS ONLY ----------
void statusLog(const String &s) {
  Serial.println(s);
}

// ESP-NOW send callback
void onSent(const wifi_tx_info_t *tx_info, esp_now_send_status_t status) {
  statusLog(String("ESP-NOW send: ") +
            (status == ESP_NOW_SEND_SUCCESS ? "SUCCESS" : "FAIL"));
}

// ESP-NOW receive callback
void onReceive(const esp_now_recv_info *info, const uint8_t *data, int len) {
  if (len < (int)sizeof(Message)) return;

  Message rx;
  memcpy(&rx, data, sizeof(rx));

  if (rx.ack && rx.id == lastSentId) {
    gotAck = true;
    rtt = micros() - sendMicros;
    statusLog("ACK id=" + String(rx.id) + " RTT(us)=" + String(rtt));
  }
}

// -------- Dominant cluster mean --------
// Takes an array (cm), finds largest cluster where consecutive
// differences in sorted order <= thresholdCm, returns mean of that cluster.
// Also outputs how many points were kept via keptCount (optional).
float meanOfDominantCluster(const float *arr, int N, float thresholdCm, int *keptCount = nullptr) {
  if (N <= 0) {
    if (keptCount) *keptCount = 0;
    return 0.0f;
  }

  float sorted[N];
  memcpy(sorted, arr, sizeof(float) * N);

  // Simple sort (N is small)
  for (int i = 0; i < N - 1; i++) {
    for (int j = i + 1; j < N; j++) {
      if (sorted[i] > sorted[j]) {
        float t = sorted[i];
        sorted[i] = sorted[j];
        sorted[j] = t;
      }
    }
  }

  int bestStart = 0, bestLen = 1;
  int currStart = 0, currLen = 1;

  for (int i = 1; i < N; i++) {
    if (fabs(sorted[i] - sorted[i - 1]) <= thresholdCm) {
      currLen++;
    } else {
      if (currLen > bestLen) {
        bestLen = currLen;
        bestStart = currStart;
      }
      currStart = i;
      currLen = 1;
    }
  }

  // final segment check
  if (currLen > bestLen) {
    bestLen = currLen;
    bestStart = currStart;
  }

  float sum = 0.0f;
  for (int i = 0; i < bestLen; i++) {
    sum += sorted[bestStart + i];
  }

  if (keptCount) *keptCount = bestLen;
  return sum / (float)bestLen;
}

void setup() {
  Serial.begin(115200);

  pinMode(BOOT_BTN, INPUT_PULLUP);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  pinMode(trigPin, OUTPUT);
  pinMode(echoPin, INPUT);

  // Bluetooth
  SerialBT.begin("ESP32-MASTER");
  Serial.println("Bluetooth ready: ESP32-MASTER");

  WiFi.mode(WIFI_STA);
  statusLog("MASTER MAC: " + WiFi.macAddress());

  if (esp_now_init() != ESP_OK) {
    statusLog("ESP-NOW init failed");
    return;
  }

  esp_now_register_send_cb(onSent);
  esp_now_register_recv_cb(onReceive);

  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, slaveMAC, 6);
  peer.channel = 0;
  peer.encrypt = false;

  if (esp_now_add_peer(&peer) != ESP_OK) {
    statusLog("Failed to add peer");
    return;
  }

  statusLog("System ready");
}

void loop() {
  const int N = 40;
  float distancesCm[N];

  for (int i = 0; i < N; i++) {
    lastSentId++;
    gotAck = false;

    tx.id = lastSentId;
    tx.blink = true;
    tx.ack = false;

    statusLog("Sending BLINK id=" + String(tx.id));

    sendMicros = micros();
    esp_now_send(slaveMAC, (uint8_t*)&tx, sizeof(tx));

    // Ultrasonic trigger
    digitalWrite(trigPin, LOW);
    delayMicroseconds(2);
    digitalWrite(trigPin, HIGH);
    delayMicroseconds(10);
    digitalWrite(trigPin, LOW);

    duration = pulseIn(echoPin, HIGH, 30000);

    // RTT correction (optional)
    float corrected = (float)duration - (rtt / 2.0f);
    if (corrected < 0) corrected = 0;

    distancesCm[i] = corrected * SOUND_SPEED;

    delay(50);
  }

  // ---------- Dominant cluster filter + mean ----------
  int kept = 0;
  float meanCm = meanOfDominantCluster(distancesCm, N, THRESHOLD_CM, &kept);
  float meanInch = meanCm * CM_TO_INCH;

  // ---------- OUTPUT ----------
  // USB: readable + kept count
  Serial.println("Kept " + String(kept) + "/" + String(N) +
                 " | Mean Distance (inch): " + String(meanInch, 2));

  // Bluetooth: ONLY numeric value
  if (SerialBT.hasClient()) {
    SerialBT.println(String(meanInch, 2));
  }

  delay(500);
}
