---
sidebar_position: 8
title: Accessors
description: Responsible for reading and writing data to a buffer
sidebar_custom_props:
  myEmoji: ✏️
---

Accessors are the low level code which know how to read and write data into a buffer. The buffer data then gets written out an interface which uses protocols to potentially change the data before it goes to the target. Accessors handle the different serializations formats such as binary (CCSDS), JSON, CBOR, XML, HTML, Protocol Buffers, etc.

For more information about how Accessors fit with Interfaces and Protocols see [Interoperability Without Standards](https://www.openc3.com/news/interoperability-without-standards).

COSMOS provides the following built-in accessors: Binary, CBOR, Form, HTML, HTTP, JSON, Template, XML.

COSMOS Enterprise provides the following accessors: GEMS Ascii, Prometheus, Protocol Buffer.

### Binary Accessor

The Binary Accessor serializes data into a binary format when writing to the buffer. This is how many devices expect their data including those following the CCSDS standard. COSMOS handles converting signed and unsigned integers, floats, strings, etc. into their binary representation in the buffer. This includes handling big and little endian, bitfields, and variable length fields. Since binary is so common this is the default Accessor and will be used if no other accessors are given.

#### Commands

```ruby
COMMAND INST COLLECT BIG_ENDIAN "Starts a collect"
  ACCESSOR BinaryAccessor # Typically not explicitly defined because it is the default
  PARAMETER TYPE       64  16  UINT MIN MAX 0 "Collect type"
  PARAMETER DURATION   80  32  FLOAT 0.0 10.0 1.0 "Collect duration"
  PARAMETER OPCODE    112   8  UINT 0x0 0xFF 0xAB "Collect opcode"
```

#### Telemetry

```ruby
TELEMETRY INST HEALTH_STATUS BIG_ENDIAN "Health and status"
  ACCESSOR BinaryAccessor # Typically not explicitly defined because it is the default
  APPEND_ITEM CMD_ACPT_CNT   32 UINT  "Command accept count"
  APPEND_ITEM COLLECTS       16 UINT  "Number of collects"
  APPEND_ITEM DURATION       32 FLOAT "Most recent collect duration"
```

### CBOR Accessor

The Concise Binary Object Representation ([CBOR](https://en.wikipedia.org/wiki/CBOR)) Accessor serializes data into a binary format loosely based on JSON. It is a subclass of the JSON Accessor and is what COSMOS uses natively to store log files.

#### Commands

Using the CBOR Accessor for [command definitions](command) requires the use of [TEMPLATE_FILE](command#template_file) and [KEY](command#key) to allow the user to set values in the CBOR data. Note that the KEY values are the [JSONPath](https://en.wikipedia.org/wiki/JSONPath) to access the values.

```ruby
COMMAND CBOR CBORCMD BIG_ENDIAN "CBOR Accessor Command"
  ACCESSOR CborAccessor
  TEMPLATE_FILE _cbor_template.bin
  APPEND_ID_PARAMETER ID_ITEM 32 INT 2 2 2 "Int Item"
    KEY $.id_item
  APPEND_PARAMETER ITEM1 16 UINT MIN MAX 101 "Int Item 2"
    KEY $.item1
    UNITS CELSIUS C
  APPEND_PARAMETER ITEM2 16 UINT MIN MAX 12 "Int Item 3"
    KEY $.more.item2
    FORMAT_STRING "0x%X"
  APPEND_PARAMETER ITEM3 64 FLOAT MIN MAX 3.14 "Float Item"
    KEY $.more.item3
  APPEND_PARAMETER ITEM4 128 STRING "Example" "String Item"
    KEY $.more.item4
  APPEND_ARRAY_PARAMETER ITEM5 8 UINT 0 "Array Item"
    KEY $.more.item5
```

Creating the template file requires the use of the Ruby or Python CBOR libraries. Here is an example from Ruby:

```ruby
require 'cbor'
data = {"id_item" : 2, "item1" : 101, "more" : { "item2" : 12, "item3" : 3.14, "item4" : "Example", "item5" : [4, 3, 2, 1] } }
File.open("_cbor_template.bin", 'wb') do |file|
  file.write(data.to_cbor)
end
```

#### Telemetry

Using the CBOR Accessor for [telemetry definitions](telemetry) only requires the use of [KEY](command#key) to pull values from the CBOR data. Note that the KEY values are the [JSONPath](https://en.wikipedia.org/wiki/JSONPath) to access the values.

```ruby
TELEMETRY CBOR CBORTLM BIG_ENDIAN "CBOR Accessor Telemetry"
  ACCESSOR CborAccessor
  APPEND_ID_ITEM ID_ITEM 32 INT 2 "Int Item"
    KEY $.id_item
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY $.item1
    GENERIC_READ_CONVERSION_START UINT 16
      value * 2
    GENERIC_READ_CONVERSION_END
    UNITS CELSIUS C
  APPEND_ITEM ITEM2 16 UINT "Int Item 3"
    KEY $.more.item2
    FORMAT_STRING "0x%X"
  APPEND_ITEM ITEM3 64 FLOAT "Float Item"
    KEY $.more.item3
  APPEND_ITEM ITEM4 128 STRING "String Item"
    KEY $.more.item4
  APPEND_ARRAY_ITEM ITEM5 8 UINT 0 "Array Item"
    KEY $.more.item5
```

### Form Accessor

The Form Accessor is typically used with the [HTTP Client](interfaces#http-client-interface) interface to submit forms to a remote HTTP Server.

#### Commands

Using the Form Accessor for [command definitions](command) requires the use of [KEY](command#key) to allow the user to set values in the HTTP form. Note that the KEY values are the [XPath](https://en.wikipedia.org/wiki/XPath) to access the values.

```ruby
COMMAND FORM FORMCMD BIG_ENDIAN "Form Accessor Command"
  ACCESSOR FormAccessor
  APPEND_ID_PARAMETER ID_ITEM 32 INT 2 2 2 "Int Item"
    KEY $.id_item
  APPEND_PARAMETER ITEM1 16 UINT MIN MAX 101 "Int Item 2"
    KEY $.item1
    UNITS CELSIUS C
```

#### Telemetry

Using the Form Accessor for [telemetry definitions](telemetry) only requires the use of [KEY](command#key) to pull values from the HTTP response data. Note that the KEY values are the [XPath](https://en.wikipedia.org/wiki/XPath) to access the values.

```ruby
TELEMETRY FORM FORMTLM BIG_ENDIAN "Form Accessor Telemetry"
  ACCESSOR FormAccessor
  APPEND_ID_ITEM ID_ITEM 32 INT 1 "Int Item"
    KEY $.id_item
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY $.item1
```

### HTML Accessor

#### Commands

```ruby
COMMAND HTML HTMLCMD BIG_ENDIAN "HTML Accessor Command"
  ACCESSOR HtmlAccessor
  TEMPLATE '<!DOCTYPE html><html lang="en"><head><title>4</title><script src="101"></script></head><body><noscript>12</noscript><img src="3.14" alt="An Image"/><p>Example</p><ul><li>1</li><li>3.14</li></ul></body></html>'
  APPEND_ID_PARAMETER ID_ITEM 32 INT 4 4 4 "Int Item"
    KEY "/html/head/title/text()"
  APPEND_PARAMETER ITEM1 16 UINT MIN MAX 101 "Int Item 2"
    KEY "/html/head/script/@src"
    UNITS CELSIUS C
  APPEND_PARAMETER ITEM2 16 UINT MIN MAX 12 "Int Item 3"
    KEY "/html/body/noscript/text()"
    FORMAT_STRING "0x%X"
  APPEND_PARAMETER ITEM3 64 FLOAT MIN MAX 3.14 "Float Item"
    KEY "/html/body/img/@src"
  APPEND_PARAMETER ITEM4 128 STRING "Example" "String Item"
    KEY "/html/body/p/text()"
```

#### Telemetry

```ruby
TELEMETRY HTML HTMLTLM BIG_ENDIAN "HTML Accessor Telemetry"
  ACCESSOR HtmlAccessor
  APPEND_ID_ITEM ID_ITEM 32 INT 4 "Int Item"
    KEY "/html/head/title/text()"
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY "/html/head/script/@src"
    GENERIC_READ_CONVERSION_START UINT 16
      value * 2
    GENERIC_READ_CONVERSION_END
    UNITS CELSIUS C
  APPEND_ITEM ITEM2 16 UINT "Int Item 3"
    KEY "/html/body/noscript/text()"
    FORMAT_STRING "0x%X"
  APPEND_ITEM ITEM3 64 FLOAT "Float Item"
    KEY "/html/body/img/@src"
  APPEND_ITEM ITEM4 128 STRING "String Item"
    KEY "/html/body/p/text()"
```

### HTTP Accessor

### JSON Accessor

The JSON Accessor serializes data into JavaScript Object Notation ([JSON](https://en.wikipedia.org/wiki/JSON)). JSON is a data interchange format that uses human-readable text to transmit data consisting of key value pairs and arrays.

#### Commands

Using the JSON Accessor for [command definitions](command) requires the use of [TEMPLATE](command#template) and [KEY](command#key) to allow the user to set values in the JSON data. Note that the KEY values are the [JSONPath](https://en.wikipedia.org/wiki/JSONPath) to access the values.

```ruby
COMMAND JSON JSONCMD BIG_ENDIAN "JSON Accessor Command"
  ACCESSOR JsonAccessor
  TEMPLATE '{"id_item":1, "item1":101, "more": { "item2":12, "item3":3.14, "item4":"Example", "item5":[4, 3, 2, 1] } }'
  APPEND_ID_PARAMETER ID_ITEM 32 INT 2 2 2 "Int Item"
    KEY $.id_item
  APPEND_PARAMETER ITEM1 16 UINT MIN MAX 101 "Int Item 2"
    KEY $.item1
    UNITS CELSIUS C
  APPEND_PARAMETER ITEM2 16 UINT MIN MAX 12 "Int Item 3"
    KEY $.more.item2
    FORMAT_STRING "0x%X"
  APPEND_PARAMETER ITEM3 64 FLOAT MIN MAX 3.14 "Float Item"
    KEY $.more.item3
  APPEND_PARAMETER ITEM4 128 STRING "Example" "String Item"
    KEY $.more.item4
  APPEND_ARRAY_PARAMETER ITEM5 8 UINT 0 "Array Item"
    KEY $.more.item5
```

#### Telemetry

Using the JSON Accessor for [telemetry definitions](telemetry) only requires the use of [KEY](command#key) to pull values from the JSON data. Note that the KEY values are the [JSONPath](https://en.wikipedia.org/wiki/JSONPath) to access the values.

```ruby
TELEMETRY JSON JSONTLM BIG_ENDIAN "JSON Accessor Telemetry"
  ACCESSOR JsonAccessor
  APPEND_ID_ITEM ID_ITEM 32 INT 1 "Int Item"
    KEY $.id_item
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY $.item1
    GENERIC_READ_CONVERSION_START UINT 16
      value * 2
    GENERIC_READ_CONVERSION_END
    UNITS CELSIUS C
  APPEND_ITEM ITEM2 16 UINT "Int Item 3"
    KEY $.more.item2
    FORMAT_STRING "0x%X"
  APPEND_ITEM ITEM3 64 FLOAT "Float Item"
    KEY $.more.item3
  APPEND_ITEM ITEM4 128 STRING "String Item"
    KEY $.more.item4
  APPEND_ARRAY_ITEM ITEM5 8 UINT 0 "Array Item"
    KEY $.more.item5
```

### Template Accessor

### XML Accessor

### GEMS Ascii (Enterprise)

### Prometheus (Enterprise)

### Protocol Buffer (Enterprise)
