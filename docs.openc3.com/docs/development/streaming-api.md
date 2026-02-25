---
title: Streaming API
description: Using the websocket streaming API to retrieve data
sidebar_custom_props:
  myEmoji: 📝
---

:::note This documentation is for COSMOS Developers
This information is just generally used behind the scenes in COSMOS tools
:::

The COSMOS Streaming Api is the primary interface to receive a stream of the telemetry packets and/or command packets that have passed through the COSMOS system, both logged and continuously in realtime. Either raw binary packets or decommutated JSON packets can be requested.

This API is implemented over Websockets using the Rails ActionCable framework. Actioncable client libraries are known to exist for at least Javascript, Ruby, and Python. Other languages may exist or could be created. Websockets allow for easy interaction with the new COSMOS Javascript based frontend.

The following interactions are all shown in Javascript, but would be very similar in any language.
Connecting to this API begins by initiating an ActionCable connection.

```
cable = ActionCable.createConsumer('/openc3-api/cable')
```

This call opens the HTTP connection to the given URL and upgrades it to a websocket connection. This connection can then be shared with multiple “subscriptions”.

A subscription describes a set of data that you want the API to stream to you. Creating a subscription looks like this:

```javascript
subscription = cable.subscriptions.create(
  {
    channel: "StreamingChannel",
    scope: "DEFAULT",
    token: token,
  },
  {
    received: (data) => {
      // Handle received data
    },
    connected: () => {
      // First chance to add what you want to stream here
    },
    disconnected: () => {
      // Handle the subscription being disconnected
    },
    rejected: () => {
      // Handle the subscription being rejected
    },
  },
);
```

Subscribing to the StreamingApi requires passing a channel name set to “StreamingChannel”, a scope which is typically “DEFAULT”, and an access token (a password in COSMOS Core). In Javascript you also pass a set of callback functions that run at various lifecycle points in the subscription. The most important of these are `connected` and `received`.

`connected` runs when the subscription is accepted by the StreamApi. This callback is the first opportunity to request specific data that you would like streamed. Data can also be added or removed at any time while the subscription is open.

Data can be added to the stream by requesting individual items from a packet or by requesting the entire packet.

Adding items to stream is done as follows:

```javascript
var items = [
  ["DECOM__TLM__INST__ADCS__Q1__RAW", "0"],
  ["DECOM__CMD__INST__COLLECT__DURATION__FORMATTED", "1"],
];
OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(() => {
  this.subscription.perform("add", {
    scope: window.openc3Scope,
    token: localStorage.openc3Token,
    items: items,
    start_time: this.startDateTime,
    end_time: this.endDateTime,
  });
});
```

The values in the item name are separated by double underscores, e.g. `<MODE>__<CMD or TLM>__<TARGET NAME>__<PACKET NAME>__<ITEM NAME>__<VALUE TYPE>__<REDUCED TYPE>`. Mode is either RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY. The next parameter is CMD or TLM followed by the target, packet and item names. The Value Type is one of RAW, CONVERTED or FORMATTED. The last parameter is optional if you want to use the reduced data types. Reduced Type is one of SAMPLE, MIN, MAX, AVG, or STDDEV.

Adding packets to stream is done as follows:

```javascript
var packets = [
  ["RAW__TLM__INST__ADCS", "0"],
  ["DECOM__TLM__INST__HEALTH_STATUS__FORMATTED", "1"],
];
OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(() => {
  this.subscription.perform("add", {
    scope: window.openc3Scope,
    token: localStorage.openc3Token,
    packets: packets,
    start_time: this.startDateTime,
    end_time: this.endDateTime,
  });
});
```

The values in the packet name are separated by double underscores, e.g. `<MODE>__<CMD or TLM>__<TARGET NAME>__<PACKET NAME>__<VALUE TYPE>`. Mode is either RAW or DECOM. The next parameter is CMD or TLM followed by the target and packet names. The Value Type is one of RAW, CONVERTED or FORMATTED.

For Raw mode, VALUE TYPE should be set to RAW or omitted (e.g. TLM\_\_INST\_\_ADCS\_\_RAW or TLM\_\_INST\_\_ADCS).
start_time and end_time are standard COSMOS 64-bit integer timestamps in nanoseconds since the Unix Epoch (midnight January 1st, 1970). If start_time is null, that indicates to start streaming from the current time in realtime, indefinitely until items are removed, or the subscription is unsubscribed. end_time is ignored if start_time is null. If start_time is given and end_time is null, that indicates to playback from the given starttime and then continue indefinitely in realtime. If both start_time and end_time are given, then that indicates a temporary playback of historical data.

