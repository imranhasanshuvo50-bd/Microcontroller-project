
#define TRIG_PIN 18
#define ECHO_PIN 19



void setup() {
  Serial.begin(115200);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
}

void send()
{
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
}

void loop() {
  // Trigger pulse
  send();

  // Replace pulseIn()
  unsigned long duration = pulseIn(ECHO_PIN, HIGH, 30000);// 300 ms timeout
   //Serial.println(duration);
  if (duration>1&& duration<30000)
  {
    Serial.print(" signal got"); Serial.println();
    for(int i=0;i<8;i++)
    {
       send();
        unsigned long startb = micros();
       unsigned long durationbit = pulseIn(ECHO_PIN, HIGH, 30000); 
        unsigned long endb = micros();
       if(durationbit>1 && durationbit<30000 ){Serial.print(" got-"); Serial.print(i);}
       delayMicroseconds(30012-endb+startb);

    }
    Serial.println();
  }

  
}
