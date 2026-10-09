# OpenC3 COSMOS Arduino Sensor Kit Plugin
COSMOS Plugin to speak to the Arduino Sensor Kit

## YouTube Videos
1. [Part 1 -- COSMOS and Arduino Sensor Kit | BMP280 | Barometric Sensor Telemetry](https://youtu.be/MtU_bPRawqk?si=cSTK1atBBmwrGer5)
1. [Part 2 -- COSMOS and Arduino Sensor Kit | Commanding & Telemetry](https://youtu.be/T9G5QWnUJPA)
1. [Part 3 -- OpenC3 COSMOS & Arduino Sensor Kit | Real-Time Telemetry & Control](https://youtu.be/gQKgtq5SCYs)

## Installing into OpenC3 COSMOS

1. Go to the OpenC3 Admin Tool, Plugins Tab
1. Click the install button and choose your plugin.gem file
1. Fill out plugin parameters
1. Click Install

## Running the Arduino Sensor Kit Plugin

1. Use the Arduino IDE to Upload the `arduino_code.ino` file onto your Arduino (for this demo, it has been tested on the Arduino Uno)
1. While the Arduino is plugged into your machine, find the port that it is plugged into (your Arduino IDE will likely display this)
1. Launch COSMOS to your machine (see: [Getting Started](https://docs.openc3.com/docs/getting-started/installation) for more details)
1. Form a bridge from your serial connection to your Docker container
1. `openc3cli bridgegem openc3-cosmos-bridge-serial router_port=2950 write_port_name=PUT_YOUR_PORT_FROM_STEP2_HERE read_port_name=PUT_YOUR_PORT_FROM_STEP2_HERE baud_rate=9600 parity=NONE`
1. Install the plugin in COSMOS through the Admin Console

## Contributing

We encourage you to contribute to OpenC3!

Contributing is easy.

1. Fork the project
2. Create a feature branch
3. Make your changes
4. Submit a pull request

Before any contributions can be incorporated we do require all contributors to agree to a Contributor License Agreement

This protects both you and us and you retain full rights to any code you write.

## License

This OpenC3 plugin is released under the MIT License. See [LICENSE.txt](LICENSE.txt)