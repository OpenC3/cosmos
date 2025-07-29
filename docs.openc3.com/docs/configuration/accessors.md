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

For a full example see [openc3-cosmos-accessor-test](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-accessor-test).

#### Commands

Using the CBOR Accessor for [command definitions](command) requires the use of [TEMPLATE_FILE](command#template_file) and [KEY](command#key) to allow the user to set values in the CBOR data. Note that the KEY values use [JSONPath](https://en.wikipedia.org/wiki/JSONPath).

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

Using the CBOR Accessor for [telemetry definitions](telemetry) only requires the use of [KEY](command#key) to pull values from the CBOR data. Note that the KEY values use [JSONPath](https://en.wikipedia.org/wiki/JSONPath).

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

Using the Form Accessor for [command definitions](command) requires the use of [KEY](command#key) to allow the user to set values in the HTTP form. Note that the KEY values use [XPath](https://en.wikipedia.org/wiki/XPath).

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

Using the Form Accessor for [telemetry definitions](telemetry) only requires the use of [KEY](command#key) to pull values from the HTTP response data. Note that the KEY values use [XPath](https://en.wikipedia.org/wiki/XPath).

```ruby
TELEMETRY FORM FORMTLM BIG_ENDIAN "Form Accessor Telemetry"
  ACCESSOR FormAccessor
  APPEND_ID_ITEM ID_ITEM 32 INT 1 "Int Item"
    KEY $.id_item
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY $.item1
```

### HTML Accessor

The HTML Accessor is typically used with the [HTTP Client](interfaces#http-client-interface) interface to parse a web page.

For a full example see [openc3-cosmos-accessor-test](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-accessor-test).

#### Commands

HTML Accessor is not typically used for commands but it would be similar to Telemetry using XPath Keys.

#### Telemetry

```ruby
TELEMETRY HTML RESPONSE BIG_ENDIAN "Search results"
  # Typically you use the HtmlAccessor to parse out the page that is returned
  # HtmlAccessor is passed to HttpAccessor and used internally
  ACCESSOR HttpAccessor HtmlAccessor
  APPEND_ITEM NAME 240 STRING
    # Keys were located by doing a manual search and then inspecting the page
    # Right click the text you're looking for and then Copy -> Copy XPath
    KEY normalize-space(//main/div/a[2]/span/h2/text())
  APPEND_ITEM DESCRIPTION 480 STRING
    KEY //main/div/a[2]/span/p/text()
  APPEND_ITEM VERSION 200 STRING
    KEY //main/div/a[2]/span/h2/span/text()
  APPEND_ITEM DOWNLOADS 112 STRING
    KEY normalize-space(//main/div/a[2]/p/text())
```

### HTTP Accessor

HTTP Accessor is typically used with the [HTTP Client](interfaces#http-client-interface) or [HTTP Server](interfaces#http-server-interface) interface to parse a web page. It takes another accessor to do the low level reading and writing of the items. The default accessor is FormAccessor. HtlmAccessor, XmlAccessor and JsonAccessor are also common for manipulating HTML, XML and JSON respectively.

For a full example see [openc3-cosmos-http-example](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-http-example).

#### Commands

When used with the HTTP Client Interface, HTTP Accessor utilizes the following command parameters:

| Parameter         | Description                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------- |
| HTTP_PATH         | requests at this path                                                                                |
| HTTP_METHOD       | request method (GET, POST, DELETE)                                                                   |
| HTTP_PACKET       | telemetry packet to store the response                                                               |
| HTTP_ERROR_PACKET | telemetry packet to store error responses (status code >= 300)                                       |
| HTTP_QUERY_XXX    | sets a value in the params passed to the request (XXX => value, or KEY => value), see example below  |
| HTTP_HEADER_XXX   | sets a value in the headers passed to the request (XXX => value, or KEY => value), see example below |

When used with the HTTP Server Interface, HTTP Accessor utilizes the following command parameters:

| Parameter       | Description                                                                             |
| --------------- | --------------------------------------------------------------------------------------- |
| HTTP_STATUS     | status to return to clients                                                             |
| HTTP_PATH       | mount point for server                                                                  |
| HTTP_PACKET     | telemetry packet to store the request                                                   |
| HTTP_HEADER_XXX | sets a value in the response headers (XXX => value, or KEY => value), see example below |

```ruby
COMMAND HTML SEARCH BIG_ENDIAN "Searches Rubygems.org"
  # Note FormAccessor is the default argument for HttpAccessor so it is typically not specified
  ACCESSOR HttpAccessor
  PARAMETER HTTP_PATH 0 0 DERIVED nil nil "/search"
  PARAMETER HTTP_METHOD 0 0 DERIVED nil nil "GET"
  PARAMETER HTTP_PACKET 0 0 DERIVED nil nil "RESPONSE"
  PARAMETER HTTP_ERROR_PACKET 0 0 DERIVED nil nil "ERROR"
  # This sets parameter query=openc3+cosmos
  # Note the parameter name 'query' based on HTTP_QUERY_QUERY
  PARAMETER HTTP_QUERY_QUERY 0 0 DERIVED nil nil "openc3 cosmos"
    GENERIC_READ_CONVERSION_START
      value.split.join('+')
    GENERIC_READ_CONVERSION_END
  # This sets header Content-Type=text/html
  # Note that TYPE is not used since the KEY is specified
  PARAMETER HTTP_HEADER_TYPE 0 0 DERIVED nil nil "text/html"
    KEY Content-Type
```

#### Telemetry

HTTP Accessor utilizes the following telemetry items:

| Parameter    | Description                                                                                                           |
| ------------ | --------------------------------------------------------------------------------------------------------------------- |
| HTTP_STATUS  | the request status                                                                                                    |
| HTTP_HEADERS | hash of the response headers                                                                                          |
| HTTP_REQUEST | optional hash which returns all the request parameters, see [HTTP Client Interface](interfaces#http-client-interface) |

```ruby
TELEMETRY HTML RESPONSE BIG_ENDIAN "Search results"
  # Typically you use the HtmlAccessor to parse out the page that is returned
  ACCESSOR HttpAccessor HtmlAccessor
  APPEND_ITEM NAME 240 STRING
    # Keys were located by doing a manual search and then inspecting the page
    # Right click the text you're looking for and then Copy -> Copy XPath
    KEY normalize-space(//main/div/a[2]/span/h2/text())
  APPEND_ITEM DESCRIPTION 480 STRING
    KEY //main/div/a[2]/span/p/text()
  APPEND_ITEM VERSION 200 STRING
    KEY //main/div/a[2]/span/h2/span/text()
  APPEND_ITEM DOWNLOADS 112 STRING
    KEY normalize-space(//main/div/a[2]/p/text())
```

### JSON Accessor

The JSON Accessor serializes data into JavaScript Object Notation ([JSON](https://en.wikipedia.org/wiki/JSON)). JSON is a data interchange format that uses human-readable text to transmit data consisting of key value pairs and arrays.

For a full example see [openc3-cosmos-accessor-test](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-accessor-test).

#### Commands

Using the JSON Accessor for [command definitions](command) requires the use of [TEMPLATE](command#template) and [KEY](command#key) to allow the user to set values in the JSON data. Note that the KEY values use [JSONPath](https://en.wikipedia.org/wiki/JSONPath).

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

Using the JSON Accessor for [telemetry definitions](telemetry) only requires the use of [KEY](command#key) to pull values from the JSON data. Note that the KEY values use [JSONPath](https://en.wikipedia.org/wiki/JSONPath).

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

The Template Accessor is commonly used with string based command / response protocols such as the [Command Response Protocol](protocols#command-response-protocol).

For a full example see [openc3-cosmos-scpi-power-supply](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-scpi-power-supply) in the COSMOS Enterprise Plugins.

#### Commands

Using the Template Accessor for [command definitions](command) requires the use of [TEMPLATE](command#template) to define a string template with optional parameters that are populated using the command parameters.

```ruby
# Some commands don't have any parameters and the template is sent as-is
COMMAND SCPI_PS RESET BIG_ENDIAN "Reset the power supply state"
  ACCESSOR TemplateAccessor
  TEMPLATE "*RST"

# This command has two parameters in the template defined by <XXX>
COMMAND SCPI_PS VOLTAGE BIG_ENDIAN "Sets the voltage of a power supply channel"
  ACCESSOR TemplateAccessor
  # <VOLTAGE> and <CHANNEL> are replaced by the parameter values
  TEMPLATE "VOLT <VOLTAGE>, (@<CHANNEL>)"
  APPEND_PARAMETER VOLTAGE 32 FLOAT MIN MAX 0.0 "Voltage Setting"
    UNITS VOLTS V
  APPEND_PARAMETER CHANNEL 8 UINT 1 2 1 "Output Channel"
```

#### Telemetry

Using the Template Accessor for [telemetry definitions](telemetry) requires the use of [TEMPLATE](telemetry#template) to define a template where telemetry values are pulled from the string buffer.

```ruby
TELEMETRY SCPI_PS STATUS BIG_ENDIAN "Power supply status"
  ACCESSOR TemplateAccessor
  # The raw string from the target is something like "1.234,2.345"
  # String is split by the comma and pushed into MEAS_VOLTAGE_1, MEAS_VOLTAGE_2
  TEMPLATE "<MEAS_VOLTAGE_1>,<MEAS_VOLTAGE_2>"
  APPEND_ITEM MEAS_VOLTAGE_1 32 FLOAT "Current Reading for Channel 1"
  APPEND_ITEM MEAS_VOLTAGE_2 32 FLOAT "Current Reading for Channel 2"
```

### XML Accessor

The XML Accessor is typically used with the [HTTP Client](interfaces#http-client-interface) interface to send and receive XML from a web server.

For a full example see [openc3-cosmos-accessor-test](https://github.com/OpenC3/cosmos/tree/main/examples/openc3-cosmos-accessor-test).

#### Commands

Using the XML Accessor for [command definitions](command) requires the use of [TEMPLATE](command#template) and [KEY](command#key) to allow the user to set values in the XML data. Note that the KEY values use [XPath](https://en.wikipedia.org/wiki/XPath).

```ruby
COMMAND XML XMLCMD BIG_ENDIAN "XML Accessor Command"
  ACCESSOR XmlAccessor
  TEMPLATE '<html><head><script src="3"></script><noscript>101</noscript></head><body><img src="12"/><div><ul><li>3.14</li><li>Example</li></ul></div><div></div></body></html>'
  APPEND_ID_PARAMETER ID_ITEM 32 INT 3 3 3 "Int Item"
    KEY "/html/head/script/@src"
  APPEND_PARAMETER ITEM1 16 UINT MIN MAX 101 "Int Item 2"
    KEY "/html/head/noscript/text()"
    UNITS CELSIUS C
  APPEND_PARAMETER ITEM2 16 UINT MIN MAX 12 "Int Item 3"
    KEY "/html/body/img/@src"
    FORMAT_STRING "0x%X"
  APPEND_PARAMETER ITEM3 64 FLOAT MIN MAX 3.14 "Float Item"
    KEY "/html/body/div/ul/li[1]/text()"
  APPEND_PARAMETER ITEM4 128 STRING "Example" "String Item"
    KEY "/html/body/div/ul/li[2]/text()"
```

#### Telemetry

Using the XML Accessor for [telemetry definitions](telemetry) only requires the use of [KEY](command#key) to pull values from the XML data. Note that the KEY values use [XPath](https://en.wikipedia.org/wiki/XPath).

```ruby
TELEMETRY XML XMLTLM BIG_ENDIAN "XML Accessor Telemetry"
  ACCESSOR XmlAccessor
  # Template is not required for telemetry, but is useful for simulation
  TEMPLATE '<html><head><script src="3"></script><noscript>101</noscript></head><body><img src="12"/><div><ul><li>3.14</li><li>Example</li></ul></div><div></div></body></html>'
  APPEND_ID_ITEM ID_ITEM 32 INT 3 "Int Item"
    KEY "/html/head/script/@src"
  APPEND_ITEM ITEM1 16 UINT "Int Item 2"
    KEY "/html/head/noscript/text()"
    GENERIC_READ_CONVERSION_START UINT 16
      value * 2
    GENERIC_READ_CONVERSION_END
    UNITS CELSIUS C
  APPEND_ITEM ITEM2 16 UINT "Int Item 3"
    KEY "/html/body/img/@src"
    FORMAT_STRING "0x%X"
  APPEND_ITEM ITEM3 64 FLOAT "Float Item"
    KEY "/html/body/div/ul/li[1]/text()"
  APPEND_ITEM ITEM4 128 STRING "String Item"
    KEY "/html/body/div/ul/li[2]/text()"
```

### GEMS Ascii (Enterprise)

The GemsAsciiAccessor inherits from [TemplateAccessor](accessors#template-accessor) to escape the following characters in outgoing commands: "&" => "&a", "|" => "&b", "," => "&c", and ";" => "&d" and reverse them in telemetry. See the [GEMS Spec](https://www.omg.org/spec/GEMS/1.3/PDF) for more information.

For a full example, please see the [openc3-cosmos-gems-interface](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-gems-interface) in the COSMOS Enterprise Plugins.

### Prometheus (Enterprise)

The PrometheusAccessor is used to read from a Prometheus endpoint and can automatically parse the results into a packet. The PrometheusAccessor is currently only implemented in Ruby.

For a full example, please see the [openc3-cosmos-prometheus-metrics](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-prometheus-metrics) in the COSMOS Enterprise Plugins.

### Protocol Buffer (Enterprise)

The ProtoAccessor is used to read and write protocol buffers. It is primarily used in conjunction with the [GrpcInterface](interfaces#grpc-interface-enterprise). The ProtoAccessor is currently only implemented in Ruby.

| Parameter | Description                                        | Required |
| --------- | -------------------------------------------------- | -------- |
| Filename  | File generated by the protocol buffer compiler     | Yes      |
| Class     | Class to use when encoding and decoding the buffer | Yes      |

For a full example, please see the [openc3-cosmos-proto-target](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-proto-target) in the COSMOS Enterprise Plugins.