Data returned by the streaming API is handled by the received callback in Javascript. Data is returned as a JSON Array, with a JSON object in the array for each packet returned. Results are batched, and the current implementation will return up to 100 packets in each batch (the array will have 100 entries). 100 packets per batch is not guaranteed, and batches may take on varying sizes based on the size of the data returned, or other factors. An empty array indicates that all data has been sent for a purely historical query and can be used as an end of data indicator.

For decommutated items, each packet is represented as a JSON object with a 'time' field holding the COSMOS nanosecond timestamp of the packet, and then each of the requested item keys with their corresponding value from the packet.

```json
[
  {
    "time": 1234657585858,
    "TLM__INST__ADCS__Q1__RAW": 50.0,
    "TLM__INST__ADCS__Q2__RAW": 100.0
  },
  {
    "time": 1234657585859,
    "TLM__INST__ADCS__Q1__RAW": 60.0,
    "TLM__INST__ADCS__Q2__RAW": 110.0
  }
]
```

For raw packets, each packet is represented as a JSON object with a time field holding the COSMOS nanosecond timestamp of the packet, a packet field holding the topic the packet was read from in the form of SCOPE\_\_TELEMETRY\_\_TARGETNAME\_\_PACKETNAME, and a buffer field holding a BASE64 encoded copy of the packet data.

```json
[
  {
    "time": 1234657585858,
    "packet": "DEFAULT__TELEMETRY__INST__ADCS",
    "buffer": "SkdfjGodkdfjdfoekfsg"
  },
  {
    "time": 1234657585859,
    "packet": "DEFAULT__TELEMETRY__INST__ADCS",
    "buffer": "3i5n49dmnfg9fl32k3"
  }
]
```

## Ruby Example

Below is a simple Ruby example for using the streaming API to retrieve telemetry data:

```ruby
require 'openc3'
require 'openc3/script/web_socket_api'

$openc3_scope = 'DEFAULT'
ENV['OPENC3_API_HOSTNAME'] = '127.0.0.1'
ENV['OPENC3_API_PORT'] = '2900'
ENV['OPENC3_API_PASSWORD'] = 'password'
# The following are needed for Enterprise (change user/pass as necessary)
#ENV['OPENC3_API_USER'] = 'operator'
#ENV['OPENC3_API_PASSWORD'] = 'operator'
#ENV['OPENC3_KEYCLOAK_REALM'] = 'openc3'
#ENV['OPENC3_KEYCLOAK_URL'] = 'http://127.0.0.1:2900/auth'

# Open a file to write CSV data
csv = File.open('telemetry_data.csv', 'w')

# Connect to the streaming API
OpenC3::StreamingWebSocketApi.new() do |api|
  # Add items to stream - request data from yesterday to 1 minute ago
  api.add(items: [
    'DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED',
    'DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED'
  ],
  start_time: (Time.now - 86400).to_nsec_from_epoch,  # 24 hours ago
  end_time: (Time.now - 60).to_nsec_from_epoch)       # 1 minute ago

  # Write CSV header
  csv.puts "Time,TEMP1,TEMP2"

  # Read all data from the stream
  data = api.read

  # Process each data point
  data.each do |item|
    csv.puts "#{item['__time']/1_000_000_000.0},#{item['DECOM__TLM__INST__HEALTH_STATUS__TEMP1__CONVERTED']},#{item['DECOM__TLM__INST__HEALTH_STATUS__TEMP2__CONVERTED']}"
  end
end
csv.close()
```

## StreamingApi Architecture

The Streaming API is a server-side subsystem within the `openc3-cosmos-cmd-tlm-api` Rails microservice that provides real-time and historical telemetry/command data streaming to web clients over WebSockets (ActionCable). It supports streaming individual telemetry items, whole packets, and aggregated (reduced) data from multiple data sources: Valkey (Redis) streams, QuestDB (time-series database), and S3-compatible bucket log files.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Web Client (Browser)                        │
│                    Vue.js Frontend (ActionCable JS)                 │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ WebSocket (AnyCable)
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     StreamingChannel (ActionCable)                  │
│  app/channels/streaming_channel.rb                                 │
│  - subscribed() → creates StreamingApi instance                    │
│  - add(data) → delegates to StreamingApi#add                       │
│  - remove(data) → delegates to StreamingApi#remove                 │
│  - unsubscribed() → calls StreamingApi#kill                        │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        StreamingApi                                 │
│  app/models/streaming_api.rb                                       │
│  - Orchestrates streaming threads                                  │
│  - Manages 0..1 RealtimeStreamingThread                            │
│  - Manages 0..N LoggedStreamingThread instances                    │
│  - Broadcasts results via ActionCable                              │
└───────────┬───────────────────┬─────────────────────────────────────┘
            │                   │
            ▼                   ▼
