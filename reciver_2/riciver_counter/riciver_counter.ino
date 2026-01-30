
#define TRIG_PIN 18
#define ECHO_PIN 19

hw_timer_t *timer = NULL;

void setup() {
  Serial.begin(115200);

  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);

  // ESP32 core 3.x timer (NO interrupt)
  timer = timerBegin(1000000); // 1 MHz → 1 µs tick
  timerStart(timer);
}

void send() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
}

void loop() {
  send();

  unsigned long duration = pulseIn(ECHO_PIN, HIGH, 30000);

  if (duration > 1 && duration < 30000) {
    Serial.println("signal got");
   // delayMicroseconds(30000);

    for (int i = 0; i < 16; i++) {
      delay(100);
      send();

      timerWrite(timer, 0);  // TCNT = 0

      unsigned long durationbit = pulseIn(ECHO_PIN, HIGH, 30000);

      if (durationbit > 1 && durationbit < 30000) {
        Serial.print("got-");
        Serial.println(i);
      }

      // wait until 30,000 µs elapsed
      while (timerRead(timer) < 30000) {
        // busy wait
      }
    }

    Serial.println();
  }
}