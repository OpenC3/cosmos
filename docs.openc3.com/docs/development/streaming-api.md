---
title: Streaming API
description: Using the websocket streaming API to retrieve data
sidebar_custom_props:
  myEmoji: 📝
---

:::note This documentation is for COSMOS Developers
This information is just generally used behind the scenes in COSMOS tools
:::

The COSMOS 5 Streaming Api is the primary interface to receive a stream of the telemetry packets and/or command packets that have passed through the COSMOS system, both logged and continuously in realtime. Either raw binary packets or decommutated JSON packets can be requested.

This API is implemented over Websockets using the Rails ActionCable framework. Actioncable client libraries are known to exist for at least Javascript, Ruby, and Python. Other languages may exist or could be created. Websockets allow for easy interaction with the new COSMOS 5 Javascript based frontend.

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
  }
);
```

Subscribing to the StreamingApi requires passing a channel name set to “StreamingChannel”, a scope which is typically “DEFAULT”, and an access token (a password in OpenSource COSMOS). In Javascript you also pass a set of callback functions that run at various lifecycle points in the subscription. The most important of these are `connected` and `received`.

`connected` runs when the subscription is accepted by the StreamApi. This callback is the first opportunity to request specific data that you would like streamed. Data can also be added or removed at any time while the subscription is open.

Data can be added to the stream by requesting individual items from a packet or by requesting the entire packet.

Adding items to stream is done as follows:

```javascript
var items = [
  ["DECOM__TLM__INST__ADCS__Q1__RAW", "0"],
  ["DECOM__CMD__INST__COLLECT__DURATION__WITH_UNITS", "1"],
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

The values in the item name are separated by double underscores, e.g. `<MODE>__<CMD or TLM>__<TARGET NAME>__<PACKET NAME>__<ITEM NAME>__<VALUE TYPE>__<REDUCED TYPE>`. Mode is either RAW, DECOM, REDUCED_MINUTE, REDUCED_HOUR, or REDUCED_DAY. The next parameter is CMD or TLM followed by the target, packet and item names. The Value Type is one of RAW, CONVERTED, FORMATTED, or WITH_UNITS. The last parameter is optional if you want to use the reduced data types. Reduced Type is one of SAMPLE, MIN, MAX, AVG, or STDDEV.

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

The values in the packet name are separated by double underscores, e.g. `<MODE>__<CMD or TLM>__<TARGET NAME>__<PACKET NAME>__<VALUE TYPE>`. Mode is either RAW or DECOM. The next parameter is CMD or TLM followed by the target and packet names. The Value Type is one of RAW, CONVERTED, FORMATTED, or WITH_UNITS.

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
