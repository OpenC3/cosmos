#include "Arduino_SensorKit.h"
#define Environment Environment_I2C
// I defined the Sync pattern for the Length protocol as the following.
// This must the same in plugin.txt but in little endian
#define SYNC_PATTERN 0xABCD1234;
#include <SPI.h>
#include <Ethernet.h>
int count = 0;

// define the mac address of the arduino
byte mac[] = {
    0xAC, 0x00, 0xF9, 0x05, 0x48, 0x7B
};
// Local area network: 192.168.0
// subnet: 255.255.255.0
// Note: class c address
IPAddress ip(169, 254, 240, 36);
IPAddress gateway(192, 168, 0, 1);
IPAddress subnet(255, 255, 255, 0);

// Open port 239
EthernetServer server(239);

// This is the target Identifyer
const uint8_t BMP280_ID = 1;

// This is the packet structure
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
    Ethernet.init(10);
    Serial.begin(9600);
    while (!Serial) {
    ; // wait for serial port to connect. Needed for native USB port only
    }
    Ethernet.begin(mac, ip, gateway, subnet);

    Serial.print("My IP address: ");
    Serial.println(Ethernet.localIP());

    server.begin();
}

void receiveCommands() 
{
  EthernetClient client = server.available();
  if (client){
    char command = client.read();
    if(command == '~')
    {
      Oled.clearDisplay();
      count=0;
    }
    else
    {
      Oled.setFont(u8x8_font_chroma48medium8_r);
      Oled.setCursor(count, 33);
      count++;
      Oled.print(command);
      Oled.refreshDisplay(); //must update display after writing to it
    }
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
  server.write(buffer,PAYLOAD_LEN);
}

void loop() {
  receiveCommands();
  tlm();
}


