#include "Arduino_SensorKit.h"
#define Environment Environment_I2C

const uint8_t BMP280_ID = 1;

void setup() {
  Wire.begin();
  Environment.begin();
  Serial.begin(9600);
}

void loop() {
  float temp = Environment.readTemperature();
  float humidity = Environment.readHumidity();

  const uint16_t PAYLOAD_LEN = 9;
  uint8_t pkt[PAYLOAD_LEN];
  int idx = 0;
  pkt[idx++] = BMP280_ID & 0xFF;
  uint8_t *tempBytes = (uint8_t *)&temp;
  uint8_t *humidityBytes = (uint8_t *)&humidity;

  for (int j = 0; j < 4; j++) pkt[idx++] = tempBytes[j];

  for (int j = 0; j < 4; j++) pkt[idx++] = humidityBytes[j];

  Serial.write(pkt,PAYLOAD_LEN);
  delay(1000);

}
