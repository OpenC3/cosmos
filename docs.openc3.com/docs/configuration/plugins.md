---
sidebar_position: 2
title: Plugins
description: Plugin definition file format and keywords
sidebar_custom_props:
  myEmoji: 🔌
---

<!-- Be sure to edit _plugins.md because plugins.md is a generated file -->

## Introduction

This document provides the information necessary to configure a COSMOS plugin. Plugins are how you configure and extend COSMOS.

Plugins are where you define targets (and their corresponding command and telemetry packet definitions), where you configure the interfaces needed to talk to targets, where you can define routers to stream raw data out of COSMOS, how you can add new tools to the COSMOS user interface, and how you can run additional microservices to provide new functionality.

Each plugin is built as a Ruby gem and thus has a plugin.gemspec file which builds it. Plugins have a plugin.txt file which declares all the variables used by the plugin and how to interface to the target(s) it contains.

## Concepts

### Target

Targets are the external pieces of hardware and/or software that COSMOS communicates with. These are things like Front End Processors (FEPs), ground support equipment (GSE), custom software tools, and pieces of hardware like satellites themselves. A target is anything that COSMOS can send commands to and receive telemetry from.

### Interface

Interfaces implement the physical connection to one or more targets. They are typically ethernet connections implemented using TCP or UDP but can be other connections like serial ports. Interfaces send commands to targets and receive telemetry from targets.

### Router

Routers flow streams of telemetry packets out of COSMOS and receive streams of commands into COSMOS. The commands are forwarded by COSMOS to associated interfaces. Telemetry comes from associated interfaces.

### Tool

COSMOS Tools are web-based applications the communicate with the COSMOS APIs to perform takes like displaying telemetry, sending commands, and running scripts.

### Microservice

Microservices are persistent running backend code that runs within the COSMOS environment. They can process data and perform other useful tasks.

## Plugin Directory Structure

COSMOS plugins have a well-defined directory structure described in detail in the [Code Generator](/docs/getting-started/generators) documentation.

## plugin.txt Configuration File

A plugin.txt configuration file is required for any COSMOS plugin. It declares the contents of the plugin and provides variables that allow the plugin to be configured at the time it is initially installed or upgraded.
This file follows the standard COSMOS configuration file format of keywords followed by zero or more space separated parameters. The following keywords are supported by the plugin.txt config file:


## VARIABLE
**Define a configurable variable for the plugin**

The VARIABLE keyword defines a variable that will be requested for the user to enter during plugin installation.   Variables can be used to handle details of targets that are user defined such as specific IP addresses and ports.  Variables should also be used to allow users to rename targets to whatever name they want and support multiple installations of the same target with different names. Variables can be used later in plugin.txt or in any other configuration file included in a plugin using Ruby ERB syntax.  The variables are assigned to accessible local variables in the file. At a high level, ERB allows you to run Ruby code in configuration files.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Variable Name | The name of the variable | True |
| Default Value | Default value of the variable | True |

## NEEDS_DEPENDENCIES
<div class="right">(Since 5.5.0)</div>**Indicates the plugin needs dependencies and sets the GEM_HOME environment variable**

If the plugin has a top level lib folder or lists runtime dependencies in the gemspec, NEEDS_DEPENDENCIES is effectively already set. Note that in Enterprise, having NEEDS_DEPENDENCIES adds the NFS volume mount to the Kubernetes pod.


## INTERFACE
**Defines a connection to a physical target**

Interfaces are what OpenC3 uses to talk to a particular piece of hardware. Interfaces require a Ruby or Python file which implements all the interface methods necessary to talk to the hardware. OpenC3 defines many built in interfaces or you can define your own as long as it implements the interface protocol.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Interface Name | Name of the interface. This name will appear in the Interfaces tab of the Server and is also referenced by other keywords. The OpenC3 convention is to name interfaces after their targets with '_INT' appended to the name, e.g. INST_INT for the INST target. | True |
| Filename | Ruby or Python file to use when instantiating the interface.<br/><br/>Valid Values: <span class="values">tcpip_client_interface, tcpip_server_interface, udp_interface, serial_interface</span> | True |

Additional parameters are required. Please see the [Interfaces](../configuration/interfaces.md) documentation for more details.

