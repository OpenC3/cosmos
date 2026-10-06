#include "Arduino_SensorKit.h"

#define SYNC_PATTERN 0xABCD1234
#define START_BYTE 0x11
#define BUZZER 5
#define Environment Environment_I2C

const uint8_t BMP280_ID = 1;
const uint8_t ACCELEROMETER_ID = 2;
const uint8_t DHT20_ID = 3;
const uint8_t SOUND_ID = 4;
const uint8_t OLED_ID = 5;

// The OLED is 16 characters wide with the chroma48medium8 font
const uint8_t OLED_COLUMNS = 16;
#define LED 6

// Global variables
bool ledState = false;
int sound_sensor = A2;

void setup() {
  Serial.begin(9600);
  Pressure.begin();
  Accelerometer.begin();
  Environment.begin();
  pinMode(LED, OUTPUT);
  pinMode(BUZZER, OUTPUT);
  digitalWrite(LED, LOW);
  Oled.begin();
  Oled.setFlipMode(true); // Sets the rotation of the screen
}

struct __attribute__((packed)) BMP_Payload {
  uint8_t id;
  float temp;
  float pressure;
  float altitude;
};

struct __attribute__((packed)) Acc_Payload {
  uint8_t id;
  float x;
  float y;
  float z;
};

struct __attribute__((packed)) DHT_Payload {
  uint8_t id;
  float temp;
  float humidity;
};

struct __attribute__((packed)) Sound_Payload {
  uint8_t id;
  int soundValue;
};

struct __attribute__((packed)) OLED_Payload {
  uint8_t id;
  int16_t temp;
  int16_t humidity;

};


void sendSoundTelemetry() {
  int soundValue = 0; //create variable to store many different readings
  for (int i = 0; i < 32; i++) //create a for loop to read 
  { soundValue += analogRead(sound_sensor);  } //read the sound sensor
 
  soundValue >>= 5; //bitshift operation 

  Sound_Payload data = { SOUND_ID, soundValue };

  int SOUND_PAYLOAD_LEN = sizeof(uint32_t) + 1 + sizeof(Sound_Payload);
  uint8_t buffer[SOUND_PAYLOAD_LEN];

  // Sets sync data
  uint32_t sync = SYNC_PATTERN;
  memcpy(buffer, &sync, sizeof(sync));

  // Sets the length of data
  uint8_t length = sizeof(Sound_Payload);
  buffer[sizeof(sync)] = length;

  // Sets the data
  memcpy(buffer + sizeof(sync) + 1, &data, sizeof(Sound_Payload));

  // Send the packet
  Serial.write(buffer, SOUND_PAYLOAD_LEN);
}

void sendDHTTelemetry() {
  // Read sensors
  float temp = Environment.readTemperature();
  float humidity = Environment.readHumidity();

  DHT_Payload data = { DHT20_ID, temp, humidity };

  int DHT_PAYLOAD_LEN = sizeof(uint32_t) + 1 + sizeof(DHT_Payload);
  uint8_t buffer[DHT_PAYLOAD_LEN];

  // Sets sync data
  uint32_t sync = SYNC_PATTERN;
  memcpy(buffer, &sync, sizeof(sync));

  // Sets the length of data
  uint8_t length = sizeof(DHT_Payload);
  buffer[sizeof(sync)] = length;

  // Sets the data
  memcpy(buffer + sizeof(sync) + 1, &data, sizeof(DHT_Payload));

  // Send the packet
  Serial.write(buffer, DHT_PAYLOAD_LEN);
} 

void sendAccTelemetry() {
  // Read sensors
  float x = Accelerometer.readX();
  float y = Accelerometer.readY();
  float z = Accelerometer.readZ();

  Acc_Payload data = { ACCELEROMETER_ID, x, y, z };

  int ACC_PAYLOAD_LEN = sizeof(uint32_t) + 1 + sizeof(Acc_Payload);
  uint8_t buffer[ACC_PAYLOAD_LEN];

  // Sets sync data
  uint32_t sync = SYNC_PATTERN;
  memcpy(buffer, &sync, sizeof(sync));

  // Sets the length of data
  uint8_t length = sizeof(Acc_Payload);
  buffer[sizeof(sync)] = length;

  // Sets the data
  memcpy(buffer + sizeof(sync) + 1, &data, sizeof(Acc_Payload));

  // Send the packet
  Serial.write(buffer, ACC_PAYLOAD_LEN);
}

