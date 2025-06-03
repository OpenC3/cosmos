---
sidebar_position: 10
title: Processors
description: Processors execute code every time a packet is received to calculate values
sidebar_custom_props:
  myEmoji: 🧮
---

<!-- Be sure to edit _processors.md because processors.md is a generated file -->

# Overview

Processors execute code every time a packet is received to calculate values that can be retrieved by a [ProcessorConversion](/docs/configuration/conversions#processor_conversion). Processors are applied using the [PROCESSOR](/docs/configuration/telemetry#processor) keyword and generate values unique to the processor.

If you only want to perform a single calculation to modify a single telemetry value you probably want to use a [Conversion](/docs/configuration/conversions). Processors are used when you're deriving a number of values from a single telemetry item.

## Custom Processors

You can easily create your own custom processors by using the [Processor Code Generator](/docs/getting-started/generators#processor-generator). To generate a process you must be inside an existing COSMOS plugin. The generator takes both a target name and the processor name. For example if your plugin is called `openc3-cosmos-gse` and you have an existing target named `GSE`:

```bash
openc3-cosmos-gse % openc3.sh cli generate processor GSE slope --python
Processor targets/GSE/lib/slope_processor.py successfully generated!
To use the processor add the following to a telemetry packet:
  PROCESSOR SLOPE slope_processor.py
```

To create a Ruby processor simply replace `--python` with `--ruby`. This creates a processor called `slope_processor.py` at `targets/GSE/lib/slope_processor.py`. The code which is generated looks like the following:

```python
import math
from openc3.processors.processor import Processor

# Custom processor class
# See https://docs.openc3.com/docs/configuration/processors
class SlopeProcessor(Processor):
    def __init__(self, item_name, num_samples, value_type='CONVERTED'):
        super().__init__(value_type)
        self.item_name = item_name.upper()
        self.num_samples = int(num_samples)
        self.reset()

    def call(self, value, packet, buffer):
        value = packet.read(self.item_name, self.value_type, buffer)
        # Don't process NaN or Infinite values
        if math.isnan(value) or math.isinf(value):
            return

        self.samples.append(value)
        if len(self.samples) > self.num_samples:
            self.samples = self.samples[-self.num_samples :]

        if len(self.samples) > 1:
            self.results['RATE_OF_CHANGE'] = (self.samples[-1] - self.samples[0]) / (len(self.samples) - 1)
        else:
            self.results['RATE_OF_CHANGE'] = None

    def reset(self):
        self.samples = []
        self.results['RATE_OF_CHANGE'] = None
```

### **init**

The **init** method is where the processor is initialized. The parameters specified are the parameters given in the configuration file when creating the processor. So for our example, the telemetry configuration file will look like:

```
# Calculate the slope of TEMP1 over the last 60 samples (1 minute)
PROCESSOR SLOPE slope_processor.py TEMP1 60
```

### call

The call method is where the actual processor logic is implemented. In our case we want to calculate the rate of change from the first sample to the last sample. There are certainly more efficient ways to calculate a single rate of change value (you really only need 2 values) but this example shows how to keep a running list of values. Also note that if you're only performing a single calculation you might be better off using a [Conversion](/docs/configuration/conversions).

### reset

The reset method initializes the samples and clears any state by setting the results to `None`.

### Instantiate Processor

Now that we have implemented the processor logic we need to create the processor by adding it to a telemetry packet with the line `PROCESSOR slope_conversion.rb` in the [telemetry](/docs/configuration/telemetry) definition file. We also need a [ProcessorConversion](/docs/configuration/conversions#processor_conversion) to pull the calculated values out of the processor and into a [derived](/docs/configuration/telemetry#derived-items) telemetry item. This could look something like this:

```bash
TELEMETRY GSE DATA BIG_ENDIAN "Data packet"
  ... # Telemetry items
  ITEM TEMP1SLOPE 0 0 DERIVED "Rate of change for the last 60 samples of TEMP1"
    READ_CONVERSION processor_conversion.rb SLOPE RATE_OF_CHANGE
  # Calculate the slope of TEMP1 over the last 60 samples (1 minute)
  PROCESSOR SLOPE slope_processor.py TEMP1 60
```

If you have multiple values you're calculating you simply add additional ITEMs with READ_COVERSIONs and read the various values the processor calculates in the results.

# Built-in Processors

COSMOS_META
