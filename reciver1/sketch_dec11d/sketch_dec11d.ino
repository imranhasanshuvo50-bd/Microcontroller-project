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
void call(){
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
}

void loop() {
  // 1) Send 10µs pulse on trigger (this is the "signal generation")
  call();
  float time1=0;
  float time2=0;

  // 2) Measure pulse width on echo with timeout (30,000 µs ≈ 5 m range)
  long duration = pulseIn(ECHO_PIN, HIGH, 30000); 
  while(true){
  if (duration>=1)
  {
    
    time1=millis();
    break;
    
  }
  
  }
  
  call();

  // 2) Measure pulse width on echo with timeout (30,000 µs ≈ 5 m range)
  long duration1 = pulseIn(ECHO_PIN, HIGH, 30000); 
  while(true){
  if (duration1>=1)
  {
    time2=millis();
    break;
    
  }
  }
  if((time1-time2)==50)
  {
    Serial.print("device 50 ditected");
  }
  else if((time1-time2)==40)
  {
    Serial.print("device 40 ditected");
  }
 

 // delay(500); // 0.5s between measurements
}