void sendBMPTelemetry() {
  // Read sensors
  float temp     = Pressure.readTemperature();
  float pressure = Pressure.readPressure();
  float altitude = Pressure.readAltitude();

  BMP_Payload data = { BMP280_ID, temp, pressure, altitude };

  // Holds the actual packet data
  int BMP_PAYLOAD_LEN = sizeof(uint32_t) + 1 + sizeof(BMP_Payload);
  uint8_t buffer[BMP_PAYLOAD_LEN];

  // Sets sync data
  uint32_t sync = SYNC_PATTERN;
  memcpy(buffer, &sync, sizeof(sync));

  // Sets the length of data
  uint8_t length = sizeof(BMP_Payload);
  buffer[sizeof(sync)] = length;

  // Sets the data
  memcpy(buffer + sizeof(sync) + 1, &data, sizeof(BMP_Payload));

  // Send the packet
  Serial.write(buffer, BMP_PAYLOAD_LEN);
}

void sendOLEDTelemetry() {
  // Read sensors
  int16_t humidity = Environment.readHumidity();
  int16_t temp = Environment.readTemperature();

  // Draw the each line padded to full width so a shrinking value doesn't
  // leave stale digits behind (65 -> 9 would otherwise read "95")
  char temp_line[OLED_COLUMNS + 1];
  snprintf(temp_line, sizeof(temp_line), "Temp: %d C", temp);
  for (uint8_t i = strlen(temp_line); i < OLED_COLUMNS; i++) temp_line[i] = ' ';
  temp_line[OLED_COLUMNS] = '\0';

  char humidity_line[OLED_COLUMNS + 2];
  snprintf(humidity_line, sizeof(humidity_line), "Humidity: %d%%", humidity);
  for (uint8_t i = strlen(humidity_line); i < OLED_COLUMNS; i++) humidity_line[i] = ' ';
  humidity_line[OLED_COLUMNS] = '\0';


  Oled.setFont(u8x8_font_chroma48medium8_r);
  Oled.setCursor(0, 0);      // Set the Coordinates for the first line
  Oled.print(temp_line);     // Print the temp
  Oled.setCursor(0, 10);     // Set the Coordinates for the second line
  Oled.print(humidity_line); // Print the humidity
  Oled.refreshDisplay();     // Update the Display

  // Send the same label the display shows so the two can't drift apart
  OLED_Payload data = { OLED_ID, temp, humidity };

  int OLED_PAYLOAD_LEN = sizeof(uint32_t) + 1 + sizeof(OLED_Payload);
  uint8_t buffer[OLED_PAYLOAD_LEN];

  // Sets sync data
  uint32_t sync = SYNC_PATTERN;
  memcpy(buffer, &sync, sizeof(sync));

  // Sets the length of data
  uint8_t length = sizeof(OLED_Payload);
  buffer[sizeof(sync)] = length;

  // Sets the data
  memcpy(buffer + sizeof(sync) + 1, &data, sizeof(OLED_Payload));

  // Send the packet
  Serial.write(buffer, OLED_PAYLOAD_LEN);
}

void receiveCommands() {
  while (Serial.available() >= 3) {
    if (Serial.read() == START_BYTE) {
      byte cmdId = Serial.read();
      byte arg = Serial.read();

      switch(cmdId) {
        case 0x01:
          if (arg == 0x00) {
            digitalWrite(LED, LOW);
          } else {
            digitalWrite(LED, HIGH);
          }
          break;
        case 0x02:
          if (arg == 0x00) {
            noTone(BUZZER);
          } else {
            tone(BUZZER, 85);
          }
          break;
        default:
          continue;
      }
    }
  }
}

void loop() {
  receiveCommands();
  sendBMPTelemetry();
  sendAccTelemetry();
  sendDHTTelemetry();
  sendSoundTelemetry();
  sendOLEDTelemetry();
  // Wait one second
  delay(1000);
}