┌─────────────────────┐ ┌────────────────────────────────────────────┐
│ RealtimeStreaming-   │ │ LoggedStreamingThread                      │
│ Thread               │ │ app/models/logged_streaming_thread.rb      │
│ app/models/realtime_ │ │ - Reads from QuestDB (TSDB mode)           │
│ streaming_thread.rb  │ │ - Reads from Valkey (STREAM mode)          │
│ - Reads from Valkey  │ │ - Reads from S3 files (RAW packets)        │
│   streams in real-   │ │ - Hands off to realtime when caught up     │
│   time               │ │                                            │
└──────────┬──────────┘ └────┬──────────────┬───────────────────────┘
           │                 │              │
           ▼                 ▼              ▼
    ┌──────────┐   ┌──────────────┐  ┌──────────────────────┐
    │  Valkey   │   │   QuestDB    │  │ S3 Bucket Log Files  │
    │  Streams  │   │   (TSDB)     │  │ (via BucketFileCache │
    │           │   │              │  │  + PacketLogReader)  │
    └──────────┘   └──────────────┘  └──────────────────────┘
```

## File Reference

### Primary Files (cmd-tlm-api/app/models/)

| File                              | Class                       | Purpose                                                                                                                                         |
| --------------------------------- | --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| `streaming_api.rb`                | `StreamingApi`              | Top-level orchestrator. Manages thread lifecycle, item collections, and result transmission.                                                    |
| `streaming_thread.rb`             | `StreamingThread`           | Abstract base class for streaming threads. Contains shared logic for Redis reading, message handling, batch transmission, and object lifecycle. |
| `realtime_streaming_thread.rb`    | `RealtimeStreamingThread`   | Subclass of `StreamingThread`. Continuously reads from Valkey streams for live data.                                                            |
| `logged_streaming_thread.rb`      | `LoggedStreamingThread`     | Subclass of `StreamingThread`. Reads historical data from QuestDB and/or Valkey, then hands off to realtime.                                    |
| `streaming_object.rb`             | `StreamingObject`           | Data class representing a single streaming subscription item (one item or one packet).                                                          |
| `streaming_object_collection.rb`  | `StreamingObjectCollection` | Thread-safe collection of `StreamingObject` instances, indexed by topic, id, and type.                                                          |
| `streaming_object_file_reader.rb` | `StreamingObjectFileReader` | Reads raw packet data from S3 bucket log files in time order across multiple files.                                                             |

### Channel Files (cmd-tlm-api/app/channels/)

| File                              | Class                          | Purpose                                                                           |
| --------------------------------- | ------------------------------ | --------------------------------------------------------------------------------- |
| `streaming_channel.rb`            | `StreamingChannel`             | ActionCable channel. Entry point for WebSocket streaming requests.                |
| `application_cable/connection.rb` | `ApplicationCable::Connection` | WebSocket connection authentication. Authorizes via token and assigns UUID/scope. |
| `application_cable/channel.rb`    | `ApplicationCable::Channel`    | Base ActionCable channel class.                                                   |

### Core Library Files (openc3/lib/openc3/)

| File                                 | Class                             | Purpose                                                                                                                  |
| ------------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `topics/topic.rb`                    | `OpenC3::Topic`                   | Delegates to `EphemeralStore` (Valkey). Provides `read_topics`, `get_oldest_message`, `get_last_offset`.                 |
| `utilities/questdb_client.rb`        | `OpenC3::QuestDBClient`           | QuestDB utility: value encoding/decoding, table/column name sanitization, timestamp formatting, sentinel value handling. |
| `utilities/bucket_file_cache.rb`     | `BucketFileCache` / `BucketFile`  | Singleton cache for S3 bucket files. Downloads, caches locally, manages disk usage and file lifecycle.                   |
| `logs/buffered_packet_log_reader.rb` | `OpenC3::BufferedPacketLogReader` | Reads packet log files with buffering to enable time-ordered reading across multiple files.                              |
| `packets/json_packet.rb`             | `OpenC3::JsonPacket`              | Represents a decommutated packet as JSON. Provides `read()` and `read_all()` for extracting item values.                 |
| `utilities/authorization.rb`         | `OpenC3::Authorization`           | Authorization mixin. Provides `authorize()` method for permission checks.                                                |
| `models/target_model.rb`             | `OpenC3::TargetModel`             | Target configuration model. Provides `get_item_to_packet_map()`, `packet()`, `packet_item()`.                            |
| `utilities/bucket_utilities.rb`      | `OpenC3::BucketUtilities`         | S3 bucket utilities. Provides `files_between_time()` for finding log files in time ranges.                               |

### Test File

| File                                | Purpose                                                                             |
| ----------------------------------- | ----------------------------------------------------------------------------------- |
| `spec/models/streaming_api_spec.rb` | RSpec tests covering realtime, logged, file-based, and reduced streaming scenarios. |

---

## Data Structures

### StreamingObject

Represents a single subscription to either a telemetry/command item or a whole packet.

```ruby
class StreamingObject
  attr_reader :key            # Full key string, e.g. "DECOM__TLM__INST__ADCS__Q1__CONVERTED"
  attr_reader :stream_mode    # Symbol: :RAW, :DECOM, :REDUCED_MINUTE, :REDUCED_HOUR, :REDUCED_DAY
  attr_reader :cmd_or_tlm     # Symbol: :CMD or :TLM
  attr_reader :target_name    # String: target name, e.g. "INST"
  attr_reader :packet_name    # String: packet name, e.g. "ADCS"
  attr_reader :item_name      # String or nil: item name (nil for whole packets)
  attr_reader :value_type     # Symbol: :RAW, :CONVERTED, :FORMATTED, :WITH_UNITS, :PURE
  attr_reader :reduced_type   # Symbol or nil: :MIN, :MAX, :AVG, :STDDEV (reduced modes only)
  attr_accessor :start_time   # Integer or nil: nanoseconds from epoch
  attr_accessor :end_time     # Integer or nil: nanoseconds from epoch
  attr_accessor :offset       # String: Valkey stream offset, e.g. "1614890937274-0"
  attr_reader :topic          # String: Valkey topic, e.g. "DEFAULT__DECOM__{INST}__ADCS"
  attr_reader :id             # String: unique id, e.g. "ITEM__DECOM__TLM__INST__ADCS__Q1__CONVERTED"
  attr_reader :realtime       # Boolean: true if end_time is nil or in the future
  attr_reader :item_key       # String or nil: client-provided key for result mapping
