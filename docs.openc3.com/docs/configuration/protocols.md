---
sidebar_position: 7
title: Protocols
---

Protocols process data on behalf of an Interface. They can modify the data being written, data being read, or both. Protocols can also mark a packet as stored instead of real-time which means COSMOS will not update the current value table with the packet data. Protocols can be layered and will be processed in order. For example, if you have a low-level encryption layer that must be first removed before processing a higher level buffer length protocol.

:::info Protocol Run Order
Read protocols execute in the order specified (First specified runs first). Write protocols execute in the reverse order (Last specified executes first).
:::

Protocols are typically used to define the logic to delineate packets and manipulate data as it written to and read from Interfaces. COSMOS includes Interfaces for TCP/IP Client, TCP/IP Server, Udp Client / Server, and Serial connections. For 99% of use cases these Interfaces should not require any changes as they universally handle the low-level details of reading and writing from these types of connections. All unique behavior should now be defined in Protocols.

At a minimum, any byte stream based Interface will require a Protocol to delineate packets. TCP/IP and Serial are examples of byte stream based Interfaces. A byte stream is just a simple stream of bytes and thus you need some way to know where packets begin and end within the stream.

TCP/IP is a friendly byte stream. Unless you are dealing with a very poorly written system, the first byte received on a TCP/IP connection will always be the start of a packet. Also, TCP/IP is a reliable connection in that it ensures that all data is received in the correct order, that no data is lost, and that the data is not corrupted (TCP/IP is protected by a CRC32 which is pretty good for avoiding unrecognized data corruption).

Serial is a much less friendly byte stream. With serial connections, it is very likely that when you open a serial port and start receiving data you will receive the middle of a message. (This problem is only avoided when interfacing with a system that only writes to the serial port in response to a command). For this reason, sync patterns are highly beneficial for serial interfaces. Additionally, serial interfaces may use some method to protect against unrecognized data corruption (Checksums, CRCs, etc.)

UDP is an inherently packet based connection. If you read from a UDP socket, you will always receive back an entire packet. The best UDP based Protocols take advantage of this fact. Some implementations try to make UDP act like a byte stream, but this is a misuse of the protocol because it is highly likely that you will lose data and have no way to recover.

## Packet Delineation Protocols

COSMOS provides the following packet delineation protocols: COBS, SLIP, CmdResponse, Burst, Fixed, Length, Template (deprecated), Terminated and Preidentified. Each of these protocols has the primary purpose of separating out packets from a byte stream.

