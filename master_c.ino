

#include <WiFi.h>
#include <esp_now.h>
#include "BluetoothSerial.h"
#include <math.h>

#define BOOT_BTN 0
#define LED_PIN  13

// Sensor-1
#define trigPin  18
#define echoPin  19

// Sensor-2
#define trigPin1 32
#define echoPin1 33

// Sound speed (cm/us)
#define SOUND_SPEED 0.034
#define CM_TO_INCH  0.393700787

// Similarity threshold (cm)
#define THRESHOLD_CM 2.0f

long duration;
long duration1;
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

  if (status == ESP_NOW_SEND_SUCCESS) {
    digitalWrite(LED_PIN, LOW);
  } else {
    digitalWrite(LED_PIN, HIGH);
  }
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
// Finds largest cluster where consecutive sorted differences <= thresholdCm
// Returns mean of that cluster, and outputs keptCount.
float meanOfDominantCluster(const float *arr, int N, float thresholdCm, int *keptCount = nullptr) {
  if (N <= 0) {
    if (keptCount) *keptCount = 0;
    return 0.0f;
  }

  float sorted[N];
  memcpy(sorted, arr, sizeof(float) * N);

  // Simple sort (N small)
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

  // Final segment check
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

// -------- Read TWO ultrasonic sensors at the "same time" --------
// Triggers both sensors nearly simultaneously, then measures both echo pulses in one loop.
// Keeps your existing RTT correction idea.
void readTwoDistancesCm(int tPinA, int ePinA,
                        int tPinB, int ePinB,
                        float &cmA, float &cmB) {
  // Trigger both
  digitalWrite(tPinA, LOW);
  digitalWrite(tPinB, LOW);
  delayMicroseconds(2);

  digitalWrite(tPinA, HIGH);
  digitalWrite(tPinB, HIGH);
  delayMicroseconds(10);

  digitalWrite(tPinA, LOW);
  digitalWrite(tPinB, LOW);

  // Measure both echoes (timeout 30ms)
  const uint32_t timeoutUs = 30000;
  uint32_t startUs = micros();

  bool aStarted = false, bStarted = false;
  bool aDone = false, bDone = false;

  uint32_t aRise = 0, bRise = 0;
  uint32_t aFall = 0, bFall = 0;

  while ((micros() - startUs) < timeoutUs && !(aDone && bDone)) {
    uint32_t now = micros();

    // A
    int aState = digitalRead(ePinA);
    if (!aStarted) {
      if (aState == HIGH) { aStarted = true; aRise = now; }
    } else if (!aDone) {
      if (aState == LOW) { aDone = true; aFall = now; }
    }

    // B
    int bState = digitalRead(ePinB);
    if (!bStarted) {
      if (bState == HIGH) { bStarted = true; bRise = now; }
    } else if (!bDone) {
      if (bState == LOW) { bDone = true; bFall = now; }
    }
  }

  long durA = (aStarted && aDone) ? (long)(aFall - aRise) : 0;
  long durB = (bStarted && bDone) ? (long)(bFall - bRise) : 0;

  float correctedA = (float)durA - (rtt / 2.0f);
  float correctedB = (float)durB - (rtt / 2.0f);
  if (correctedA < 0) correctedA = 0;
  if (correctedB < 0) correctedB = 0;

  cmA = correctedA * SOUND_SPEED;
  cmB = correctedB * SOUND_SPEED;
}

void setup() {
  Serial.begin(115200);

  pinMode(BOOT_BTN, INPUT_PULLUP);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  pinMode(trigPin, OUTPUT);
  pinMode(echoPin, INPUT);

  pinMode(trigPin1, OUTPUT);
  pinMode(echoPin1, INPUT);

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
  const int N = 20;
  float distancesCm[N];
  float distancesCm1[N];

  for (int i = 0; i < N; i++) {
    lastSentId++;
    gotAck = false;

    tx.id = lastSentId;
    tx.blink = true;
    tx.ack = false;

    statusLog("Sending BLINK id=" + String(tx.id));

    sendMicros = micros();
    esp_now_send(slaveMAC, (uint8_t*)&tx, sizeof(tx));

    // Read both sensors at (near) the same time
    readTwoDistancesCm(trigPin, echoPin, trigPin1, echoPin1, distancesCm1[i], distancesCm[i]);

    delay(50);
  }

  // ---------- Dominant cluster filter + mean (Sensor-1) ----------
  int kept = 0;
  float meanCm = meanOfDominantCluster(distancesCm, N, THRESHOLD_CM, &kept);
  float meanInch = meanCm * CM_TO_INCH;

  // ---------- Dominant cluster filter + mean (Sensor-2) ----------
  int kept1 = 0;
  float meanCm1 = meanOfDominantCluster(distancesCm1, N, THRESHOLD_CM, &kept1);
  float meanInch1 = meanCm1 * CM_TO_INCH;

  // ---------- OUTPUT ----------
  // USB: readable
  Serial.println("S1 Kept " + String(kept) + "/" + String(N) +
                 " | Mean (inch): " + String(meanInch, 2));
  Serial.println("S2 Kept " + String(kept1) + "/" + String(N) +
                 " | Mean (inch): " + String(meanInch1, 2));

  if (SerialBT.hasClient()) {
    SerialBT.println(
      String(meanInch, 2) + "," + String(meanInch1, 2)
    );
  }

  delay(100);
}