end
```

**Key Format (Items):**

```
MODE__CMDORTLM__TARGET__PACKET__ITEM__VALUETYPE[__REDUCEDTYPE]
```

Examples:

- `DECOM__TLM__INST__ADCS__Q1__CONVERTED`
- `REDUCED_MINUTE__TLM__INST__PARAMS__VALUE1__RAW__AVG`

**Key Format (Packets):**

```
MODE__CMDORTLM__TARGET__PACKET__VALUETYPE
```

Examples:

- `RAW__TLM__INST__PARAMS`
- `DECOM__TLM__INST__PARAMS__CONVERTED`

**Topic Format:**

```
SCOPE__TYPE__{TARGET}__PACKET
```

Where TYPE is: `TELEMETRY`, `COMMAND`, `DECOM`, `DECOMCMD`, `REDUCED_MINUTE`, `REDUCED_HOUR`, or `REDUCED_DAY`.

Example: `DEFAULT__DECOM__{INST}__ADCS`

**ID Format:**

- Items: `ITEM__<key>`
- Packets: `PACKET__<key>`

### StreamingObjectCollection

Thread-safe collection that indexes StreamingObjects for efficient lookup.

```ruby
class StreamingObjectCollection
  @objects                  # Array<StreamingObject> - all objects
  @objects_by_id            # Hash{String => StreamingObject} - lookup by object.id
  @topics_and_offsets       # Hash{String => String} - topic => latest offset
  @item_objects_by_topic    # Hash{String => Array<StreamingObject>} - items grouped by topic
  @packet_objects_by_topic  # Hash{String => Array<StreamingObject>} - packets grouped by topic
  @includes_realtime        # Boolean - true if any object has realtime == true
  @mutex                    # Mutex - protects all internal state