## INTERFACE Modifiers
The following keywords must follow a INTERFACE keyword.

### MAP_TARGET
**Maps a target name to an interface**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Target Name | Target name to map to this interface | True |

Ruby Example:
```ruby
INTERFACE DATA_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TARGET DATA
```

Python Example:
```python
INTERFACE DATA_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TARGET DATA
```

### MAP_CMD_TARGET
<div class="right">(Since 5.2.0)</div>**Maps a target name to an interface for commands only**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Target Name | Command target name to map to this interface | True |

Ruby Example:
```ruby
INTERFACE CMD_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST
  MAP_CMD_TARGET DATA # Only DATA commands go on the CMD_INT interface
```

Python Example:
```python
INTERFACE CMD_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 nil BURST
  MAP_CMD_TARGET DATA # Only DATA commands go on the CMD_INT interface
```

### MAP_TLM_TARGET
<div class="right">(Since 5.2.0)</div>**Maps a target name to an interface for telemetry only**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Target Name | Telemetry target name to map to this interface | True |

Ruby Example:
```ruby
INTERFACE TLM_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TLM_TARGET DATA # Only DATA telemetry received on TLM_INT interface
```

Python Example:
```python
INTERFACE TLM_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TLM_TARGET DATA # Only DATA telemetry received on TLM_INT interface
```

### DONT_CONNECT
**Server will not automatically try to connect to the interface at startup**


### DONT_RECONNECT
**Server will not try to reconnect to the interface if the connection is lost**


### RECONNECT_DELAY
**Reconnect delay in seconds**

If DONT_RECONNECT is not present the Server will try to reconnect to an interface if the connection is lost. Reconnect delay sets the interval in seconds between reconnect tries.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Delay | Delay in seconds between reconnect attempts. The default is 15 seconds. | True |

### DISABLE_DISCONNECT
**Disable the Disconnect button on the Interfaces tab in the Server**

Use this keyword to prevent the user from disconnecting from the interface. This is typically used in a 'production' environment where you would not want the user to inadvertently disconnect from a target.


### LOG_RAW
**Deprecated, use LOG_STREAM**


### LOG_STREAM
<div class="right">(Since 5.5.2)</div>**Log all data on the interface exactly as it is sent and received**

LOG_STREAM does not add any OpenC3 headers and thus can not be read by OpenC3 tools. It is primarily useful for low level debugging of an interface. You will have to manually parse these logs yourself using a hex editor or other application.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Cycle Time | Amount of time to wait before cycling the log file. Default is 10 min. If nil refer to Cycle Hour and Cycle Minute. | False |
| Cycle Size | Amount of data to write before cycling the log file. Default is 50MB. | False |
| Cycle Hour | The time at which to cycle the log. Combined with Cycle Minute to cycle the log daily at the specified time. If nil, the log will be cycled hourly at the specified Cycle Minute. Only applies if Cycle Time is nil. | False |
| Cycle Minute | See Cycle Hour. | False |

Example Usage:
```ruby
INTERFACE EXAMPLE example_interface.rb
  # Override the default log time of 600
  LOG_STREAM 60
```

### PROTOCOL
<div class="right">(Since 4.0.0)</div>**Protocols modify the interface by processing the data**

Protocols can be either READ, WRITE, or READ_WRITE. READ protocols act on the data received by the interface while write acts on the data before it is sent out. READ_WRITE applies the protocol to both reading and writing.<br/><br/> For information on creating your own custom protocol please see [Protocols](../configuration/protocols.md)

| Parameter | Description | Required |
|-----------|-------------|----------|
| Type | Whether to apply the protocol on incoming data, outgoing data, or both<br/><br/>Valid Values: <span class="values">READ, WRITE, READ_WRITE</span> | True |
| Protocol Filename or Classname | Ruby or Python filename or class name which implements the protocol | True |
| Protocol specific parameters | Additional parameters used by the protocol | False |

Ruby Example:
```ruby
INTERFACE DATA_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil nil
  MAP_TARGET DATA
  # Rather than defining the LENGTH protocol on the INTERFACE line we define it here
  PROTOCOL READ LengthProtocol 0 16 0 1 BIG_ENDIAN 4 0xBA5EBA11
```

