// ESP32 Ultrasonic Sensor (HC-SR04)
// Trigger -> GPIO 18
// Echo    -> GPIO 19

const int TRIG_PIN = 18;
const int ECHO_PIN = 19;

void setup() {
  Serial.begin(115200);

  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);

  // Make sure trigger is LOW at start
  digitalWrite(TRIG_PIN, LOW);
}

void enable()
{
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

}

void loop() {
  // Send 10µs pulse on trigger
 enable();

  while(true)
  {
      Serial.print(digitalRead(ECHO_PIN));
  }

  //delay(500); // 0.5s between measurements
}
