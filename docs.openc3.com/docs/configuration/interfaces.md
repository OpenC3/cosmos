---
sidebar_position: 6
title: Interfaces
description: Built-in COSMOS interfaces including how to create one
sidebar_custom_props:
  myEmoji: 💡
---

## Overview

Interfaces are the connection to the external embedded systems called [targets](target). Interfaces are defined by the top level [INTERFACE](plugins.md#interface-1) keyword in the plugin.txt file.

Interface classes provide the code that COSMOS uses to receive real-time telemetry from targets and to send commands to targets. The interface that a target uses could be anything (TCP/IP, serial, MQTT, SNMP, etc.), therefore it is important that this is a customizable portion of any reusable Command and Telemetry System. Fortunately the most common form of interfaces are over TCP/IP sockets, and COSMOS provides interface solutions for these. This guide will discuss how to use these interface classes, and how to create your own. Note that in most cases you can extend interfaces with [Protocols](protocols.md) rather than implementing a new interface.

:::info Interface and Routers Are Very Similar
Note that Interfaces and Routers are very similar and share the same configuration parameters. Routers are simply Interfaces which route an existing Interface's telemetry data out to the connected target and routes the connected target's commands back to the original Interface's target.
:::

### Protocols

Protocols define the behaviour of an Interface, including differentiating packet boundaries and modifying data as necessary. See [Protocols](protocols) for more information.

### Accessors

Accessors are responsible for reading and writing the buffer which is transmitted by the interface to the target. See [Accessors](accessors) for more information.

For more information about how Interfaces fit with Protocols and Accessors see [Interoperability Without Standards](https://www.openc3.com/news/interoperability-without-standards).

## Provided Interfaces

COSMOS provides the following interfaces: TCPIP Client, TCPIP Server, UDP, HTTP Client, HTTP Server, MQTT and Serial. The interface to use is defined by the [INTERFACE](plugins.md#interface) and [ROUTER](plugins.md#router) keywords. See [Interface Modifiers](plugins.md#interface-modifiers) for a description of the keywords which can follow the INTERFACE keyword.

COSMOS Enterprise provides the following interfaces: SNMP, SNMP Trap, GEMS, InfluxDB.

### TCPIP Client Interface

The TCPIP client interface connects to a TCPIP socket to send commands and receive telemetry. This interface is used for targets which open a socket and wait for a connection. This is the most common type of interface.

| Parameter          | Description                                                                                                    | Required |
| ------------------ | -------------------------------------------------------------------------------------------------------------- | -------- |
| Host               | Machine name to connect to                                                                                     | Yes      |
| Write Port         | Port to write commands to (can be the same as read port). Pass nil / None to make the interface read only.     | Yes      |
| Read Port          | Port to read telemetry from (can be the same as write port). Pass nil / None to make the interface write only. | Yes      |
| Write Timeout      | Number of seconds to wait before aborting the write                                                            | Yes      |
| Read Timeout       | Number of seconds to wait before aborting the read. Pass nil / None to block on read.                          | Yes      |
| Protocol Type      | See Protocols.                                                                                                 | No       |
| Protocol Arguments | See Protocols for the arguments each stream protocol takes.                                                    | No       |

plugin.txt Ruby Examples:

```ruby
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 nil BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 nil FIXED 6 0 nil true
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 nil PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME tcpip_client_interface.rb host.docker.internal 8080 8080 10.0 10.0 # no built-in protocol
```

plugin.txt Python Examples:

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 None LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 None BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 None FIXED 6 0 None true
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 None PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8080 10.0 10.0 # no built-in protocol
```

### TCPIP Server Interface

The TCPIP server interface creates a TCPIP server which listens for incoming connections and dynamically creates sockets which communicate with the target. This interface is used for targets which open a socket and try to connect to a server.

| Parameter          | Description                                                                           | Required |
| ------------------ | ------------------------------------------------------------------------------------- | -------- |
| Write Port         | Port to write commands to (can be the same as read port)                              | Yes      |
| Read Port          | Port to read telemetry from (can be the same as write port)                           | Yes      |
| Write Timeout      | Number of seconds to wait before aborting the write                                   | Yes      |
| Read Timeout       | Number of seconds to wait before aborting the read. Pass nil / None to block on read. | Yes      |
| Protocol Type      | See Protocols.                                                                        | No       |
| Protocol Arguments | See Protocols for the arguments each stream protocol takes.                           | No       |

#### Interface Options

Options are added directly beneath the interface definition as shown in the example.

| Option         | Description                         | Default |
| -------------- | ----------------------------------- | ------- |
| LISTEN_ADDRESS | IP address to accept connections on | 0.0.0.0 |

plugin.txt Ruby Examples:

```ruby
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8081 10.0 nil LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 nil BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 nil FIXED 6 0 nil true
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME tcpip_client_interface.rb 8080 8080 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME tcpip_server_interface.rb 8080 8080 10.0 nil PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME tcpip_client_interface.rb 8080 8080 10.0 10.0 # no built-in protocol
  OPTION LISTEN_ADDRESS 127.0.0.1
```

plugin.txt Python Examples:

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8081 10.0 None LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 None BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 None FIXED 6 0 None true
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py 8080 8080 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_server_interface.py 8080 8080 10.0 None PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME openc3/interfaces/tcpip_client_interface.py 8080 8080 10.0 10.0 # no built-in protocol
```

### UDP Interface

The UDP interface uses UDP packets to send and receive telemetry from the target.

| Parameter         | Description                                                                                                        | Required | Default                                       |
| ----------------- | ------------------------------------------------------------------------------------------------------------------ | -------- | --------------------------------------------- |
| Host              | Host name or IP address of the machine to send and receive data with                                               | Yes      |
| Write Dest Port   | Port on the remote machine to send commands to                                                                     | Yes      |
| Read Port         | Port on the remote machine to read telemetry from                                                                  | Yes      |
| Write Source Port | Port on the local machine to send commands from                                                                    | No       | nil (socket is not bound to an outgoing port) |
| Interface Address | If the remote machine supports multicast the interface address is used to configure the outgoing multicast address | No       | nil (not used)                                |
| TTL               | Time to Live. The number of intermediate routers allowed before dropping the packet.                               | No       | 128 (Windows)                                 |
| Write Timeout     | Number of seconds to wait before aborting the write                                                                | No       | 10.0                                          |
| Read Timeout      | Number of seconds to wait before aborting the read                                                                 | No       | nil (block on read)                           |

plugin.txt Ruby Example:

```ruby
INTERFACE INTERFACE_NAME udp_interface.rb host.docker.internal 8080 8081 8082 nil 128 10.0 nil
```

plugin.txt Python Example:

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/udp_interface.py host.docker.internal 8080 8081 8082 None 128 10.0 None
```

### HTTP Client Interface

The HTTP client interface connects to a HTTP server to send commands and receive telemetry. This interface is commonly used with the [HttpAccessor](accessors#http-accessor) and [JsonAccessor](accessors#json-accessor). See the [openc3-cosmos-http-example](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-http-example) for more information.

| Parameter                   | Description                                                                             | Required | Default    |
| --------------------------- | --------------------------------------------------------------------------------------- | -------- | ---------- |
| Host                        | Machine name to connect to                                                              | Yes      |            |
| Port                        | Port to write commands to and read telemetry from                                       | No       | 80         |
| Protocol                    | HTTP or HTTPS protocol                                                                  | No       | HTTP       |
| Write Timeout               | Number of seconds to wait before aborting the write. Pass nil / None to block on write. | No       | 5          |
| Read Timeout                | Number of seconds to wait before aborting the read. Pass nil / None to block on read.   | No       | nil / None |
| Connect Timeout             | Number of seconds to wait before aborting the connection                                | No       | 5          |
| Include Request In Response | Whether to include the request in the extra data                                        | No       | false      |

plugin.txt Ruby Examples:

```ruby
INTERFACE INTERFACE_NAME http_client_interface.rb myserver.com 80
```

plugin.txt Python Examples:

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/http_client_interface.py mysecure.com 443 HTTPS
```

### HTTP Server Interface

The HTTP server interface creates a simple unencrypted, unauthenticated HTTP server. This interface is commonly used with the [HttpAccessor](accessors#http-accessor) and [JsonAccessor](accessors#json-accessor). See the [openc3-cosmos-http-example](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-http-example) for more information.

| Parameter | Description                                       | Required | Default |
| --------- | ------------------------------------------------- | -------- | ------- |
| Port      | Port to write commands to and read telemetry from | No       | 80      |

#### Interface Options

Options are added directly beneath the interface definition as shown in the example.

| Option         | Description                         | Default |
| -------------- | ----------------------------------- | ------- |
| LISTEN_ADDRESS | IP address to accept connections on | 0.0.0.0 |

plugin.txt Ruby Examples:

```ruby
INTERFACE INTERFACE_NAME http_server_interface.rb
  LISTEN_ADDRESS 127.0.0.1
```

plugin.txt Python Examples:

```ruby
INTERFACE INTERFACE_NAME openc3/interfaces/http_server_interface.py 88
```

### MQTT Interface

The MQTT interface is typically used for connecting to Internet of Things (IoT) devices. The COSMOS MQTT interface is a client that can both publish and receive messages (commands and telemetry). It has built in support for SSL certificates as well as authentication. It differs from the MQTT Streaming Interface in that the commands and telemetry are transmitted over topics given by `META TOPIC` in the command and telemetry definitions.

| Parameter | Description                                                                          | Required | Default |
| --------- | ------------------------------------------------------------------------------------ | -------- | ------- |
| Host      | Host name or IP address of the MQTT broker                                           | Yes      |         |
| Port      | Port on the MQTT broker to connect to. Keep in mind whether you're using SSL or not. | No       | 1883    |
| SSL       | Whether to use SSL to connect                                                        | No       | false   |

#### Interface Options

Options are added directly beneath the interface definition as shown in the example.

| Option           | Description                                                                                |
| ---------------- | ------------------------------------------------------------------------------------------ |
| ACK_TIMEOUT      | Time to wait when connecting to the MQTT broker                                            |
| USERNAME         | Username for authentication with the MQTT broker                                           |
| PASSWORD         | Password for authentication with the MQTT broker                                           |
| CERT             | PEM encoded client certificate filename used with KEY for client TLS based authentication  |
| KEY              | PEM encoded client private keys filename                                                   |
| KEYFILE_PASSWORD | Password to decrypt the CERT and KEY files (Python only)                                   |
| CA_FILE          | Certificate Authority certificate filename that is to be treated as trusted by this client |

plugin.txt Ruby Example:

```ruby
INTERFACE MQTT_INT mqtt_interface.rb test.mosquitto.org 1883
```

plugin.txt Python Example (Note: This example uses the [SECRET](plugins#secret) keyword to set the PASSWORD option in the Interface):

```ruby
INTERFACE MQTT_INT openc3/interfaces/mqtt_interface.py test.mosquitto.org 8884
  OPTION USERNAME rw
  # Create an env variable called MQTT_PASSWORD with the secret named PASSWORD
  # and set an OPTION called PASSWORD with the secret value
  # For more information about secrets see the Admin Tool page
  SECRET ENV PASSWORD MQTT_PASSWORD PASSWORD
```

#### Packet Definitions

The MQTT Interface utilizes 'META TOPIC &lt;topic name&gt;' in the command and telemetry definition files to determine which topics to publish and receive messages from. Thus to send to the topic 'TEST' you would create a command like the following (Note: The command name 'TEST' does NOT have to match the topic name):

```
COMMAND MQTT TEST BIG_ENDIAN "Test"
  META TOPIC TEST # <- The topic name is 'TEST'
  APPEND_PARAMETER DATA 0 BLOCK '' "MQTT Data"
```

Similarly to receive from the topic 'TEST' you would create a telemetry packet like the following (Note: The telemetry name 'TEST' does NOT have to match the topic name):

```
TELEMETRY MQTT TEST BIG_ENDIAN "Test"
  META TOPIC TEST # <- The topic name is 'TEST'
  APPEND_ITEM DATA 0 BLOCK "MQTT Data"
```

For a full example, please see the [openc3-cosmos-mqtt-test](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-mqtt-test) in the COSMOS source.

### MQTT Streaming Interface

The MQTT streaming interface is typically used for connecting to Internet of Things (IoT) devices. The COSMOS MQTT streaming interface is a client that can both publish and receive messages (commands and telemetry). It has built in support for SSL certificates as well as authentication. It differs from the MQTT Interface in that all the commands are transmitted on a single topic and all telemetry is received on a single topic.

| Parameter          | Description                                                                             | Required | Default    |
| ------------------ | --------------------------------------------------------------------------------------- | -------- | ---------- |
| Host               | Host name or IP address of the MQTT broker                                              | Yes      |            |
| Port               | Port on the MQTT broker to connect to. Keep in mind whether you're using SSL or not.    | No       | 1883       |
| SSL                | Whether to use SSL to connect                                                           | No       | false      |
| Write Topic        | Name of the write topic for all commands. Pass nil / None to make interface read only.  | No       | nil / None |
| Read Topic         | Name of the read topic for all telemetry. Pass nil / None to make interface write only. | No       | nil / None |
| Protocol Type      | See Protocols.                                                                          | No       |
| Protocol Arguments | See Protocols for the arguments each stream protocol takes.                             | No       |

#### Interface Options

Options are added directly beneath the interface definition as shown in the example.

| Option           | Description                                                                                |
| ---------------- | ------------------------------------------------------------------------------------------ |
| ACK_TIMEOUT      | Time to wait when connecting to the MQTT broker                                            |
| USERNAME         | Username for authentication with the MQTT broker                                           |
| PASSWORD         | Password for authentication with the MQTT broker                                           |
| CERT             | PEM encoded client certificate filename used with KEY for client TLS based authentication  |
| KEY              | PEM encoded client private keys filename                                                   |
| KEYFILE_PASSWORD | Password to decrypt the CERT and KEY files (Python only)                                   |
| CA_FILE          | Certificate Authority certificate filename that is to be treated as trusted by this client |

plugin.txt Ruby Example:

```ruby
INTERFACE MQTT_INT mqtt_stream_interface.rb test.mosquitto.org 1883 false write read
```

plugin.txt Python Example (Note: This example uses the [SECRET](plugins#secret) keyword to set the PASSWORD option in the Interface):

```ruby
INTERFACE MQTT_INT openc3/interfaces/mqtt_stream_interface.py test.mosquitto.org 8884 False write read
  OPTION USERNAME rw
  # Create an env variable called MQTT_PASSWORD with the secret named PASSWORD
  # and set an OPTION called PASSWORD with the secret value
  # For more information about secrets see the Admin Tool page
  SECRET ENV PASSWORD MQTT_PASSWORD PASSWORD
```

#### Packet Definitions

The MQTT Streaming Interface utilizes the topic names passed to the interface so no additional information is necessary in the definition.

For a full example, please see the [openc3-cosmos-mqtt-test](https://github.com/OpenC3/cosmos/tree/main/openc3-cosmos-init/plugins/packages/openc3-cosmos-mqtt-test) in the COSMOS source.

### Serial Interface

The serial interface connects to a target over a serial port. COSMOS provides drivers for both Windows and POSIX drivers for UNIX based systems. The Serial Interface is currently only implemented in Ruby.

| Parameter          | Description                                                                                        | Required |
| ------------------ | -------------------------------------------------------------------------------------------------- | -------- |
| Write Port         | Name of the serial port to write, e.g. 'COM1' or '/dev/ttyS0'. Pass nil / None to disable writing. | Yes      |
| Read Port          | Name of the serial port to read, e.g. 'COM1' or '/dev/ttyS0'. Pass nil / None to disable reading.  | Yes      |
| Baud Rate          | Baud rate to read and write                                                                        | Yes      |
| Parity             | Serial port parity. Must be 'NONE', 'EVEN', or 'ODD'.                                              | Yes      |
| Stop Bits          | Number of stop bits, e.g. 1.                                                                       | Yes      |
| Write Timeout      | Number of seconds to wait before aborting the write                                                | Yes      |
| Read Timeout       | Number of seconds to wait before aborting the read. Pass nil / None to block on read.              | Yes      |
| Protocol Type      | See Protocols.                                                                                     | No       |
| Protocol Arguments | See Protocols for the arguments each stream protocol takes.                                        | No       |

#### Interface Options

Options are added directly beneath the interface definition as shown in the example.

| Option       | Description                                              | Default |
| ------------ | -------------------------------------------------------- | ------- |
| FLOW_CONTROL | Serial port flow control. Must be one of NONE or RTSCTS. | NONE    |
| DATA_BITS    | Number of data bits.                                     | 8       |

plugin.txt Ruby Examples:

```ruby
INTERFACE INTERFACE_NAME serial_interface.rb COM1 COM1 9600 NONE 1 10.0 nil LENGTH 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
INTERFACE INTERFACE_NAME serial_interface.rb /dev/ttyS1 /dev/ttyS1 38400 ODD 1 10.0 nil BURST 4 0xDEADBEEF
INTERFACE INTERFACE_NAME serial_interface.rb COM2 COM2 19200 EVEN 1 10.0 nil FIXED 6 0 nil true
INTERFACE INTERFACE_NAME serial_interface.rb COM4 COM4 115200 NONE 1 10.0 10.0 TERMINATED 0x0D0A 0x0D0A true 0 0xF005BA11
INTERFACE INTERFACE_NAME serial_interface.rb COM4 COM4 115200 NONE 1 10.0 10.0 TEMPLATE 0xA 0xA
INTERFACE INTERFACE_NAME serial_interface.rb /dev/ttyS0 /dev/ttyS0 57600 NONE 1 10.0 nil PREIDENTIFIED 0xCAFEBABE
INTERFACE INTERFACE_NAME serial_interface.rb COM4 COM4 115200 NONE 1 10.0 10.0 # no built-in protocol
  OPTION FLOW_CONTROL RTSCTS
  OPTION DATA_BITS 7
```

### SNMP Interface (Enterprise)

The SNMP Interface is for connecting to Simple Network Management Protocol devices. The SNMP Interface is currently only implemented in Ruby.

| Parameter | Description                  | Required | Default |
| --------- | ---------------------------- | -------- | ------- |
| Host      | Host name of the SNMP device | Yes      |         |
| Port      | Port on the SNMP device      | No       | 161     |

#### Interface Options

Options are added directly beneath the interface definition as shown in the example.

| Option         | Description                                        | Default |
| -------------- | -------------------------------------------------- | ------- |
| VERSION        | SNMP Version: 1, 2, or 3                           | 1       |
| COMMUNITY      | Password or user ID that allows access to a device | private |
| USERNAME       | Username                                           | N/A     |
| RETRIES        | Retries when sending requests                      | N/A     |
| TIMEOUT        | Timeout waiting for a response from an agent       | N/A     |
| CONTEXT        | SNMP context                                       | N/A     |
| SECURITY_LEVEL | Must be one of NO_AUTH, AUTH_PRIV, or AUTH_NO_PRIV | N/A     |
| AUTH_PROTOCOL  | Must be one of MD5, SHA, or SHA256                 | N/A     |
| PRIV_PROTOCOL  | Must be one of DES or AES                          | N/A     |
| AUTH_PASSWORD  | Auth password                                      | N/A     |
| PRIV_PASSWORD  | Priv password                                      | N/A     |

plugin.txt Ruby Examples:

```ruby
INTERFACE SNMP_INT snmp_interface.rb 192.168.1.249 161
  OPTION VERSION 1
```

For a full example, please see the [openc3-cosmos-apc-switched-pdu](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-apc-switched-pdu) in the COSMOS Enterprise Plugins.

### SNMP Trap Interface (Enterprise)

The SNMP Trap Interface is for receiving Simple Network Management Protocol traps. The SNMP Trap Interface is currently only implemented in Ruby.

| Parameter    | Description                 | Required | Default |
| ------------ | --------------------------- | -------- | ------- |
| Read Port    | Port to read from           | No       | 162     |
| Read Timeout | Read timeout                | No       | nil     |
| Bind Address | Address to bind UDP port to | Yes      | 0.0.0.0 |

#### Interface Options

Options are added directly beneath the interface definition as shown in the example.

| Option  | Description              | Default |
| ------- | ------------------------ | ------- |
| VERSION | SNMP Version: 1, 2, or 3 | 1       |

plugin.txt Ruby Examples:

```ruby
INTERFACE SNMP_INT snmp_trap_interface.rb 162
  OPTION VERSION 1
```

For a full example, please see the [openc3-cosmos-apc-switched-pdu](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-apc-switched-pdu) in the COSMOS Enterprise Plugins.

### GEMS Interface (Enterprise)

### InfluxDb Interface (Enterprise)

## Custom Interfaces

Interfaces have the following methods that must be implemented:

1. **connect** - Open the socket or port or somehow establish the connection to the target. Note: This method may not block indefinitely. Be sure to call super() in your implementation.
1. **connected?** - Return true or false depending on the connection state. Note: This method should return immediately.
1. **disconnect** - Close the socket or port of somehow disconnect from the target. Note: This method may not block indefinitely. Be sure to call super() in your implementation.
1. **read_interface** - Lowest level read of data on the interface. Note: This method should block until data is available or the interface disconnects. On a clean disconnect it should return nil.
1. **write_interface** - Lowest level write of data on the interface. Note: This method may not block indefinitely.

Interfaces also have the following methods that exist and have default implementations. They can be overridden if necessary but be sure to call super() to allow the default implementation to be executed.

1. **read_interface_base** - This method should always be called from read_interface(). It updates interface specific variables that are displayed by CmdTLmServer including the bytes read count, the most recent raw data read, and it handles raw logging if enabled.
1. **write_interface_base** - This method should always be called from write_interface(). It updates interface specific variables that are displayed by CmdTLmServer including the bytes written count, the most recent raw data written, and it handles raw logging if enabled.
1. **read** - Read the next packet from the interface. COSMOS implements this method to allow the Protocol system to operate on the data and the packet before it is returned.
1. **write** - Send a packet to the interface. COSMOS implements this method to allow the Protocol system to operate on the packet and the data before it is sent.
1. **write_raw** - Send a raw binary string of data to the target. COSMOS implements this method by basically calling write_interface with the raw data.

:::warning Naming Conventions
When creating your own interfaces, in most cases they will be subclasses of one of the built-in interfaces described below. It is important to know that both the filename and class name of the interface files must match with correct capitalization or you will receive "class not found" errors when trying to load your new interface. For example, an interface file called labview_interface.rb must contain the class LabviewInterface. If the class was named, LabVIEWInterface, for example, COSMOS would not be able to find the class because of the unexpected capitalization.
:::