end
```

**Offset management:** Both `add()` and `topics_offsets_and_objects()` use max-offset-per-topic logic: when multiple objects share a topic, the highest offset is kept. This ensures `XREAD` starts from the most advanced position, avoiding re-reading messages already processed by all objects on that topic. The `topics_offsets_and_objects()` method rebuilds the offset map from scratch on each call to reflect the latest object offsets.

### Client Request Format (add)

```json
{
  "scope": "DEFAULT",
  "token": "<auth_token>",
  "start_time": 1614890937274290500,
  "end_time": 1614891537276524900,
  "items": [
    ["DECOM__TLM__INST__ADCS__Q1__CONVERTED", "optional_item_key"],
    ["DECOM__TLM__INST__ADCS__Q2__RAW", null]
  ],
  "packets": ["RAW__TLM__INST__PARAMS", "DECOM__TLM__INST__PARAMS__CONVERTED"]
}
```

- `start_time`: 64-bit nanoseconds from Unix epoch. Omit for realtime-only.
- `end_time`: 64-bit nanoseconds from Unix epoch. Omit to stream indefinitely.
- `items`: Array of `[key, item_key]` pairs. `item_key` is used as the key in result JSON (defaults to key string if null).
- `packets`: Array of key strings for whole-packet streaming.

### Result Transmission Format

Results are broadcast as JSON arrays via ActionCable. Each entry is one of:

**Item Result:**

```json
{
  "__type": "ITEMS",
  "__time": 1614890937274290500,
  "COSMOS_EXTRA": "{...}",
  "item_key_1": 42.5,
  "item_key_2": "ENABLED"
}
```

**Packet Result (decom/raw):**

```json
{
  "__type": "PACKET",
  "__packet": "RAW__TLM__INST__PARAMS",
  "__time": 1614890937274290500,
  "buffer": "<base64_encoded>"
}
```

**Stream Complete Marker:**

```json
[]
```

An empty array signals that all streaming threads have completed.

---

## Thread Model

### Thread Hierarchy

```
ActionCable WebSocket Connection (managed by AnyCable/Rails)
  └── StreamingApi instance (1 per WebSocket subscription)
        ├── RealtimeStreamingThread (0 or 1, singleton per StreamingApi)
        │     └── Ruby Thread: runs redis_thread_body() in a loop
        └── LoggedStreamingThread[] (0..N, one per add() call with start_time)
              └── Ruby Thread: runs thread_body() in a loop
                    (cycles through SETUP → TSDB → STREAM modes)
