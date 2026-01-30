#define TRIG_PIN 18
#define ECHO_PIN 19



void setup() {
  Serial.begin(115200);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
}

void loop() {
  // Trigger pulse
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);

  // Replace pulseIn()
  unsigned long duration = pulseIn(ECHO_PIN, HIGH, 30000);// 300 ms timeout
   //Serial.println(duration);
  if (duration>1&& duration<30000)
  {
    Serial.print(" signal got"); Serial.println();
    for(int i=0;i<8;i++)
    {
       digitalWrite(TRIG_PIN, LOW);
       delayMicroseconds(2);
       digitalWrite(TRIG_PIN, HIGH);
       delayMicroseconds(10);
       digitalWrite(TRIG_PIN, LOW);
        unsigned long startb = micros();
       unsigned long durationbit = pulseIn(ECHO_PIN, HIGH, 30); 
        unsigned long endb = micros();
       if(durationbit>1 && durationbit<30 ){Serial.print(" got-"); Serial.print(i);}
       delayMicroseconds(30-endb+startb);

    }
    Serial.println();
  }

  
}
