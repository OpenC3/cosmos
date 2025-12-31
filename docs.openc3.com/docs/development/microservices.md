---
title: Microservices
description: Building custom microservices for COSMOS
sidebar_custom_props:
  myEmoji: 🔧
---

Microservices are persistent background processes that run within the COSMOS environment. They can process data, perform periodic tasks, and provide custom functionality to extend COSMOS.

## Creating a Microservice

The easiest way to create a microservice is to use the [generator](/docs/getting-started/generators#microservice-generator) to create the scaffolding for a new COSMOS Microservice. It must operate inside an existing COSMOS plugin. For example:

```bash
openc3-cosmos-myplugin % openc3.sh cli generate microservice
Usage: cli generate microservice <NAME> (--ruby or --python)

openc3-cosmos-myplugin % openc3.sh cli generate microservice background --python
Microservice BACKGROUND successfully generated!
```

This creates a `microservices/BACKGROUND/` directory containing `background.py` with a fully functional microservice template.

## Microservice Structure

A microservice must extend the `Microservice` base class and implement a `run` method. Here's the basic structure:

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
import time
from openc3.microservices.microservice import Microservice
from openc3.utilities.sleeper import Sleeper
from openc3.api import *

class BackgroundMicroservice(Microservice):
    def __init__(self, name):
        super().__init__(name)
        # Parse OPTION keywords from plugin.txt
        for option in self.config['options']:
            match option[0].upper():
                case 'PERIOD':
                    self.period = int(option[1])
                case _:
                    self.logger.error(
                        f"Unknown option passed to microservice {name}: {option}"
                    )
        if not hasattr(self, 'period'):
            self.period = 60  # Default to 60 seconds
        self.sleeper = Sleeper()

    def run(self):
        while True:
            start_time = time.time()
            if self.cancel_thread:
                break

            # Do your microservice work here
            self.logger.info("BackgroundMicroservice ran")

            run_time = time.time() - start_time
            delta = self.period - run_time
            if delta > 0:
                if self.sleeper.sleep(delta):
                    break
            self.count += 1

    def shutdown(self):
        self.sleeper.cancel()
        super().shutdown()

if __name__ == "__main__":
    BackgroundMicroservice.class_run()
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
require 'openc3/microservices/microservice'
require 'openc3/api/api'

module OpenC3
  class BackgroundMicroservice < Microservice
    include Api # Provides access to api methods

    def initialize(name)
      super(name)
      @config['options'].each do |option|
        case option[0].upcase
        when 'PERIOD'
          @period = option[1].to_i
        else
          @logger.error("Unknown option passed to microservice #{@name}: #{option}")
        end
      end
      @period = 60 unless @period # Default to 60 seconds
      @sleeper = Sleeper.new
    end

    def run
      while true
        start_time = Time.now
        break if @cancel_thread

        # Do your microservice work here
        @logger.info("BackgroundMicroservice ran")

        run_time = Time.now - start_time
        delta = @period - run_time
        if delta > 0
          break if @sleeper.sleep(delta)
        end
        @count += 1
      end
    end

    def shutdown
      @sleeper.cancel
      super()
    end
  end
end

OpenC3::BackgroundMicroservice.run if __FILE__ == $0
```

</TabItem>
</Tabs>

## Plugin Configuration

Microservices are declared in the [plugin.txt](/docs/configuration/plugins#microservice) file:

```ruby
MICROSERVICE BACKGROUND background-microservice
  CMD python background.py
  OPTION PERIOD 30
```

### Available Keywords

| Keyword                                                    | Description                                    |
| ---------------------------------------------------------- | ---------------------------------------------- |
| [CMD](/docs/configuration/plugins#cmd-1)                   | Command to execute the microservice            |
| [ENV](/docs/configuration/plugins#env-1)                   | Set environment variables                      |
| [WORK_DIR](/docs/configuration/plugins#work_dir-1)         | Set the working directory                      |
| [PORT](/docs/configuration/plugins#port-1)                 | Expose a port for HTTP access                  |
| [TOPIC](/docs/configuration/plugins#topic)                 | Subscribe to Redis topics                      |
| [TARGET_NAME](/docs/configuration/plugins#target_name)     | Associate a target with the microservice       |
| [OPTION](/docs/configuration/plugins#option-1)             | Pass custom options to the microservice        |
| [SECRET](/docs/configuration/plugins#secret-1)             | Mount secrets (environment variables or files) |
| [ROUTE_PREFIX](/docs/configuration/plugins#route_prefix-1) | Expose the microservice via Traefik            |
| [SHARD](/docs/configuration/plugins#shard-2)               | Assign to a specific operator shard            |
| [CONTAINER](/docs/configuration/plugins#container-1)       | Docker container image (Enterprise)            |
| [STOPPED](/docs/configuration/plugins#stopped)             | Start in disabled state                        |

## Available APIs

:::warning API vs Script
When writing code for a microservice (or interface) that runs _within_ COSMOS, you must use the `openc3/api` library, **NOT** `openc3/script`.

- `openc3/api` - For code running inside the COSMOS cluster (microservices, interfaces)
- `openc3/script` - For external scripts connecting to COSMOS from outside the cluster

Since microservices run inside the COSMOS cluster, they can make direct connections to the database and do not need external authentication.

For more information see [API vs Script](/docs/guides/script-writing#api-vs-script).
:::

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
from openc3.api import *
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
require 'openc3/api/api'
# Then include in your class:
include Api
```

</TabItem>
</Tabs>

The API module provides access to the [Scripting API](/docs/guides/scripting-api) methods for commanding and telemetry:

| API Category | Key Methods                                                    |
| ------------ | -------------------------------------------------------------- |
| Commands     | `cmd`, `cmd_no_hazardous_check`, `cmd_raw`, `build_cmd`        |
| Telemetry    | `tlm`, `tlm_raw`, `tlm_formatted`, `tlm_with_units`, `set_tlm` |
| Limits       | `get_limits`, `set_limits`, `enable_limits`, `disable_limits`  |
| Targets      | `get_target_names`, `get_all_cmds`, `get_all_tlm`              |
| Interfaces   | `get_interface`, `connect_interface`, `disconnect_interface`   |
| Settings     | `get_setting`, `set_setting`, `get_all_settings`               |

## Base Class Attributes

The `Microservice` base class provides these attributes:

| Attribute       | Description                                                                            |
| --------------- | -------------------------------------------------------------------------------------- |
| `name`          | Full microservice name (format: `SCOPE__TYPE__NAME`)                                   |
| `scope`         | Scope extracted from the name                                                          |
| `state`         | Current state: `INITIALIZED`, `RUNNING`, `FINISHED`, `DIED_ERROR`, `STOPPED`, `KILLED` |
| `count`         | Operation counter (increment in your run loop)                                         |
| `error`         | Last error encountered                                                                 |
| `custom`        | Custom status data (displayed in Admin Microservices tab)                              |
| `logger`        | Logger instance for output                                                             |
| `config`        | Configuration from plugin.txt (topics, target_names, options, secrets)                 |
| `secrets`       | Secrets client for accessing sensitive data                                            |
| `cancel_thread` | Boolean flag to check for shutdown requests                                            |
| `topics`        | List of Redis topics to monitor                                                        |
| `target_names`  | Associated target names                                                                |

## Logging

Use the built-in logger for output. Log messages appear in container logs and the Admin Log Messages panel:

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
self.logger.debug("Debug message")
self.logger.info("Info message")
self.logger.warn("Warning message")
self.logger.error("Error message")
self.logger.fatal("Fatal message")
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
@logger.debug("Debug message")
@logger.info("Info message")
@logger.warn("Warning message")
@logger.error("Error message")
@logger.fatal("Fatal message")
```

</TabItem>
</Tabs>

## State Management

Update `state` to communicate status to users viewing the Admin Microservices tab.

:::note Polling Interval
The microservice status is polled by the frontend every few seconds. Only long-running states will be visible to users. Rapid state changes may not be displayed.
:::

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
self.state = 'CALCULATING'
# ... perform calculation
self.state = 'RUNNING'
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
@state = 'CALCULATING'
# ... perform calculation
@state = 'RUNNING'
```

</TabItem>
</Tabs>

## Custom Status

Set `custom` to display additional information in the Admin Microservices tab. Like state, custom status is polled by the frontend so only persistent values will be visible.

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
self.custom = {"processed": 100, "errors": 2}
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
@custom = {"processed" => 100, "errors" => 2}
```

</TabItem>
</Tabs>

## Secrets

Access secrets defined in plugin.txt with the [SECRET](/docs/configuration/plugins#secret-1) keyword:

```ruby
SECRET ENV MY_API_KEY API_KEY_ENV
SECRET FILE MY_CERT /path/to/cert.pem
```

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
# Environment secrets are automatically available
import os
api_key = os.environ.get('API_KEY_ENV')

# Or use the secrets client
value = self.secrets.get('MY_API_KEY', scope=self.scope)
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
# Environment secrets are automatically available
api_key = ENV['API_KEY_ENV']

# Or use the secrets client
value = @secrets.get('MY_API_KEY', scope: @scope)
```

</TabItem>
</Tabs>

## HTTP Endpoints

To expose your microservice via HTTP, use the [PORT](/docs/configuration/plugins#port-1) and [ROUTE_PREFIX](/docs/configuration/plugins#route_prefix-1) keywords. See [Exposing Microservices](/docs/guides/exposing-microservices) for details.

```ruby
MICROSERVICE MYAPI my-api-service
  CMD python api_server.py
  PORT 8080
  ROUTE_PREFIX /myapi
```

This makes the microservice accessible at `http://localhost:2900/myapi`.

## Metrics

Track performance metrics using the built-in metric system:

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
self.metric.set(name='requests_total', value=self.count, type='counter')
self.metric.set(name='processing_seconds', value=elapsed, type='gauge', unit='seconds')
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
@metric.set(name: 'requests_total', value: @count, type: 'counter')
@metric.set(name: 'processing_seconds', value: elapsed, type: 'gauge', unit: 'seconds')
```

</TabItem>
</Tabs>

## Subscribing to Topics

Microservices can subscribe to Redis topics to receive telemetry or command streams. Use the `TOPIC` keyword in plugin.txt:

```ruby
MICROSERVICE MONITOR telemetry-monitor
  CMD python monitor.py
  TOPIC DEFAULT__DECOM__{INST}__HEALTH_STATUS
```

Then process messages in your run loop:

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
from openc3.topics.topic import Topic

def run(self):
    while True:
        if self.cancel_thread:
            break
        for topic, msg_id, msg_hash, redis in Topic.read_topics(self.topics):
            # Process the message
            self.logger.info(f"Received message on {topic}")
            self.count += 1
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
def run
  while true
    break if @cancel_thread
    Topic.read_topics(@topics) do |topic, msg_id, msg_hash, redis|
      # Process the message
      @logger.info("Received message on #{topic}")
      @count += 1
    end
  end
end
```

</TabItem>
</Tabs>

## Lifecycle Methods

| Method                    | Description                                       |
| ------------------------- | ------------------------------------------------- |
| `__init__` / `initialize` | Constructor - parse options, initialize state     |
| `run`                     | Main execution loop - **must be implemented**     |
| `shutdown`                | Cleanup when stopping - call `super()` at the end |

## Example: Safety Monitor

This example monitors telemetry and takes action when values exceed thresholds:

<Tabs groupId="script-language">
<TabItem value="python" label="Python">

```python
import time
from openc3.microservices.microservice import Microservice
from openc3.utilities.sleeper import Sleeper
from openc3.api import *

class SafetyMonitor(Microservice):
    def __init__(self, name):
        super().__init__(name)
        self.threshold = 100.0
        for option in self.config['options']:
            if option[0].upper() == 'THRESHOLD':
                self.threshold = float(option[1])
        self.sleeper = Sleeper()

    def run(self):
        while True:
            if self.cancel_thread:
                break

            # Check telemetry value
            temp = tlm("INST", "HEALTH_STATUS", "TEMP1")

            if temp > self.threshold:
                self.logger.warn(f"Temperature {temp} exceeds threshold {self.threshold}")
                self.state = 'WARNING'
                # Take corrective action
                cmd("INST", "SAFE_MODE")
            else:
                self.state = 'RUNNING'

            self.count += 1
            if self.sleeper.sleep(1):
                break

    def shutdown(self):
        self.sleeper.cancel()
        super().shutdown()

if __name__ == "__main__":
    SafetyMonitor.class_run()
```

</TabItem>
<TabItem value="ruby" label="Ruby">

```ruby
require 'openc3/microservices/microservice'
require 'openc3/api/api'

module OpenC3
  class SafetyMonitor < Microservice
    include Api

    def initialize(name)
      super(name)
      @threshold = 100.0
      @config['options'].each do |option|
        if option[0].upcase == 'THRESHOLD'
          @threshold = option[1].to_f
        end
      end
      @sleeper = Sleeper.new
    end

    def run
      while true
        break if @cancel_thread

        # Check telemetry value
        temp = tlm("INST", "HEALTH_STATUS", "TEMP1")

        if temp > @threshold
          @logger.warn("Temperature #{temp} exceeds threshold #{@threshold}")
          @state = 'WARNING'
          # Take corrective action
          cmd("INST", "SAFE_MODE")
        else
          @state = 'RUNNING'
        end

        @count += 1
        break if @sleeper.sleep(1)
      end
    end

    def shutdown
      @sleeper.cancel
      super()
    end
  end
end

OpenC3::SafetyMonitor.run if __FILE__ == $0
```

</TabItem>
</Tabs>

Configure in plugin.txt:

```ruby
MICROSERVICE SAFETY safety-monitor
  CMD python safety_monitor.py
  OPTION THRESHOLD 90.0
```