Note that all protocols take a final parameter called "Allow Empty Data". This indicates whether the protocol will allow an empty string to be passed down to later Protocols (instead of returning :STOP). Can be true, false, or nil, where nil is interpreted as true unless the Protocol is the last Protocol of the chain. End users of a protocol will almost always simply leave off this parameter. For more information read the [Custom Protocols](protocols.md#custom-protocols) documentation.

### COBS Protocol

The Consistent Overhead Byte Stuffing (COBS) Protocol is an algorithm for encoding data bytes that results in efficient, reliable, unambiguous packet framing regardless of packet content, thus making it easy for receiving applications to recover from malformed packets. It employs the zero byte value to serve as a packet delimiter (a special value that indicates the boundary between packets). The algorithm replaces each zero data byte with a non-zero value so that no zero data bytes will appear in the packet and thus be misinterpreted as packet boundaries (See https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing for more).

### SLIP Protocol

The Serial Line IP (SLIP) Protocol defines a sequence of characters that frame IP packets on a serial line. It defines two special characters: END and ESC. END is 0xC0 and ESC is 0xDB. To send a packet, a SLIP host simply starts sending the data in the packet. If a data byte is the same code as END character, a two byte sequence of ESC and 0xDC is sent instead. If a data bytes is the same as an ESC character, an two byte sequence of ESC and 0xDD is sent instead. When the last byte in the packet has been sent, an END character is then transmitted (See https://datatracker.ietf.org/doc/html/rfc1055 for more).

| Parameter             | Description                                    | Required | Default            |
| --------------------- | ---------------------------------------------- | -------- | ------------------ |
| Start Char            | Character to place at the start of frames      | No       | nil (no character) |
| Read Strip Characters | Strip off start_char and end_char from reads   | No       | true               |
| Read Enable Escaping  | Whether to enable character escaping on reads  | No       | true               |
| Write Enable Escaping | Whether to enable character escaping on writes | No       | true               |
| End Char              | Character to place at the end of frames        | No       | 0xC0               |
| Esc Char              | Escape character                               | No       | 0xDB               |
| Escape End Char       | Character to escape End character              | No       | 0xDC               |
| Escape Esc Char       | Character to escape Esc character              | No       | 0xDD               |

### CmdResponse Protocol

The CmdResponse Protocol waits for a response for any commands with a defined response packet.

| Parameter               | Description                                                                                                  | Required | Default |
| ----------------------- | ------------------------------------------------------------------------------------------------------------ | -------- | ------- |
| Response Timeout        | Number of seconds to wait before timing out when waiting for a response                                      | No       | 5       |
| Response Polling Period | Number of seconds to wait between polling for a response                                                     | No       | 0.02    |
| Raise Exceptions        | Whether to raise exceptions when errors occur in the protocol like unexpected responses or response timeouts | No       | false   |

### Burst Protocol

The Burst Protocol simply reads as much data as it can from the interface before returning the data as a COSMOS Packet (It returns a packet for each burst of data read). This Protocol relies on regular bursts of data delimited by time and thus is not very robust. However, it can utilize a sync pattern which does allow it to re-sync if necessary. It can also discard bytes from the incoming data to remove the sync pattern. Finally, it can add sync patterns to data being written out of the Interface.

| Parameter             | Description                                                                                                                                                                                 | Required | Default                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------ |
| Discard Leading Bytes | The number of bytes to discard from the binary data after reading. Note that this applies to bytes starting with the sync pattern if the sync pattern is being used.                        | No       | 0 (do not discard bytes) |
| Sync Pattern          | Hex string representing a byte pattern that will be searched for in the raw data. This pattern represents a packet delimiter and all data found including the sync pattern will be returned | No       | nil (no sync pattern)    |
| Fill Fields           | Whether to fill in the sync pattern on outgoing packets                                                                                                                                     | No       | false                    |

### Fixed Protocol

The Fixed Protocol reads a preset minimum amount of data which is necessary to properly identify all the defined packets using the interface. It then identifies the packet and proceeds to read as much data from the interface as necessary to create the packet which it then returns. This protocol relies on all the packets on the interface being fixed in length. For example, all the packets using the interface are a fixed size and contain a simple header with a 32-bit sync pattern followed by a 16 bit ID. The Fixed Protocol would elegantly handle this case with a minimum read size of 6 bytes. The Fixed Protocol also supports a sync pattern, discarding leading bytes, and filling the sync pattern similar to the Burst Protocol.

| Parameter             | Description                                                                                                                                                                                  | Required | Default                    |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | -------------------------- |
| Minimum ID Size       | The minimum number of bytes needed to identify a packet. All the packet definitions must declare their ID_ITEM(s) within this given number of bytes.                                         | Yes      |
| Discard Leading Bytes | The number of bytes to discard from the binary data after reading. Note that this applies to bytes starting with the sync pattern if the sync pattern is being used.                         | No       | 0 (do not discard bytes)   |
| Sync Pattern          | Hex string representing a byte pattern that will be searched for in the raw data. This pattern represents a packet delimiter and all data found including the sync pattern will be returned. | No       | nil (no sync pattern)      |
| Telemetry             | Whether the data is telemetry                                                                                                                                                                | No       | true (false means command) |
| Fill Fields           | Whether to fill in the sync pattern on outgoing packets                                                                                                                                      | No       | false                      |
| Unknown Raise         | Whether to raise an exception for an unknown packet                                                                                                                                          | No       | false                      |

### Length Protocol

The Length Protocol depends on a length field at a fixed location in the defined packets using the interface. It then reads enough data to grab the length field, decodes it, and reads the remaining length of the packet. For example, all the packets using the interface contain a CCSDS header with a length field. The Length Protocol can be set up to handle the length field and even the length offset CCSDS uses. The Length Protocol also supports a sync pattern, discarding leading bytes, and filling the length and sync pattern similar to the Burst Protocol.

| Parameter                    | Description                                                                                                                                                                                                                                                                                                                                                                                                                  | Required | Default                  |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------ |
| Length Bit Offset            | The bit offset from the start of the packet to the length field. Every packet using this interface must have the same structure such that the length field is the same size at the same location. Be sure to account for the length of the Sync Pattern in this value (if present).                                                                                                                                          | No       | 0 bits                   |
| Length Bit Size              | The size in bits of the length field                                                                                                                                                                                                                                                                                                                                                                                         | No       | 16 bits                  |
| Length Value Offset          | The offset to apply to the length field value. The actual value of the length field plus this offset should equal the exact number of bytes required to read all data for the packet (including the length field itself, sync pattern, etc). For example, if the length field indicates packet length minus one, this value should be one. Be sure to account for the length of the Sync Pattern in this value (if present). | No       | 0                        |
| Bytes per Count              | The number of bytes per each length field 'count'. This is used if the units of the length field is something other than bytes, e.g. if the length field count is in words.                                                                                                                                                                                                                                                  | No       | 1 byte                   |
| Length Endianness            | The endianness of the length field. Must be either 'BIG_ENDIAN' or 'LITTLE_ENDIAN'.                                                                                                                                                                                                                                                                                                                                          | No       | 'BIG_ENDIAN'             |
| Discard Leading Bytes        | The number of bytes to discard from the binary data after reading. Note that this applies to bytes including the sync pattern if the sync pattern is being used. Discarding is one of the very last steps so any size and offsets above need to account for all the data before discarding.                                                                                                                                  | No       | 0 (do not discard bytes) |
| Sync Pattern                 | Hex string representing a byte pattern that will be searched for in the raw data. This pattern represents a packet delimiter and all data found including the sync pattern will be returned.                                                                                                                                                                                                                                 | No       | nil (no sync pattern)    |
| Max Length                   | The maximum allowed value in the length field                                                                                                                                                                                                                                                                                                                                                                                | No       | nil (no maximum length)  |
| Fill Length and Sync Pattern | Setting this flag to true causes the length field and sync pattern (if present) to be filled automatically on outgoing packets.                                                                                                                                                                                                                                                                                              | No       | false                    |

The most confusing aspect of the Length Protocol is calculating the Length Value Offset. This is especially true in the commonly used CCSDS Space Packet Protocol. The best way to illustrate this is with an example. Suppose you have CCSDS Space Packets prepended with a Sync Pattern of 0x1ACFFC1D. This would look like the following:

| Sync (4 bytes) | Header (4 bytes) | Length (2 bytes) | Data (4 bytes) |
| -------------- | ---------------- | ---------------- | -------------- |
| 0x1ACFFC1D     | 0x0001CADB       | 0x0003           | 0xDEADBEEF     |

In this case the total length of the packet is 14 bytes: **4 + 4 + 2 + 4 = 14**. With 4 bytes of data, the length field is 3 because in CCSDS the length field is calculated as (data length - 1). So how would we calculate the Length Value Offset? COSMOS reads all the bytes in the packet (including the Sync Pattern) so the total length is 14 bytes. The length field is 3 so the Length Value Offset (offset to apply to the length field value) should be 11 (**3 + 11 = 14**).

### Terminated Protocol

The Terminated Protocol delineates packets using termination characters found at the end of every packet. It continuously reads data until the termination characters are found at which point it returns the packet data. For example, all the packets using the interface are followed by 0xABCD. This data can either be a part of each packet that is kept or something which is known only by the Terminated Protocol and simply thrown away.

| Parameter                    | Description                                                                                                                                                                                  | Required | Default                  |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------ |
| Write Termination Characters | The data to write after writing a command packet. Given as a hex string such as 0xABCD.                                                                                                      | Yes      |
| Read Termination Characters  | The characters which delineate the end of a telemetry packet. Given as a hex string such as 0xABCD.                                                                                          | Yes      |
| Strip Read Termination       | Whether to remove the read termination characters before returning the telemetry packet                                                                                                      | No       | true                     |
| Discard Leading Bytes        | The number of bytes to discard from the binary data after reading. Note that this applies to bytes including the sync pattern if the sync pattern is being used.                             | No       | 0 (do not discard bytes) |
| Sync Pattern                 | Hex string representing a byte pattern that will be searched for in the raw data. This pattern represents a packet delimiter and all data found including the sync pattern will be returned. | No       | nil (no sync pattern)    |
| Fill Fields                  | Whether to fill in the sync pattern on outgoing packets                                                                                                                                      | No       | false                    |

### Template Protocol

**Deprecated**

This protocol is now deprecated because it is not able to capture the original SCPI messages in COSMOS raw logging. Please use the TemplateAccessor with the CmdResponseProtocol instead.

The Template Protocol works much like the Terminated Protocol except it is designed for text-based command and response type interfaces such as SCPI (Standard Commands for Programmable Instruments). It delineates packets in the same way as the Terminated Protocol except each packet is referred to as a line (because each usually contains a line of text). For outgoing packets, a CMD_TEMPLATE field is expected to exist in the packet. This field contains a template string with items to be filled in delineated within HTML tag style brackets `"<EXAMPLE>"`. The Template Protocol will read the named items from within the packet and fill in the CMD_TEMPLATE. This filled in string is then sent out rather than the originally passed in packet. Correspondingly, if a response is expected the outgoing packet should include a RSP_TEMPLATE and RSP_PACKET field. The RSP_TEMPLATE is used to extract data from the response string and build a corresponding RSP_PACKET. See the TEMPLATE target within the COSMOS Demo configuration for an example of usage.

| Parameter                    | Description                                                                                                                                                                                  | Required | Default                  |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- | ------------------------ |
| Write Termination Characters | The data to write after writing a command packet. Given as a hex string such as 0xABCD.                                                                                                      | Yes      |
| Read Termination Characters  | The characters which delineate the end of a telemetry packet. Given as a hex string such as 0xABCD.                                                                                          | Yes      |
| Ignore Lines                 | Number of response lines to ignore (completely drop)                                                                                                                                         | No       | 0 lines                  |
| Initial Read Delay           | An initial delay after connecting after which the interface will be read till empty and data dropped. Useful for discarding connect headers and initial prompts.                             | No       | nil (no initial read)    |
| Response Lines               | The number of lines that make up expected responses                                                                                                                                          | No       | 1 line                   |
| Strip Read Termination       | Whether to remove the read termination characters before returning the telemetry packet                                                                                                      | No       | true                     |
| Discard Leading Bytes        | The number of bytes to discard from the binary data after reading. Note that this applies to bytes including the sync pattern if the sync pattern is being used.                             | No       | 0 (do not discard bytes) |
| Sync Pattern                 | Hex string representing a byte pattern that will be searched for in the raw data. This pattern represents a packet delimiter and all data found including the sync pattern will be returned. | No       | nil (no sync pattern)    |
| Fill Fields                  | Whether to fill in the sync pattern on outgoing packets                                                                                                                                      | No       | false                    |
| Response Timeout             | Number of seconds to wait for a response before timing out                                                                                                                                   | No       | 5.0                      |
| Response Polling Period      | Number of seconds to wait between polling for a response                                                                                                                                     | No       | 0.02                     |
| Raise Exceptions             | Whether to raise exceptions when errors occur like timeouts or unexpected responses                                                                                                          | No       | false                    |

### Preidentified Protocol

The Preidentified Protocol delineates packets using a custom COSMOS header. This Protocol is created to allow tools to connect and receive the entire packet stream. It can also be used to chain COSMOS instances together although that should rarely be needed with the new web native implementation.

| Parameter    | Description                                                                                                                                                                                                                    | Required | Default                 |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------- | ----------------------- |
| Sync Pattern | Hex string representing a byte pattern that will be searched for in the raw data. This pattern represents a packet delimiter and all data found AFTER the sync pattern will be returned. The sync pattern itself is discarded. | No       | nil (no sync pattern)   |
| Max Length   | The maximum allowed value in the length field                                                                                                                                                                                  | No       | nil (no maximum length) |
| Mode         | The Version of the preidentified protocol to support (2 or 4).3                                                                                                                                                                | No       | 4                       |

## Helper Protocols

COSMOS provides the following helper protocols: Crc & Ignore. These protocols provide helper functionality to Interfaces.

### CRC Protocol

The CRC protocol can add CRCs to outgoing commands and verify CRCs on incoming telemetry packets.

| Parameter       | Description                                                                                                 | Required | Default                                                                                    |
| --------------- | ----------------------------------------------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| Write Item Name | Item to fill with calculated CRC value for outgoing packets (nil = don't fill)                              | No       | nil                                                                                        |
| Strip CRC       | Whether to remove the CRC from incoming packets                                                             | No       | false                                                                                      |
| Bad Strategy    | How to handle CRC errors on incoming packets. ERROR = Just log the error, DISCONNECT = Disconnect interface | No       | "ERROR"                                                                                    |
| Bit Offset      | Bit offset of the CRC in the data. Can be negative to indicate distance from end of packet                  | No       | -32                                                                                        |
| Bit Size        | Bit size of the CRC - Must be 16, 32, or 64                                                                 | No       | 32                                                                                         |
| Endianness      | Endianness of the CRC (BIG_ENDIAN/LITTLE_ENDIAN)                                                            | No       | "BIG_ENDIAN"                                                                               |
| Poly            | Polynomial to use when calculating the CRC expressed as an integer                                          | No       | nil (use default polynomial - 16-bit=0x1021, 32-bit=0x04C11DB7, 64-bit=0x42F0E1EBA9EA3693) |
| Seed            | Seed value to start the calculation                                                                         | No       | nil (use default seed - 16-bit=0xFFFF, 32-bit=0xFFFFFFFF, 64-bit=0xFFFFFFFFFFFFFFFF)       |
| Xor             | Whether to XOR the CRC result with 0xFFFF                                                                   | No       | nil (use default value - 16-bit=false, 32-bit=true, 64-bit=true)                           |
| Reflect         | Whether to bit reverse each byte of data before calculating the CRC                                         | No       | nil (use default value - 16-bit=false, 32-bit=true, 64-bit=true)                           |

### Ignore Packet Protocol

The Ignore Packet protocol drops specified command packets sent by COSMOS or drops incoming telemetry packets.

| Parameter   | Description                         | Required | Default |
| ----------- | ----------------------------------- | -------- | ------- |
| Target Name | Target name of the packet to ignore | Yes      | nil     |
| Packet Name | Packet name of the packet to ignore | Yes      | nil     |

## Custom Protocols

Creating a custom protocol is easy and should be the default solution for customizing COSMOS Interfaces (rather than creating a new Interface class). However, creating custom Interfaces is still useful for defaulting parameters to values that always are fixed for your target and for including the necessary Protocols. The base COSMOS Interfaces take a lot of parameters that can be confusing to your end users. Thus you may want to create a custom Interface just to hard coded these values and cut the available parameters down to something like the hostname and port to connect to.

All custom Protocols should derive from the Protocol class found in the COSMOS gem at [lib/openc3/interfaces/protocols/protocol.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/interfaces/protocols/protocol.rb). This class defines the 9 methods that are relevant to writing your own protocol. The base class implementation for each method is included below as well as a discussion as to how the methods should be overridden and used in your own Protocols.

:::info Protocol APIs
Protocols should not `require 'openc3/script'` since they are part of a COSMOS interface. They should use the COSMOS library code directly like [System](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/system/system.rb), [Packet](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/packets/packet.rb), [Bucket](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/utilities/bucket.rb), [BinaryAccessor](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/accessors/binary_accessor.rb), etc. When in doubt, consult the existing COSMOS [protocol](https://github.com/OpenC3/cosmos/tree/main/openc3/lib/openc3/interfaces/protocols) classes.
:::

To really understand how Protocols work, you first must understand the logic within the base Interface class read and write methods.

Let's first discuss the read method.

![Interface Read Logic](/img/interface_read_logic.png)

On EVERY call to read, an empty Ruby string "" is first passed down to each of the read Protocol's read_data() method BEFORE new raw data is attempted to be read using the Interface's read_interface() method. This is a signal to Protocols that have cached up more than one packet worth of data to output those cached packets before any new data is read from the Interface. Typically no data will be cached up and one of the Protocols read_data() methods will return :STOP in response to the empty string, indicating that more data is required to generate a packet. Each Protocol's read_data() method can return one of three things: data that will be passed down to any additional Protocols or turned into a Packet, :STOP which means more data is required from the Interface for the Protocol to continue, or :DISCONNECT which means that something has happened that requires disconnecting the Interface (and by default trying to reconnect). Each Protocol's read_data method is passed the data that will eventually be turned into a packet and returns a possibly modified set of data. If the data passes through all Protocol's read_data() methods it is then converted into a COSMOS packet using the Interface's convert_data_to_packet() method. This packet is then run in a similar fashion through each Read Protocol's read_packet() method. This method has essentially the same return possibilities: a Packet (instead of data as in read_data()), :STOP, or :DISCONNECT. If the Packet makes it through all read_packet() methods then the Interface packet read counter is incremented and the Packet is returned to the Interface.

![Interface Write Logic](/img/interface_write_logic.png)

The Interface write() method works very similarly to read. (It should be mentioned that by default write protocols run in the reverse order of read protocols. This makes sense because when reading you're typically stripping layers of data and when writing you're typically adding on layers in reverse order.)

First, the packet write counter is incremented. Then each write Protocol is given a chance to modify the packet by its write_packet() method being called. This method can either return a potentially modified packet, :STOP, or :DISCONNECT. If a write Protocol returns :STOP no data will be written out the Interface and it is assumed that more packets are necessary before a final packet can be output. :DISCONNECT will disconnect the Interface. If the packet makes it through all the write Protocol's write_packet() methods, then it is converted to binary data using the Interface's convert_packet_to_data() method. Next the write_data() method is called for each write Protocol giving it a chance to modify the lower level data. The same return options are available except a Ruby string of data is returned instead of a COSMOS packet. If the data makes it through all write_data() methods, then it is written out on the Interface using the write_interface() method. Afterwards, each Protocol's post_write_interface() method is called with both the final modified Packet, and the actual data written out to the Interface. This method allows follow-up such as waiting for a response after writing out a message.

## Method discussions

### initialize

This is the constructor for your custom Protocol. It should always call super(allow_empty_data) to initialize the base Protocol class.

Base class implementation:

```ruby
# @param allow_empty_data [true/false] Whether STOP should be returned on empty data
def initialize(allow_empty_data = false)
  @interface = nil
  @allow_empty_data = ConfigParser.handle_true_false(allow_empty_data)
  reset()
end
```

As you can see, every Protocol maintains state on at least two items. @interface holds the Interface class instance that the protocol is associated with. This is sometimes necessary to introspect details that only the Interface knows. @allow_empty_data is a flag used by the read_data(data) method that is discussed later in this document.

### reset

The reset method is used to reset internal protocol state when the Interface is connected and/or disconnected. This method should be used for common resetting logic. Connect and Disconnect specific logic are handled in the next two methods.

Base class implementation:

```ruby
def reset
end
```

As you can see, the base class reset implementation doesn't do anything.

### connect_reset

The connect_reset method is used to reset internal Protocol state each time the Interface is connected.

Base class implementation:

```ruby
def connect_reset
  reset()
end
```

The base class connect_reset implementation just calls the reset method to ensure common reset logic is run.

### disconnect_reset

The disconnect_reset method is used to reset internal Protocol state each time the Interface is disconnected.

Base class implementation:

```ruby
def disconnect_reset
  reset()
end
```

The base class disconnect_reset implementation just calls the reset method to ensure common reset logic is run.

### read_data

The read_data method is used to analyze and potentially modify any raw data read by an Interface. It takes one parameter as the current state of the data to be analyzed. It can return either a Ruby string of data, :STOP, or :DISCONNECT. If it returns a Ruby string, then it believes that data may be ready to be a full packet, and is ready for processing by any following Protocols. If :STOP is returned then the Protocol believes it needs more data to complete a full packet. If :DISCONNECT is returned then the Protocol believes the Interface should be disconnected (and typically automatically reconnected).

Base Class Implemenation:

```ruby
def read_data(data)
  if (data.length <= 0)
    if @allow_empty_data.nil?
      if @interface and @interface.read_protocols[-1] == self # Last read interface in chain with auto @allow_empty_data
        return :STOP
      end
    elsif !@allow_empty_data # Don't @allow_empty_data means STOP
      return :STOP
    end
  end
  data
end
```

The base class implementation does nothing except return the data it was given. The only exception to this is when handling an empty string. If the allow_empty_data flag is false or if it nil and the Protocol is the last in the chain, then the base implementation will return :STOP data to indicate that it is time to call the Interface read_interface() method to get more data. Blank strings are used to signal Protocols that they have an opportunity to return a cached packet.

### read_packet

The read_packet method is used to analyze and potentially modify a COSMOS packet before it is returned by the Interface. It takes one parameter as the current state of the packet to be analyzed. It can return either a COSMOS packet, :STOP, or :DISCONNECT. If it returns a COSMOS packet, then it believes that the packet is valid, should be returned, and is ready for processing by any following Protocols. If :STOP is returned then the Protocol believes the packet should be silently dropped. If :DISCONNECT is returned then the Protocol believes the Interface should be disconnected (and typically automatically reconnected). This method is where a Protocol would set the stored flag on a packet if it determines that the packet is stored telemetry instead of real-time telemetry.

Base Class Implementation:

```ruby
def read_packet(packet)
  return packet
end
```

The base class always just returns the packet given.

### write_packet

The write_packet method is used to analyze and potentially modify a COSMOS packet before it is output by the Interface. It takes one parameter as the current state of the packet to be analyzed. It can return either a COSMOS packet, :STOP, or :DISCONNECT. If it returns a COSMOS packet, then it believes that the packet is valid, should be written out the Interface, and is ready for processing by any following Protocols. If :STOP is returned then the Protocol believes the packet should be silently dropped. If :DISCONNECT is returned then the Protocol believes the Interface should be disconnected (and typically automatically reconnected).

Base Class Implementation:

```ruby
def write_packet(packet)
  return packet
end
```

The base class always just returns the packet given.

### write_data

The write_data method is used to analyze and potentially modify data before it is written out by the Interface. It takes one parameter as the current state of the data to be analyzed and sent. It can return either a Ruby String of data, :STOP, or :DISCONNECT. If it returns a Ruby string of data, then it believes that the data is valid, should be written out the Interface, and is ready for processing by any following Protocols. If :STOP is returned then the Protocol believes the data should be silently dropped. If :DISCONNECT is returned then the Protocol believes the Interface should be disconnected (and typically automatically reconnected).

Base Class Implementation:

```ruby
def write_data(data)
  return data
end
```

The base class always just returns the data given.

### post_write_interface

The post_write_interface method is called after data has been written out the Interface. The typical use of this method is to provide a hook to implement command/response type interfaces where a response is always immediately expected in response to a command. It takes two parameters, the packet after all modifications by write_packet() and the data that was actually written out the Interface. It can return either the same pair of packet/data, :STOP, or :DISCONNECT. If it returns a packet/data pair then they are passed on to any other Protocols. If :STOP is returned then the Interface write() call completes and no further Protocols post_write_interface() methods are called. If :DISCONNECT is returned then the Protocol believes the Interface should be disconnected (and typically automatically reconnected). Note that only the first parameter "packet", is checked to be :STOP, or :DISCONNECT on the return.

Base Class Implementation:

```ruby
def post_write_interface(packet, data)
  return packet, data
end
```

The base class always just returns the packet/data given.

## Examples

Please see the included COSMOS protocol code for examples of the above methods in action.

[lib/openc3/interfaces/protocols/protocol.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/interfaces/protocols/protocol.rb)
[lib/openc3/interfaces/protocols/burst_protocol.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/interfaces/protocols/burst_protocol.rb)
[lib/openc3/interfaces/protocols/fixed_protocol.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/interfaces/protocols/fixed_protocol.rb)
[lib/openc3/interfaces/protocols/length_protocol.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/interfaces/protocols/length_protocol.rb)
[lib/openc3/interfaces/protocols/terminated_protocol.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/interfaces/protocols/terminated_protocol.rb)
[lib/openc3/interfaces/protocols/template_protocol.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/interfaces/protocols/template_protocol.rb)
[lib/openc3/interfaces/protocols/crc_protocol.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/interfaces/protocols/crc_protocol.rb)
[lib/openc3/interfaces/protocols/preidentified_protocol.rb](https://github.com/OpenC3/cosmos/blob/main/openc3/lib/openc3/interfaces/protocols/preidentified_protocol.rb)
