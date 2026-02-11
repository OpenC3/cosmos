# COSMOS Throughput Testing Server

A standalone Python TCP/IP server for measuring COSMOS command and telemetry throughput.

## Overview

This server provides a lightweight test environment for measuring COSMOS throughput performance. It implements:

- Dual-port TCP server (7778 for INST, 7780 for INST2)
- CCSDS command packet parsing
- CCSDS telemetry packet generation
- LengthProtocol framing (compatible with COSMOS interfaces)
- Configurable telemetry streaming rates
- Real-time throughput metrics

## Architecture

```
COSMOS Container                      Throughput Server (Python)
+-------------------+                 +-------------------+
| INST (Ruby)       |----TCP/7778---->| Port 7778         |
|   TcpipClient     |                 |   CCSDS Commands  |
|   LengthProtocol  |<---TCP/7778----.|   CCSDS Telemetry |
+-------------------+                 +-------------------+
| INST2 (Python)    |----TCP/7780---->| Port 7780         |
|   TcpipClient     |                 |   CCSDS Commands  |
|   LengthProtocol  |<---TCP/7780----.|   CCSDS Telemetry |
+-------------------+                 +-------------------+
```

## Requirements

- Python 3.10 or higher
- No external dependencies (uses only standard library)

## Usage

### Starting the Server

```bash
# Default ports (7778 for INST, 7780 for INST2)
python throughput_server.py

# Custom ports
python throughput_server.py --inst-port 8778 --inst2-port 8780

# Debug logging
python throughput_server.py --debug
```

### Command Line Options

| Option | Default | Description |
|--------|---------|-------------|
| `--inst-port` | 7778 | Port for INST (Ruby) target |
| `--inst2-port` | 7780 | Port for INST2 (Python) target |
| `--debug` | False | Enable debug logging |

## Supported Commands

The server responds to the following CCSDS commands:

| Command | PKTID | Description |
|---------|-------|-------------|
| START_STREAM | 200 | Start telemetry streaming at specified rate |
| STOP_STREAM | 201 | Stop telemetry streaming |
| GET_STATS | 202 | Request THROUGHPUT_STATUS telemetry packet |
| RESET_STATS | 203 | Reset all throughput statistics |

### START_STREAM Payload

| Field | Type | Description |
|-------|------|-------------|
| RATE | 32-bit UINT | Packets per second (1-100000) |
| PACKET_TYPES | 32-bit UINT | Bitmask of packet types (default: 0x01) |

## Telemetry Packets

### THROUGHPUT_STATUS (APID 100)

| Field | Type | Description |
|-------|------|-------------|
| CMD_RECV_COUNT | 32-bit UINT | Total commands received |
| CMD_RECV_RATE | 32-bit FLOAT | Commands per second |
| TLM_SENT_COUNT | 32-bit UINT | Total telemetry packets sent |
| TLM_SENT_RATE | 32-bit FLOAT | Telemetry packets per second |
| TLM_TARGET_RATE | 32-bit UINT | Configured streaming rate |
| BYTES_RECV | 64-bit UINT | Total bytes received |
| BYTES_SENT | 64-bit UINT | Total bytes sent |
| UPTIME_SEC | 32-bit UINT | Server uptime in seconds |

## CCSDS Packet Format

### Command Header (8 bytes)

```
Bits 0-2:   CCSDSVER (3 bits) = 0
Bit 3:      CCSDSTYPE (1 bit) = 1 (command)
Bit 4:      CCSDSSHF (1 bit) = 0
Bits 5-15:  CCSDSAPID (11 bits)
Bits 16-17: CCSDSSEQFLAGS (2 bits) = 3
Bits 18-31: CCSDSSEQCNT (14 bits)
Bits 32-47: CCSDSLENGTH (16 bits) = packet_length - 7
Bits 48-63: PKTID (16 bits)
```

### Telemetry Header (14 bytes)

```
Bits 0-2:   CCSDSVER (3 bits) = 0
Bit 3:      CCSDSTYPE (1 bit) = 0 (telemetry)
Bit 4:      CCSDSSHF (1 bit) = 1
Bits 5-15:  CCSDSAPID (11 bits)
Bits 16-17: CCSDSSEQFLAGS (2 bits) = 3
Bits 18-31: CCSDSSEQCNT (14 bits)
Bits 32-47: CCSDSLENGTH (16 bits)
Bits 48-79: TIMESEC (32 bits)
Bits 80-111: TIMEUS (32 bits)
Bits 112-127: PKTID (16 bits)
```

## COSMOS Integration

### Installing the Modified DEMO Plugin

To use the throughput server with COSMOS, install the modified DEMO plugin with throughput server enabled:

```bash
./openc3.sh cli load openc3-cosmos-demo-*.gem \
  use_throughput_server=true \
  throughput_server_host=host.docker.internal
```

### Plugin Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `use_throughput_server` | false | Enable throughput server mode |
| `throughput_server_host` | host.docker.internal | Hostname of throughput server |
| `inst_throughput_port` | 7778 | Port for INST connection |
| `inst2_throughput_port` | 7780 | Port for INST2 connection |

### Running Throughput Tests

1. Start the throughput server:
   ```bash
   python throughput_server.py
   ```

2. Install the DEMO plugin with throughput mode enabled

3. Run the Ruby throughput test:
   - Open Script Runner in COSMOS
   - Load `INST/procedures/throughput_test.rb`
   - Execute and observe results

4. Run the Python throughput test:
   - Open Script Runner in COSMOS
   - Load `INST2/procedures/throughput_test.py`
   - Execute and observe results

5. Monitor via the THROUGHPUT screen in Telemetry Viewer

## File Structure

```
examples/throughput_server/
├── throughput_server.py    # Main entry point
├── ccsds.py                # CCSDS packet encoding/decoding
├── metrics.py              # Throughput statistics
├── config.py               # Configuration constants
├── requirements.txt        # Dependencies (none required)
└── README.md               # This file
```
