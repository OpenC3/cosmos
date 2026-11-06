---
title: Hardware Discovery
description: Find devices connected to your computers and configure plugins to discover them
sidebar_custom_props:
  myEmoji: 📡
---

Hardware discovery lets COSMOS find the devices that are connected to, or reachable from, the computers paired with it through openc3-cosmos-app. These include serial ports, USB and HID devices, network devices and Bluetooth LE devices. COSMOS uses what it finds in two ways:

- **When installing a plugin**, a variable can list the matching devices in a dropdown, so the user picks the serial port, controller or IP address instead of typing it.
- **With Discover Hardware**, COSMOS scans a computer for devices and proposes plugins that support them, from the OpenC3 Store and from the plugins already installed. Choosing one opens the plugin install dialog with the device already filled in.

Plugin authors make a plugin discoverable with a few `plugin.txt` keywords. They are covered in [Configuring a Plugin for Discovery](#configuring-a-plugin-for-discovery).

:::info[Requires openc3-cosmos-app]
Discovery runs on a computer paired with COSMOS through openc3-cosmos-app, the same computer that runs the plugin's [bridged](bridges.md) interfaces. Without a paired computer, plugins still install normally and their values can be typed in by hand.
:::

## How It Works

```
 Browser                COSMOS                          Host computer
 ───────                ──────                          ─────────────
 Plugin dialog ──┐
                 ├──▶  cmd-tlm-api ──▶ bridge hub ◀──── openc3-cosmos-app
 Discover        │     (admin only)    (per bridge)       │
 Hardware ───────┘                                        ▼
                                                     Python discovery classes
                                                     (serial, HID, USB, mDNS,
                                                      SSDP, ARP, Bluetooth)
```

1. The plugin dialog or the Discover Hardware dialog asks COSMOS to run a discovery on one of its **bridges**. Each bridge is a computer paired through openc3-cosmos-app; every scope has one named `DEFAULT`.
2. COSMOS passes the request to the bridge, and openc3-cosmos-app picks it up. openc3-cosmos-app keeps its own Python environment for discovery with the packages the built-in discovery classes need, so the host needs no setup.
3. openc3-cosmos-app runs the discovery classes on the host, and the devices they find come back to COSMOS.

Running discovery requires the `admin` permission, the same as installing a plugin, because it runs code on the host.

## Using Discovery

### When Installing a Plugin

A variable configured for discovery shows a dropdown of the devices found, with a refresh button beside it.

- **Choosing the computer.** Discovery runs on the bridge the plugin's bridge variable selects, or on `DEFAULT` if the plugin doesn't have one. Changing the bridge runs discovery again.
- **New installs.** The first device found is selected automatically, unless a value was already chosen.
- **Devices in use.** A device another installed plugin is using on the same computer is shown as in use and isn't offered. This keeps two plugins from opening the same serial port, for example. Uninstalling the plugin frees the device. Upgrading or editing a plugin still offers the devices it already uses.
- **Typing a value.** You can always type a value instead, for example when the device isn't connected yet.

### Discover Hardware

In **Admin Console → Plugins**, click **Discover Hardware**. Choose a bridge, or **All bridges** when more than one computer is paired, and COSMOS scans the selected computers, which takes about 10 seconds.

Each device found is listed with the plugins that support it:

- **Store plugins.** These come from the OpenC3 Store. **Requires license** marks plugins you aren't entitled to install.
- **Installed plugins.** These are already installed in COSMOS. **Install Another** installs another copy of the plugin for the new device.
- **Possible match.** The plugin recognized the device only by a name pattern, such as a Bluetooth name starting with `Govee`, which other products from the same maker can share. The plugin may not support this exact device. Check the plugin's documentation.
- **In use by …** marks a device an installed plugin is already using.

Plugins are listed with the most specific match first, so a plugin for one exact product comes before a plugin that matches a USB-to-serial chip that many devices use.

Click **Install** to open the plugin install dialog with the device, the computer and any settings that depend on the device already filled in. Review them and install as usual. Target names that are already taken are replaced with the next free name, such as `INST_2`, if the plugin uses [`VARIABLE_TYPE TARGET_NAME`](../configuration/plugins.md#variable_type).

**Other devices** lists the devices no plugin recognized.

## Configuring a Plugin for Discovery

Three [`plugin.txt`](../configuration/plugins.md) keywords configure discovery:

| Keyword | Purpose |
| --- | --- |
| [`VARIABLE_BRIDGE`](../configuration/plugins.md#variable_bridge) | Lets the user choose the computer (bridge) the plugin's interfaces and discovery run on |
| [`VARIABLE_DISCOVERY`](../configuration/plugins.md#variable_discovery) | Discovers the values of a variable with a discovery class and its parameters |
| [`VARIABLE_DISCOVERY_SET`](../configuration/plugins.md#variable_discovery_set) | Sets other variables when a value from that discovery is chosen |

A complete serial device plugin:

```cosmos
VARIABLE_BRIDGE
  VARIABLE_DESCRIPTION "Computer the power supply is connected to"
VARIABLE serial_port /dev/ttyUSB0
  VARIABLE_LABEL "Serial port"
  # A Silicon Labs CP210x USB serial adapter
  VARIABLE_DISCOVERY openc3/discovery/serial_discovery.py 10C4:EA60
TARGET PSU PSU
INTERFACE PSU_INT serial_interface.py <%= serial_port %> <%= serial_port %> 115200 NONE 1 10.0 nil
  MAP_TARGET PSU
  BRIDGE <%= bridge_name %>
```

`VARIABLE_BRIDGE` defines a variable named `bridge_name`, whose value is passed to the interface's [`BRIDGE`](../configuration/plugins.md#bridge) modifier and also selects where discovery runs.

### Discovery Classes

The first parameter of `VARIABLE_DISCOVERY` is a discovery class, given as a filename (`openc3/discovery/serial_discovery.py`) or a module (`openc3.discovery.serial_discovery`). The parameters after it decide which devices are found. COSMOS provides these classes:

| Class | Finds | Value | Parameters |
| --- | --- | --- | --- |
| `serial_discovery` | Serial ports | Port name, e.g. `/dev/ttyUSB0` or `COM3` | USB `VID:PID` in hex, e.g. `10C4:EA60`. Use `VID:*` or `VID` for any product of a vendor. |
| `hid_discovery` | USB HID devices (game controllers, keypads, ...) | Serial number | Vendor ID then product ID, decimal or `0x` hex, e.g. `0x054C 0x0CE6` |
| `usb_discovery` | Other USB devices (cameras, radios, debug probes, instruments) | Serial number, or a location like `1-2.3` when there is none | `VID:PID` in hex, or conditions: `vid=`, `pid=`, `class=` (device or interface class, optionally `/subclass/protocol`), `manufacturer=`, `product=`, `serial=` |
| `zeroconf_discovery` | Network devices advertising mDNS / DNS-SD services | IP address | Service type, e.g. `_hue._tcp.local.`, optionally followed by `\|name=glob` or `\|<TXT property>=glob` filters |
| `ssdp_discovery` | Network devices advertising SSDP / UPnP (media players, TVs, cameras, routers) | IP address | Conditions on the response headers `st`, `usn` and `server`, or the device description fields `devicetype`, `friendlyname`, `manufacturer`, `modelname`, `modelnumber`, `serialnumber` and others |
| `neighbor_discovery` | Network hosts the computer has recently communicated with, from its ARP table | IP address | Conditions: `mac=` (hex digits, with or without separators), `hostname=` (reverse DNS) and `ip=` |
| `bluetooth_discovery` | Bluetooth LE devices that are advertising | Bluetooth address | Conditions: `local_name=`, `service_uuid=`, `service_data_uuid=`, `manufacturer_id=`, `manufacturer_data_start=` (hex) |

How parameters combine:

- **Each parameter is an alternative.** A device is found if any one of them matches. The exception is `hid_discovery`, whose two parameters together identify one product.
- **Conditions within a parameter are joined with `|`,** and all of them must match, e.g. `manufacturer=Sonos*|modelname=Sonos?Era*`.
- **Glob patterns** use `*` and `?`. They are case-insensitive, except Bluetooth `local_name`.
- **Spaces.** Parameters are separated by spaces, so use `?` to match a space inside a pattern.
- **Several discoveries.** A variable can have more than one `VARIABLE_DISCOVERY`, and their results are combined.

```cosmos
VARIABLE controller_serial ""
  VARIABLE_DISCOVERY openc3/discovery/hid_discovery.py 0x054C 0x0CE6
VARIABLE sdr_serial ""
  VARIABLE_DISCOVERY openc3/discovery/usb_discovery.py 0BDA:2838
VARIABLE scope_serial ""
  # Any USB test and measurement (USBTMC) instrument from this vendor
  VARIABLE_DISCOVERY openc3/discovery/usb_discovery.py vid=0699|class=FE/03
VARIABLE bridge_host ""
  VARIABLE_DISCOVERY openc3/discovery/zeroconf_discovery.py _hue._tcp.local.
VARIABLE speaker_host ""
  VARIABLE_DISCOVERY openc3/discovery/ssdp_discovery.py manufacturer=Sonos*
VARIABLE plc_host ""
  VARIABLE_DISCOVERY openc3/discovery/neighbor_discovery.py mac=00D02D*
VARIABLE sensor_address ""
  VARIABLE_DISCOVERY openc3/discovery/bluetooth_discovery.py local_name=SensorTag*|manufacturer_id=13
```

### Setting Other Variables from the Device Found

`VARIABLE_DISCOVERY_SET` follows a `VARIABLE_DISCOVERY` and sets another variable when the user chooses a device that discovery found. This lets one plugin support several models:

```cosmos
VARIABLE controller_model 5
  VARIABLE_STATE "DualShock 4 (PS4)" 4
  VARIABLE_STATE "DualSense (PS5)" 5
  VARIABLE_STATE "DualSense Edge (PS5)" 5edge
VARIABLE controller_serial ""
  VARIABLE_DISCOVERY openc3/discovery/hid_discovery.py 0x054C 0x05C4
    VARIABLE_DISCOVERY_SET controller_model 4
  VARIABLE_DISCOVERY openc3/discovery/hid_discovery.py 0x054C 0x0CE6
    VARIABLE_DISCOVERY_SET controller_model 5
  VARIABLE_DISCOVERY openc3/discovery/hid_discovery.py 0x054C 0x0DF2
    VARIABLE_DISCOVERY_SET controller_model 5edge
```

Choosing a DualSense Edge sets `controller_model` to `5edge`. When the set value selects a `VARIABLE_STATE`, as here, Discover Hardware also uses that state's text to name the match, e.g. "DualSense Edge (PS5)".

### Parameters That Depend on Other Variables

Discovery parameters can use the value of another variable as `${name}`. The discovery runs again when that variable changes, and doesn't run while all the variables it uses are blank. A value with several space-separated words becomes several parameters.

A common pattern is a hidden variable that each state sets, so one plugin supports several kinds of device:

```cosmos
VARIABLE device hue
  VARIABLE_STATE "Philips Hue" hue
    VARIABLE_STATE_SET mdns_types "_hue._tcp.local. _hap._tcp.local.|md=BSB002*"
  VARIABLE_STATE Shelly shelly
    VARIABLE_STATE_SET mdns_types _shelly._tcp.local.
VARIABLE mdns_types ""
  VARIABLE_HIDDEN
VARIABLE host ""
  VARIABLE_DISCOVERY openc3/discovery/zeroconf_discovery.py ${mdns_types}
```

Discover Hardware creates one match for each state, here named "Philips Hue" and "Shelly". Installing from a match selects its state as well as filling in the device. If the variable is only shown by some states (`VARIABLE_STATE_SHOW`), only those states count.

### Making a Plugin Show Up in Discover Hardware

Discover Hardware proposes a plugin for a device when one of its `VARIABLE_DISCOVERY` keywords would find that device. To take part, a discovery must:

- **Use a discovery class provided by COSMOS.** Discover Hardware never runs code from plugins that aren't installed.
- **Have parameters.** A discovery without parameters, such as any serial port, finds every device of its kind, so it doesn't identify the hardware the plugin supports.
- **Have parameters that can be worked out without installing,** from fixed values, variable defaults or the states that set them.

The OpenC3 Store reads this from the `plugin.txt` of each plugin version when it is uploaded. Installed plugins are read from the installed copy.

To be proposed accurately:

- **Be as specific as the hardware allows.** Prefer a USB `VID:PID` over a vendor ID alone, and a manufacturer ID or service UUID over a Bluetooth name. More specific matches are listed first.
- **Avoid matching on a name pattern alone.** A match that relies only on a name pattern, such as Bluetooth `local_name`, network `hostname`, USB `manufacturer`/`product` or SSDP `friendlyname`, is shown as **Possible match**. Add a condition that identifies the product, e.g. `local_name=Acme_TH*|manufacturer_id=1234` rather than `local_name=Acme*`, and list only models the plugin supports.
- **Name the matches.** Use `VARIABLE_STATE` text, or a `VARIABLE_DISCOVERY_SET` that selects a state, so each match has a clear model name.
- **Use `VARIABLE_TYPE TARGET_NAME`** for target names, so the plugin can be installed again for a second device without a name conflict.

### Writing a Discovery Class

If none of the provided classes fit, a discovery class can be written in Python. Subclass `openc3.discovery.discovery.Discovery`, which receives the `VARIABLE_DISCOVERY` parameters as strings, and implement either:

- `discover()`, returning a list of values, or of dicts with a `value` and an optional `text` description; or
- `scan()` and `match(device)`. `scan()` returns every device as a dict with a `value`, a `text` and any other details. `match()` returns whether a device is one these parameters are looking for.

```python
from openc3.discovery.discovery import Discovery


class MyRadioDiscovery(Discovery):
    def __init__(self, *models):
        super().__init__(*models)
        self.models = [model.upper() for model in models]

    def scan(self):
        # List the radios connected to this computer
        return [{"value": "RADIO-0042", "text": "Model X radio (RADIO-0042)", "model": "X"}]

    def match(self, device):
        return not self.models or device["model"] in self.models
```

The class is named after its file: `my_radio_discovery.py` contains `MyRadioDiscovery`. openc3-cosmos-app finds it if it's in the `lib` folder of a plugin already installed in COSMOS, since openc3-cosmos-app syncs those folders to the host. It isn't available when the plugin that contains it is being installed for the first time. Discover Hardware only uses the classes COSMOS provides.

### Testing Discovery on a Computer

The runners openc3-cosmos-app uses can be run directly in a Python environment with the `openc3` package and the packages the class needs (`hidapi`, `pyusb` and `libusb-package`, `zeroconf` or `bleak`):

```bash
python -m openc3.discovery.discovery_runner openc3/discovery/serial_discovery.py 10C4:EA60
# {"results": [{"value": "/dev/ttyUSB0", "text": "CP2102 USB to UART Bridge Controller (/dev/ttyUSB0)"}]}

echo '{"matchers": [{"id": "1", "class": "openc3.discovery.hid_discovery", "params": ["0x054C", "0x0CE6"]}]}' \
  | python -m openc3.discovery.discovery_scan
```

`discovery_scan` lists every device each provided class can see, and the ids of the matchers each device matches.

## Troubleshooting

| Problem | Cause |
| --- | --- |
| No bridge is paired with openc3-cosmos-app | Install openc3-cosmos-app on the computer with the devices and pair it with COSMOS from the **Bridges** tab of the Admin Console |
| Timeout waiting for discovery | openc3-cosmos-app isn't running or can't reach COSMOS, or it is still setting up its discovery environment, which happens the first time it starts |
| openc3-cosmos-app does not support hardware discovery | Update openc3-cosmos-app |
| A device isn't found | Check that it is connected and powered, and that the computer can use it: on Linux, serial and HID devices need permission for the user running openc3-cosmos-app (e.g. the `dialout` group or a udev rule). Bluetooth requires the computer's Bluetooth to be on, and the operating system may ask to allow openc3-cosmos-app to use it. |
| A network host isn't found by `neighbor_discovery` | It only lists hosts the computer has communicated with recently. Ping the device or open its web page first. |
| A device is listed as in use | Another installed plugin uses it on that computer. Uninstall that plugin, or choose a different device. |
| An error is shown for one kind of device | That discovery class failed, e.g. Bluetooth isn't available on the computer. Other kinds of devices are still listed. |