```

### Thread 1: RealtimeStreamingThread

**File:** `realtime_streaming_thread.rb` (extends `streaming_thread.rb`)

**Lifecycle:**

1. Created when `add()` is called with no `start_time`, or when `end_time` is in the future.
2. At most one instance exists per `StreamingApi`. New add requests merge into the existing thread's collection.
3. Runs `redis_thread_body()` in an infinite loop.
4. Stops when all objects are removed or `kill()` is called.

**Behavior:**

- Calls `OpenC3::Topic.read_topics()` (Valkey XREAD) with a 500ms timeout.
- Skips stored packets (`msg_hash["stored"] == true`).
- Processes items and packets from each message.
- Batches results up to `@max_batch_size` (default 100) before transmitting.
- Calls `check_for_completed_objects()` when no data is received (to detect wall-clock end-time expiry).

### Thread 2: LoggedStreamingThread

**File:** `logged_streaming_thread.rb` (extends `streaming_thread.rb`)

**Lifecycle:**

1. Created when `add()` is called with a `start_time`.
2. Multiple instances can exist simultaneously (one per `add()` call with `start_time`).
3. Progresses through three modes: `SETUP` → `TSDB` or `STREAM` → `STREAM`.
4. After catching up, hands off objects to the `RealtimeStreamingThread` (if the objects have no `end_time` or `end_time` is in the future).
5. Stops when all objects expire or handoff completes.

**Mode: SETUP** (`setup_thread_body`)

- Validates that `start_time` is not more than 1 minute in the future.
- Queries Valkey for the oldest message on the first object's topic.
- Decision logic:
  - If `start_time < oldest_time_in_valkey` → switch to **TSDB** mode (data is too old for Valkey).
  - If `start_time >= oldest_time_in_valkey` → switch to **STREAM** mode (data is in Valkey). Calculates a Valkey stream offset by interpolating between Redis time and packet time.
  - If no data in Valkey → switch to **TSDB** mode.

**Mode: TSDB** (`tsdb_thread_body`)

- Separates objects into regular items, reduced items, and packets.
- Regular items: Queries QuestDB with `SELECT` + `ASOF JOIN` across tables, type-aware decoding via `QuestDBClient.decode_value()`.
- Reduced items: Queries QuestDB with `SAMPLE BY` aggregation (min, max, avg, stddev) at minute/hour/day intervals.
- Packets:
  - RAW packets → reads from S3 log files via `StreamingObjectFileReader`.
  - DECOM packets → queries QuestDB with `SELECT *`.
  - REDUCED packets → queries QuestDB with `SAMPLE BY`.
- Uses paginated queries (`LIMIT min, max`) with batch size of 600.
- Retries on `IOError` or `PG::Error` up to 5 times with connection reset.
- Tracks the latest packet timestamp per topic in `@last_tsdb_times` (Hash{topic => nanoseconds}).
- After completion, calls `bridge_tsdb_to_stream()` to calculate Valkey stream offsets, then switches to **STREAM** mode.

**TSDB→STREAM Bridge** (`bridge_tsdb_to_stream`)

The offset interpolation between TSDB packet timestamps and Valkey stream IDs is approximate (Valkey IDs are wall-clock insertion times, while packet times are generation times). To prevent gaps:

1. For each topic with recorded TSDB data, queries `OpenC3::Topic.get_oldest_message(topic)` to get the reference mapping between Valkey stream ID and packet timestamp.
2. Applies the same linear interpolation formula as `setup_thread_body`: `offset = ((last_tsdb_time - TSDB_STREAM_OVERLAP_NSEC + delta) / 1_000_000).to_s + '-0'`.
3. Subtracts a 2-second overlap buffer (`TSDB_STREAM_OVERLAP_NSEC`) to ensure the Valkey read starts before where TSDB left off. The overlap filtering in `redis_thread_body` deduplicates.
4. Sets each object's offset to the calculated value for its topic. Topics without TSDB data retain their existing offsets.

**Mode: STREAM** (`redis_thread_body` overridden from `StreamingThread`)

- On the first iteration after TSDB→STREAM transition, filters overlap per topic: messages with `time <= @last_tsdb_times[topic]` are skipped (offsets still advance). Once a message passes the filter for a topic, that topic's filter is cleared.
- After all per-topic filters are cleared, delegates to the parent `redis_thread_body` (same as RealtimeStreamingThread).
- After each iteration, calls `attempt_handoff_to_realtime()` to transfer objects.

### Thread 3: BucketFileCache Thread

**File:** `openc3/lib/openc3/utilities/bucket_file_cache.rb`

**Lifecycle:** Singleton background thread, created on first access. Lives for the duration of the process.

**Behavior:**

- Dequeues files from `@queued_bucket_files` and downloads them from S3 to local temp directory.
- Manages disk usage up to `MAX_DISK_USAGE` (default 20GB, configurable via `OPENC3_BUCKET_FILE_CACHE_SIZE`).
- Periodically age-checks files (every 3600 seconds) and deletes unreserved files older than 4 hours.

### Thread Synchronization

| Mutex                                | Scope                                     | Protects                                                                                                  |
| ------------------------------------ | ----------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `StreamingApi#@mutex`                | Per StreamingApi instance                 | `@realtime_thread`, `@logged_threads` array, handoff operations                                           |
| `StreamingObjectCollection#@mutex`   | Per collection                            | `@objects`, `@objects_by_id`, `@topics_and_offsets`, `@item_objects_by_topic`, `@packet_objects_by_topic` |
| `LoggedStreamingThread.@@conn_mutex` | Class-level (shared across all instances) | `@@conn` - shared PG::Connection to QuestDB                                                               |
| `BucketFileCache.@@mutex`            | Singleton                                 | `@queued_bucket_files`, `@bucket_file_hash`, `@current_disk_usage`                                        |
| `BucketFile#@mutex`                  | Per file                                  | `@reservation_count`, `@local_path`, file retrieval                                                       |

### Thread Shutdown (`kill`)

1. Calls `stop()` on the realtime thread and all logged threads (sets `@cancel_thread = true`).
2. Waits up to ~1.1 seconds for each thread to exit (polling at 10ms intervals).
3. Clears references: `@realtime_thread = nil`, `@logged_threads = []`.
4. Threads self-cleanup via `ensure` block calling `@streaming_api.complete_thread(self)`.

---

## Data Flow

### Realtime Streaming (no start_time)

```
Client add(data) →
  StreamingApi#add →
    Build StreamingObjectCollection →
    Create/reuse RealtimeStreamingThread →
      Loop:
        OpenC3::Topic.read_topics (Valkey XREAD, 500ms timeout) →
        For each message:
          Skip if stored == true
          handle_message() → handle_json_packet() or handle_raw_packet() →
          Batch results up to max_batch_size →
        transmit_results() →
          ActionCable.server.broadcast(subscription_key, results)
```

### Historical → Realtime Streaming (with start_time, no end_time)

