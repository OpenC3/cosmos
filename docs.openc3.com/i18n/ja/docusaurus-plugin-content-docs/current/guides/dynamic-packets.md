---
title: Dynamic Packets
description: How COSMOS dynamically builds packets
sidebar_custom_props:
  myEmoji: 🧱
---

COSMOS has the ability to dynamically build packets rather than have them statically defined by our [COMMAND](/docs/configuration/command) and [TELEMETRY](/docs/configuration/telemetry) configuration files. This is useful when your telemetry items are dynamic like when generating [prometheus](https://prometheus.io/) metrics.

The best way to illustrate this capability is with an example. If you're an Enterprise customer, please see the [prometheus-metrics](https://github.com/OpenC3/cosmos-enterprise-plugins/tree/main/openc3-cosmos-prometheus-metrics) plugin.

## Using Dynamic Update

To use the dynamic update capability in your own code you need to call the `TargetModel` `dynamic_update` method. This method takes an array / list of packets, whether the packets are commands or telemetry, and the filename to create in the config bucket.

Here is the method signature:

```ruby
def dynamic_update(packets, cmd_or_tlm = :TELEMETRY, filename = "dynamic_tlm.txt")
```

```python
def dynamic_update(self, packets, cmd_or_tlm="TELEMETRY", filename="dynamic_tlm.txt")
```

Here is an example of using this method:

```ruby
# Create a new packet
packet = Packet.new('INST', 'NEW_PACKET')
# or get an existing packet
packet = System.telemetry.packet('INST', 'METRICS')
# Modify the packet by appending new items to it
packet.append_item('NEW_ITEM', 32, :FLOAT)
# Grab the TargetModel associated with the packet's target
target_model = TargetModel.get_model(name: 'INST', scope: 'DEFAULT')
# Update the target model with the new packet
target_model.dynamic_update([packet])
```

```python
# Create a new packet
packet = Packet('INST', 'NEW_PACKET')
# or get an existing packet
packet = System.telemetry.packet('INST', 'METRICS')
# Modify the packet by appending new items to it
packet.append_item('NEW_ITEM', 32, 'FLOAT')
# Grab the TargetModel associated with the packet's target
target_model = TargetModel.get_model(name='INST', scope='DEFAULT')
# Update the target model with the new packet
target_model.dynamic_update([packet])
```

When this method is called several things happen:

1. The COSMOS Redis database is updated with the new packets and the current value table is initialized
2. A configuration file for the packets is created and stored at &lt;SCOPE&gt;/targets_modified/&lt;TARGET&gt;/cmd_tlm/dynamic_tlm.txt. Note that if you call `dynamic_update` multiple times you should update the filename so it is not written over.
3. The COSMOS microservices are informed of the new streaming topics which will contain the raw and decommuted packet data. Part of this action is to restart the microservices so they pickup these changes. For COMMANDS the following are restarted: &lt;SCOPE&gt;\_\_COMMANDLOG\_\_&lt;TARGET&gt; and &lt;SCOPE&gt;\_\_DECOMCMDLOG\_\_&lt;TARGET&gt;. For TELEMETRY the following are restarted: &lt;SCOPE&gt;\_\_PACKET_LOG\_\_&lt;TARGET&gt;, &lt;SCOPE&gt;\_\_DECOMLOG\_\_&lt;TARGET&gt;, and &lt;SCOPE&gt;\_\_DECOM\_\_&lt;TARGET&gt;.

Since `dynamic_update` restarts the LOG microservices there is a potential for a loss of packets during the restart. Thus you should not call `dynamic_update` during critical telemetry processing periods.
