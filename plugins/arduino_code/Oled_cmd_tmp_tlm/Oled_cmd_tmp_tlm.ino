#include "Arduino_SensorKit.h"
#define Environment Environment_I2C
#define SYNC_PATTERN 0xABCD1234;

const uint8_t BMP280_ID = 1;

struct __attribute__((packed)) Payload {
  uint8_t id;
  float temp;
  float humidity;
};

void setup() {
  Wire.begin();
  Oled.begin();
  Oled.setFlipMode(true);
  Environment.begin();
  Serial.begin(9600);
}

void receiveCommands() 
{
  while (Serial.available() > 0){
    String command = Serial.readString();
    Oled.clearDisplay();
    
    Oled.setFont(u8x8_font_chroma48medium8_r);
    Oled.setCursor(0, 33);
    Oled.print(command);
    Oled.refreshDisplay(); //must update display after writing to it
  }
}

void tlm()
{
  float temp = Environment.readTemperature();
  float humidity = Environment.readHumidity();
  Payload data = { BMP280_ID, temp, humidity};
  // sync pattern length = sizeof(uint32_t)
  int PAYLOAD_LEN = sizeof(uint32_t) + 1 + sizeof(Payload);
  uint8_t buffer[PAYLOAD_LEN];
  uint32_t sync = SYNC_PATTERN;
  memcpy(buffer, &sync, sizeof(sync));
  uint8_t length = sizeof(Payload);
  // Set the number which will define data length
  buffer[sizeof(sync)] = length;
  memcpy(buffer+sizeof(sync) + 1, &data, sizeof(Payload));
  Serial.write(buffer,PAYLOAD_LEN);
}

void loop() {
  receiveCommands();
  tlm();
  delay(1000);

}