```
Client add(data) →
  StreamingApi#add →
    Build StreamingObjectCollection →
    Create LoggedStreamingThread →
      SETUP: Check Valkey for oldest message →
        If data too old → TSDB mode:
          Query QuestDB (items, packets, reduced) →
          Track @last_tsdb_times per topic →
          Transmit batched results →
          bridge_tsdb_to_stream():
            For each topic with TSDB data:
              Look up oldest Valkey message for that topic →
              Interpolate offset with 2s overlap buffer →
              Set object offsets for that topic →
          Switch to STREAM mode
        If data in Valkey → STREAM mode:
          Calculate start offset →
      STREAM mode:
        redis_thread_body() reads from Valkey →
          If @last_tsdb_times has entries for this topic:
            Skip messages with time <= last_tsdb_time (advance offsets) →
            Clear filter once past overlap →
          Process and transmit batched results →
      attempt_handoff_to_realtime() →
        StreamingApi#handoff_to_realtime() →
          Transfer objects to RealtimeStreamingThread →
          LoggedStreamingThread exits
```

### Historical Only (with start_time and past end_time)

```
Client add(data) →
  StreamingApi#add →
    Build StreamingObjectCollection →
    Create LoggedStreamingThread →
      SETUP → TSDB/STREAM →
        Stream data within time range →
        objects_active?() detects end_time exceeded →
        finish() removes completed objects →
        Thread exits →
        complete_thread() →
          transmit_results([], force: true)  (empty array = stream complete)
```

### LATEST Item Resolution

When an item key contains `LATEST` as the packet name (e.g., `DECOM__TLM__INST__LATEST__TEMP1__CONVERTED`), the `build_item_collection()` method resolves it:

1. Calls `OpenC3::TargetModel.get_item_to_packet_map(target_name)` to find all packets containing that item.
2. Creates one `StreamingObject` per packet, each sharing the same `item_key` for result mapping.
3. The client receives whichever packet updates first (all map to the same output key).

### Handoff: Logged → Realtime

The handoff mechanism in `StreamingThread#handoff()` compares offsets between the logged thread's collection and the realtime thread's collection:

1. For each topic in the logged collection (indexed by `index`):
   - Looks up the topic's position in the realtime collection (`my_index = my_topics.index(topic)`).
   - If the realtime thread has the same topic and the logged offset (`offsets[index]`) >= realtime offset (`my_offsets[my_index]`) → **caught up**, transfer objects.
   - If the realtime thread doesn't have this topic → **new topic**, transfer objects.
   - If the logged offset < realtime offset → **not caught up**, keep in logged thread.
2. Objects are moved from the logged collection to the realtime collection.
3. If all objects are transferred, the logged thread cancels itself.

**Note:** The offset comparison uses `my_index` (the topic's position in the realtime collection) to look up `my_offsets`, not `index` (the logged collection's position). These differ when the two collections have topics in different orders.

---

## Data Sources

### 1. Valkey (Redis) Streams

- **Used by:** `RealtimeStreamingThread`, `LoggedStreamingThread` (STREAM mode)
- **Access:** `OpenC3::Topic.read_topics()` (wraps `EphemeralStore.read_topics` / Valkey XREAD)
- **Topics:** `SCOPE__TYPE__{TARGET}__PACKET` (e.g., `DEFAULT__DECOM__{INST}__ADCS`)
- **Message Fields:**
  - `time` - packet timestamp (nanoseconds)
  - `stored` - boolean, true for non-realtime packets
  - `buffer` - raw binary data (RAW mode)
  - `json_data` - JSON string of decommutated values (DECOM mode)
  - `extra` - optional JSON metadata (COSMOS_EXTRA)

### 2. QuestDB (Time-Series Database)

- **Used by:** `LoggedStreamingThread` (TSDB mode)
- **Access:** `PG::Connection` via PostgreSQL wire protocol
- **Connection:** Shared class-level `@@conn` protected by `@@conn_mutex`
- **Environment Variables:**
  - `OPENC3_TSDB_HOSTNAME` - QuestDB host
  - `OPENC3_TSDB_QUERY_PORT` - PostgreSQL query port
  - `OPENC3_TSDB_USERNAME` / `OPENC3_TSDB_PASSWORD` - credentials