Python Example:
```python
INTERFACE DATA_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TARGET DATA
  PROTOCOL READ openc3/interfaces/protocols/ignore_packet_protocol.py INST IMAGE # Drop all INST IMAGE packets
```

### OPTION
**Set a parameter on an interface**

When an option is set the interface class calls the set_option method. Custom interfaces can override set_option to handle any additional options they want.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | The option to set. OpenC3 defines several options on the core provided interfaces. The SerialInterface defines FLOW_CONTROL which can be NONE (default) or RTSCTS and DATA_BITS which changes the data bits of the serial interface. The TcpipServerInterface and HttpServerInterface define LISTEN_ADDRESS which is the IP address to accept connections on (default 0.0.0.0). | True |
| Parameters | Parameters to pass to the option | False |

Example Usage:
```ruby
INTERFACE SERIAL_INT serial_interface.rb COM1 COM1 115200 NONE 1 10.0 nil
  OPTION FLOW_CONTROL RTSCTS
  OPTION DATA_BITS 8
ROUTER SERIAL_ROUTER tcpip_server_interface.rb 2950 2950 10.0 nil BURST
  ROUTE SERIAL_INT
  OPTION LISTEN_ADDRESS 127.0.0.1
```

### SECRET
<div class="right">(Since 5.3.0)</div>**Define a secret needed by this interface**