- **Table Names:** `CMDORTLM__TARGET__PACKET` (sanitized), e.g., `TLM__INST__PARAMS`
- **Query Patterns:**
  - Items: `SELECT col1, col2, ... FROM T0 [ASOF JOIN T1 ...] WHERE T0.PACKET_TIMESECONDS >= X LIMIT min, max`
  - Packets: `SELECT * FROM table WHERE PACKET_TIMESECONDS >= X LIMIT min, max`
  - Reduced: `SELECT min(col), max(col), avg(col), stddev(col) FROM table WHERE ... SAMPLE BY 1m|1h|1d ALIGN TO CALENDAR ORDER BY PACKET_TIMESECONDS LIMIT min, max`
- **Type Mapping:** Uses `PG::BasicTypeMapForResults` for automatic type conversion, plus `QuestDBClient.decode_value()` for COSMOS-specific types (arrays, blocks, 64-bit integers, sentinel float values).
- **Retry Logic:** Up to 5 retries on `IOError` or `PG::Error`, with connection reset between retries.

### 3. S3 Bucket Log Files

- **Used by:** `LoggedStreamingThread` → `StreamingObjectFileReader` (RAW packet mode only)
- **Access:** `BucketFileCache` (singleton) → `OpenC3::Bucket` (S3 client)
- **File Format:** Compressed binary log files (`.bin.gz`) in bucket paths like:
  ```
  SCOPE/stream_mode_logs/cmd_or_tlm/TARGET/YYYYMMDD/TIMESTAMP__TIMESTAMP__SCOPE__TARGET__PACKET__rt__mode.bin.gz
  ```
- **Reading:** `BufferedPacketLogReader` with a buffer depth of 10 packets for time-ordered merging across multiple files.
- **File Discovery:** `OpenC3::BucketUtilities.files_between_time()` lists files whose time ranges overlap the requested period.

---

## Configuration

| Environment Variable            | Default              | Purpose                                      |
| ------------------------------- | -------------------- | -------------------------------------------- |
| `OPENC3_LOGS_BUCKET`            | -                    | S3 bucket name for log files                 |
| `OPENC3_TSDB_HOSTNAME`          | -                    | QuestDB hostname                             |
| `OPENC3_TSDB_QUERY_PORT`        | -                    | QuestDB PostgreSQL wire protocol port        |
| `OPENC3_TSDB_USERNAME`          | -                    | QuestDB username                             |
| `OPENC3_TSDB_PASSWORD`          | -                    | QuestDB password                             |
| `OPENC3_BUCKET_FILE_CACHE_SIZE` | `20000000000` (20GB) | Max local disk usage for cached bucket files |

| Constant                               | Value              | Location                  | Purpose                                                                                                         |
| -------------------------------------- | ------------------ | ------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `ALLOWABLE_START_TIME_OFFSET_NSEC`     | 60 seconds (in ns) | `LoggedStreamingThread`   | Max allowed start_time in the future                                                                            |
| `TSDB_STREAM_OVERLAP_NSEC`             | 2 seconds (in ns)  | `LoggedStreamingThread`   | Overlap buffer when bridging from TSDB to Valkey stream. Ensures no gaps from offset interpolation imprecision. |
| `max_batch_size` (realtime)            | 100                | `StreamingThread`         | Max results per ActionCable broadcast (realtime)                                                                |
| `max_batch_size` (logged)              | 600                | `LoggedStreamingThread`   | Max results per ActionCable broadcast (historical)                                                              |
| `BucketFile::MAX_AGE_SECONDS`          | 14400 (4 hours)    | `BucketFileCache`         | Max age for unreserved cached files                                                                             |
| `BucketFileCache::CHECK_TIME_SECONDS`  | 3600 (1 hour)      | `BucketFileCache`         | Interval for age-checking cached files                                                                          |
| `BufferedPacketLogReader buffer_depth` | 10                 | `BufferedPacketLogReader` | Number of packets buffered for time-ordered reading                                                             |

---

## Error Handling

- **Authorization errors** (`OpenC3::AuthError`, `OpenC3::ForbiddenError`): Caught in `StreamingChannel`, transmit `{"error": "unauthorized"}` and reject the subscription.
- **General errors in `StreamingChannel`**: Transmit `{"error": "ClassName:message"}` and reject the subscription.
- **Thread crashes**: Caught by `rescue => e` in `StreamingThread#start`. Logs error and calls `complete_thread(self)` via `ensure` block.
- **QuestDB connection errors** (`IOError`, `PG::Error`): Retry up to 5 times with connection reset. Raise after 5th retry.
- **S3 retrieval errors**: `BucketFile#retrieve` retries up to 3 times with 1-second sleep between attempts.
- **Start time too far in future**: `LoggedStreamingThread` finishes objects and cancels if `start_time` exceeds current time by more than 60 seconds.