Defines a secret for this interface and optionally assigns its value to an option. For more information see [Admin Secrets](/docs/tools/admin#secrets).

| Parameter | Description | Required |
|-----------|-------------|----------|
| Type | ENV or FILE.  ENV will mount the secret into an environment variable. FILE mounts the secret into a file. | True |
| Secret Name | The name of the secret to retrieve from the Admin / Secrets tab. For more information see [Admin Secrets](/docs/tools/admin#secrets). | True |
| Environment Variable or File Path | Environment variable name or file path to store secret. Note that if you use the Option Name to set an option to the secret value, this value doesn't really matter as long as it is unique. | True |
| Option Name | Interface option to pass the secret value. This is the primary way to pass secrets to interfaces. | False |
| Secret Store Name | Name of the secret store for stores with multipart keys | False |

Example Usage:
```ruby
SECRET ENV USERNAME ENV_USERNAME USERNAME
SECRET FILE KEY "/tmp/DATA/cert" KEY
```

### ENV
<div class="right">(Since 5.7.0)</div>**Sets an environment variable in the microservice.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Key | Environment variable name | True |
| Value | Environment variable value | True |

Example Usage:
```ruby
ENV COMPANY OpenC3
```

### WORK_DIR
<div class="right">(Since 5.7.0)</div>**Set the working directory**

Working directory to run the microservice CMD in.  Can be a path relative to the microservice folder in the plugin, or an absolute path in the container the microservice runs in.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Directory | Working directory to run the microservice CMD in. Can be a path relative to the microservice folder in the plugin, or an absolute path in the container the microservice runs in. | True |

Example Usage:
```ruby
WORK_DIR '/openc3/lib/openc3/microservices'
```

### PORT
<div class="right">(Since 5.7.0)</div>**Open port for the microservice**

Kubernetes needs a Service to be applied to open a port so this is required for Kubernetes support

| Parameter | Description | Required |
|-----------|-------------|----------|
| Number | Port number | True |
| Protocol | Port protocol. Default is TCP. | False |

Example Usage:
```ruby
PORT 7272
```

### CMD
<div class="right">(Since 5.7.0)</div>**Command line to execute to run the microservice.**

Command line to execute to run the microservice.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Args | One or more arguments to exec to run the microservice. | True |

Ruby Example:
```ruby
CMD ruby interface_microservice.rb DEFAULT__INTERFACE__INT1
```

Python Example:
```python
CMD python interface_microservice.py DEFAULT__INTERFACE__INT1
```

### CONTAINER
<div class="right">(Since 5.7.0)</div>**Docker Container**

Container to execute and run the microservice in. Only used in COSMOS Enterprise.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Args | Name of the container | False |

### ROUTE_PREFIX
<div class="right">(Since 5.7.0)</div>**Prefix of route**

Prefix of route to the microservice to expose externally with Traefik

| Parameter | Description | Required |
|-----------|-------------|----------|
| Route Prefix | Route prefix. Must be unique across all scopes. Something like /myprefix | True |

Example Usage:
```ruby
ROUTE_PREFIX /interface
```

### SHARD
<div class="right">(Since 6.0.0)</div>**Operator shard to run target microservices on**

Operator Shard. Only used if running multiple operator containers typically in Kubernetes

| Parameter | Description | Required |
|-----------|-------------|----------|
| Shard | Shard number starting from 0 | False |

Example Usage:
```ruby
SHARD 0
```

## ROUTER
**Create router to receive commands and output telemetry packets from one or more interfaces**

Creates an router which receives command packets from their remote clients and sends them to associated interfaces. They receive telemetry packets from their interfaces and send them to their remote clients. This allows routers to be intermediaries between an external client and an actual device.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Name | Name of the router | True |
| Filename | Ruby or Python file to use when instantiating the interface.<br/><br/>Valid Values: <span class="values">tcpip_client_interface, tcpip_server_interface, udp_interface, serial_interface</span> | True |

Additional parameters are required. Please see the [Interfaces](../configuration/interfaces.md) documentation for more details.

## TARGET
**Defines a new target**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Folder Name | The target folder | True |
| Name | The target name. While this is almost always the same as Folder Name it can be different to create multiple targets based on the same target folder. | True |

Example Usage:
```ruby
TARGET INST INST
```

## TARGET Modifiers
The following keywords must follow a TARGET keyword.

### CMD_BUFFER_DEPTH
<div class="right">(Since 5.2.0)</div>**Number of commands to buffer to ensure logged in order**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Buffer Depth | Buffer depth in packets (Default = 5) | True |

### CMD_LOG_CYCLE_TIME
**Command binary logs can be cycled on a time interval.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Maximum time between files in seconds (default = 600) | True |

### CMD_LOG_CYCLE_SIZE
**Command binary logs can be cycled after a certain log file size is reached.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Size | Maximum file size in bytes (default = 50_000_000) | True |

### CMD_LOG_RETAIN_TIME
**How long to keep raw command logs in seconds.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds to keep raw command logs (default = nil = Forever) | True |

### CMD_DECOM_LOG_CYCLE_TIME
**Command decommutation logs can be cycled on a time interval.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Maximum time between files in seconds (default = 600) | True |

### CMD_DECOM_LOG_CYCLE_SIZE
**Command decommutation logs can be cycled after a certain log file size is reached.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Size | Maximum file size in bytes (default = 50_000_000) | True |

### CMD_DECOM_LOG_RETAIN_TIME
**How long to keep decom command logs in seconds.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds to keep decom command logs (default = nil = Forever) | True |

### TLM_BUFFER_DEPTH
<div class="right">(Since 5.2.0)</div>**Number of telemetry packets to buffer to ensure logged in order**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Buffer Depth | Buffer depth in packets (Default = 60) | True |

### TLM_LOG_CYCLE_TIME
**Telemetry binary logs can be cycled on a time interval.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Maximum time between files in seconds (default = 600) | True |

### TLM_LOG_CYCLE_SIZE
**Telemetry binary logs can be cycled after a certain log file size is reached.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Size | Maximum file size in bytes (default = 50_000_000) | True |

### TLM_LOG_RETAIN_TIME
**How long to keep raw telemetry logs in seconds.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds to keep raw telemetry logs (default = nil = Forever) | True |

### TLM_DECOM_LOG_CYCLE_TIME
**Telemetry decommutation logs can be cycled on a time interval.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Maximum time between files in seconds (default = 600) | True |

### TLM_DECOM_LOG_CYCLE_SIZE
**Telemetry decommutation logs can be cycled after a certain log file size is reached.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Size | Maximum file size in bytes (default = 50_000_000) | True |

### TLM_DECOM_LOG_RETAIN_TIME
**How long to keep decom telemetry logs in seconds.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds to keep decom telemetry logs (default = nil = Forever) | True |

### REDUCED_MINUTE_LOG_RETAIN_TIME
**How long to keep reduced minute telemetry logs in seconds.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds to keep reduced minute telemetry logs (default = nil = Forever) | True |

### REDUCED_HOUR_LOG_RETAIN_TIME
**How long to keep reduced hour telemetry logs in seconds.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds to keep reduced hour telemetry logs (default = nil = Forever) | True |

### REDUCED_DAY_LOG_RETAIN_TIME
**How long to keep reduced day telemetry logs in seconds.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds to keep reduced day telemetry logs (default = nil = Forever) | True |

### LOG_RETAIN_TIME
**How long to keep all regular telemetry logs in seconds.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds to keep all regular telemetry logs (default = nil = Forever) | True |

### REDUCED_LOG_RETAIN_TIME
**How long to keep all reduced telemetry logs in seconds.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds to keep all reduced telemetry logs (default = nil = Forever) | True |

### CLEANUP_POLL_TIME
**Period at which to run the cleanup process.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Time | Number of seconds between runs of the cleanup process (default = 600 = 10 minutes) | True |

### REDUCER_DISABLE
**Disables the data reduction microservice for the target**


### REDUCER_MAX_CPU_UTILIZATION
**Maximum amount of CPU utilization to apply to data reduction**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Percentage | 0 to 100 percent (default = 30) | True |

### TARGET_MICROSERVICE
<div class="right">(Since 5.2.0)</div>**Breaks a target microservice out into its own process.**

Can be used to give more resources to processing that is falling behind. If defined multiple times for the same type, will create multiple processes. Each process can be given specific packets to process with the PACKET keyword.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Type | The target microservice type. Must be one of DECOM, COMMANDLOG, DECOMCMDLOG, PACKETLOG, DECOMLOG, REDUCER, or CLEANUP | True |

### PACKET
<div class="right">(Since 5.2.0)</div>**Packet Name to allocate to the current TARGET_MICROSERVICE.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Packet Name | The packet name. Does not apply to REDUCER or CLEANUP target microservice types. | True |

### DISABLE_ERB
<div class="right">(Since 5.12.0)</div>**Disable ERB processing**

Disable ERB processing for the entire target or a set of regular expressions over its filenames

| Parameter | Description | Required |
|-----------|-------------|----------|
| Regex | Regex to match against filenames. If match, then no ERB processing | False |

### SHARD
<div class="right">(Since 6.0.0)</div>**Operator shard to run target microservices on**

Operator Shard. Only used if running multiple operator containers typically in Kubernetes

| Parameter | Description | Required |
|-----------|-------------|----------|
| Shard | Shard number starting from 0 | False |

Example Usage:
```ruby
SHARD 0
```

## MICROSERVICE
**Defines a new microservice**

Defines a microservice that the plugin adds to the OpenC3 system. Microservices are background software processes that perform persistent processing.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Microservice Folder Name | The exact name of the microservice folder in the plugin. ie. microservices/MicroserviceFolderName | True |
| Microservice Name | The specific name of this instance of the microservice in the OpenC3 system | True |

Example Usage:
```ruby
MICROSERVICE EXAMPLE openc3-example
```

## MICROSERVICE Modifiers
The following keywords must follow a MICROSERVICE keyword.

### ENV
**Sets an environment variable in the microservice.**

| Parameter | Description | Required |
|-----------|-------------|----------|
| Key | Environment variable name | True |
| Value | Environment variable value | True |

Example Usage:
```ruby
MICROSERVICE EXAMPLE openc3-example
  ENV COMPANY OpenC3
```

### WORK_DIR
**Set the working directory**

Working directory to run the microservice CMD in.  Can be a path relative to the microservice folder in the plugin, or an absolute path in the container the microservice runs in.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Directory | Working directory to run the microservice CMD in. Can be a path relative to the microservice folder in the plugin, or an absolute path in the container the microservice runs in. | True |

Example Usage:
```ruby
MICROSERVICE EXAMPLE openc3-example
  WORK_DIR .
```

### PORT
<div class="right">(Since 5.0.10)</div>**Open port for the microservice**

Kubernetes needs a Service to be applied to open a port so this is required for Kubernetes support

| Parameter | Description | Required |
|-----------|-------------|----------|
| Number | Port number | True |
| Protocol | Port protocol. Default is TCP. | False |

Example Usage:
```ruby
MICROSERVICE EXAMPLE openc3-example
  PORT 7272
```

### TOPIC
**Associate a Redis topic**

Redis topic to associate with this microservice. Standard OpenC3 microservices such as decom_microservice use this information to know what packet streams to subscribe to. The TOPIC keyword can be used as many times as necessary to associate all needed topics.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Topic Name | Redis Topic to associate with the microservice | True |

Example Usage:
```ruby
MICROSERVICE EXAMPLE openc3-example
  # Manually assigning topics is an advanced topic and requires
  # intimate knowledge of the internal COSMOS data structures.
  TOPIC DEFAULT__openc3_log_messages
  TOPIC DEFAULT__TELEMETRY__EXAMPLE__STATUS
```

### TARGET_NAME
**Associate a OpenC3 target**

OpenC3 target to associate with the microservice. For standard OpenC3 microservices such as decom_microservice this causes the target configuration to get loaded into the container for the microservice.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Target Name | OpenC3 target to associate with the microservice | True |

Example Usage:
```ruby
MICROSERVICE EXAMPLE openc3-example
  TARGET_NAME EXAMPLE
```

### CMD
**Command line to execute to run the microservice.**

Command line to execute to run the microservice.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Args | One or more arguments to exec to run the microservice. | True |

Ruby Example:
```ruby
MICROSERVICE EXAMPLE openc3-example
  CMD ruby example_target.rb
```

Python Example:
```python
MICROSERVICE EXAMPLE openc3-example
  CMD python example_target.py
```

### OPTION
**Pass an option to the microservice**

Generic key/value(s) options to pass to the microservice. These take the form of KEYWORD/PARAMS like a line in a OpenC3 configuration file. Multiple OPTION keywords can be used to pass multiple options to the microservice.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Option Name | Name of the option | True |
| Option Value(s) | One or more values to associate with the option | True |

### CONTAINER
**Docker Container**

Container to execute and run the microservice in. Only used in COSMOS Enterprise.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Args | Name of the container | False |

### SECRET
<div class="right">(Since 5.3.0)</div>**Define a secret needed by this microservice**

Defines a secret for this microservice. For more information see [Admin Secrets](/docs/tools/admin#secrets).

| Parameter | Description | Required |
|-----------|-------------|----------|
| Type | ENV or FILE.  ENV will mount the secret into an environment variable. FILE mounts the secret into a file. | True |
| Secret Name | The name of the secret to retrieve from the Admin / Secrets tab. For more information see [Admin Secrets](/docs/tools/admin#secrets). | True |
| Environment Variable or File Path | Environment variable name or file path to store secret | True |
| Secret Store Name | Name of the secret store for stores with multipart keys | False |

Example Usage:
```ruby
SECRET ENV USERNAME ENV_USERNAME
SECRET FILE KEY "/tmp/DATA/cert"
```

### ROUTE_PREFIX
<div class="right">(Since 5.5.0)</div>**Prefix of route**

Prefix of route to the microservice to expose externally with Traefik

| Parameter | Description | Required |
|-----------|-------------|----------|
| Route Prefix | Route prefix. Must be unique across all scopes. Something like /myprefix | True |

Example Usage:
```ruby
MICROSERVICE CFDP CFDP
  ROUTE_PREFIX /cfdp
```

### DISABLE_ERB
<div class="right">(Since 5.12.0)</div>**Disable ERB processing**

Disable ERB processing for the entire microservice or a set of regular expressions over its filenames

| Parameter | Description | Required |
|-----------|-------------|----------|
| Regex | Regex to match against filenames. If match, then no ERB processing | False |

### SHARD
<div class="right">(Since 6.0.0)</div>**Operator shard to run target microservices on**

Operator Shard. Only used if running multiple operator containers typically in Kubernetes

| Parameter | Description | Required |
|-----------|-------------|----------|
| Shard | Shard number starting from 0 | False |

Example Usage:
```ruby
SHARD 0
```

### STOPPED
<div class="right">(Since 6.2.0)</div>**Initially creates the microservice in a stopped state (not enabled)**


Example Usage:
```ruby
STOPPED
```

## TOOL
**Define a tool**

Defines a tool that the plugin adds to the OpenC3 system. Tools are web based applications that make use of the Single-SPA javascript library that allows them to by dynamically added to the running system as independent frontend microservices.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Tool Folder Name | The exact name of the tool folder in the plugin. ie. tools/ToolFolderName | True |
| Tool Name | Name of the tool that is displayed in the OpenC3 Navigation menu | True |

Example Usage:
```ruby
TOOL DEMO Demo
```

## TOOL Modifiers
The following keywords must follow a TOOL keyword.

### URL
**Url used to access the tool**

The relative url used to access the tool. Defaults to "/tools/ToolFolderName".

| Parameter | Description | Required |
|-----------|-------------|----------|
| Url | The url. If not given defaults to tools/ToolFolderName. Generally should not be given unless linking to external tools. | True |

### INLINE_URL
**Internal url to load a tool**

The url of the javascript file used to load the tool into single-SPA. Defaults to "main.js".

| Parameter | Description | Required |
|-----------|-------------|----------|
| Url | The inline url. If not given defaults to main.js. Generally should not be given unless using a non-standard filename. | True |

### WINDOW
**How to display the tool when navigated to**

The window mode used to display the tool. INLINE opens the tool internally without refreshing the page using the Single-SPA framework. IFRAME opens external tools in an Iframe within OpenC3. NEW opens the tool in a new TAB.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Window Mode | Tool display mode<br/><br/>Valid Values: <span class="values">INLINE, IFRAME, NEW</span> | True |

### ICON
**Set tool icon**

Icon shown next to the tool name in the OpenC3 navigation menu.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Icon Name | Icon to display next to the tool name. Icons come from Font Awesome, Material Design (https://materialdesignicons.com/), and Astro. | True |

### CATEGORY
**Category for the tool**

Associates the tool with a category which becomes a submenu in the Navigation menu.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Category Name | Category to associate the tool with | True |

### SHOWN
**Show the tool or not**

Whether or not the tool is shown in the Navigation menu. Should generally be true, except for the openc3 base tool.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Shown | Whether or not the tool is shown.  TRUE or FALSE<br/><br/>Valid Values: <span class="values">true, false</span> | True |

### POSITION
<div class="right">(Since 5.0.8)</div>**Position of the tool in the nav bar**

Position of the tool starting at 2 (1 is reserved for Admin Console). Tools without a position are appended to the end as they are installed. All COSMOS Core tools have consecutive integer values for position.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Position | Numerical position | True |

### DISABLE_ERB
<div class="right">(Since 5.12.0)</div>**Disable ERB processing**

Disable ERB processing for the entire tool or a set of regular expressions over its filenames

| Parameter | Description | Required |
|-----------|-------------|----------|
| Regex | Regex to match against filenames. If match, then no ERB processing | False |

### IMPORT_MAP_ITEM
<div class="right">(Since 6.0.0)</div>**Add an item to the import map**

| Parameter | Description | Required |
|-----------|-------------|----------|
| key | Import Map Key | True |
| value | Import Map Value | True |

## WIDGET
**Define a custom widget**

Defines a custom widget that can be used in Telemetry Viewer screens.

| Parameter | Description | Required |
|-----------|-------------|----------|
| Widget Name | The name of the widget will be used to build a path to the widget implementation. For example, `WIDGET HELLOWORLD` will find the as-built file tools/widgets/HelloworldWidget/HelloworldWidget.umd.min.js. See the [Custom Widgets](../guides/custom-widgets.md) guide for more details. | True |
| Label | The label for the widget that will appear in the Data Viewer component drop down | False |

Example Usage:
```ruby
WIDGET HELLOWORLD
```

## WIDGET Modifiers
The following keywords must follow a WIDGET keyword.

### DISABLE_ERB
<div class="right">(Since 5.12.0)</div>**Disable ERB processing**

Disable ERB processing for the entire widget or a set of regular expressions over its filenames

| Parameter | Description | Required |
|-----------|-------------|----------|
| Regex | Regex to match against filenames. If match, then no ERB processing | False |

## SCRIPT_ENGINE
**Define a script engine to add language support to Script Runner**

Defines a script engine to add language support to Script Runner

| Parameter | Description | Required |
|-----------|-------------|----------|
| Extension | Extension that will use this script engine | True |
| Script Engine Filename | Filename that implements the script engine. Should be in top level lib folder in plugin. | True |

Example Usage:
```ruby
SCRIPT_ENGINE .print print_script_engine.py
```

