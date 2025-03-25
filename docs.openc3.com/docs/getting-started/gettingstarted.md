---
sidebar_position: 3
title: Getting Started
description: Getting starting with COSMOS
sidebar_custom_props:
  myEmoji: 🧑‍💻
---

Welcome to the OpenC3 COSMOS system... Let's get started! This guide is a high level overview that will help with setting up your first COSMOS project.

1. Get COSMOS Installed onto your computer by following the [Installation Guide](installation).
   - You should now have COSMOS installed and a Demo project available that we can make changes to.
1. Browse to http://localhost:2900
   - The COSMOS Command and Telemetry Server will appear. This tool provides real-time information about each "target" in the system. Targets are external systems that receive commands and generate telemetry, often over ethernet or serial connections.
1. Experiment with other COSMOS tools. This is a DEMO environment so you can't break anything. Some things to try:
   - Use Command Sender to send individual commands.
   - Use Limits Monitor to watch for telemetry limits violations
   - Run some of the example scripts in Script Runner and Test Runner
   - View individual Telemetry packets in Packet Viewer
   - View detailed telemetry displays in Telemetry Viewer
   - Graph some data in Telemetry Grapher
   - View log type data in Data Viewer
   - Process log data with Data Extractor

:::info Browser Version Issue

When you try to load the page and it fails to load, check with the built-in web development tools / DevTools. We have seen some strange things with version of browsers. You can build to a version of browser if you need to by reading about the [browserslist](https://github.com/browserslist/browserslist). A typical failure results in:

```
unexpected token ||=
```

To fix this make sure your browsers is compliant with the current settings in the [.browserlistrc](https://github.com/OpenC3/cosmos/blob/main/openc3-cosmos-init/plugins/openc3-tool-base/.browserslistrc) file. You can change this and rebuild the image. Note: This can cause build speeds to increase or decrease.

:::

## Interfacing with Your Hardware

Playing with the COSMOS Demo is fun and all, but now you want to talk to your own real hardware? Let's do it!

:::info Install and Platform
This guide assumes we're on Windows and COSMOS is installed in C:\COSMOS. On Mac or Linux, change openc3.bat to openc3.sh and adjust paths as necessary to match your installation directory.
:::

1. Before creating your own configuration you should uninstall the COSMOS Demo so you're working with a clean COSMOS system. Click the Admin button and the PLUGINS tab. Then click the Trash can icon next to openc3-cosmos-demo to delete it. When you go back to the Command and Telemetry Server you should have a blank table with no interfaces.

1. If you followed the [Installation Guide](installation) you should already be inside a cloned [openc3-project](https://github.com/OpenC3/cosmos-project) which is in your PATH (necessary for openc3.bat / openc3.sh to be resolved). Inside this project it's recommended to edit the README.md ([Markdown](https://www.markdownguide.org/)) to describe your program / project.

1. Now we need to create a plugin. Plugins are how we add targets and microservices to COSMOS. Our plugin will contain a single target which contains all the information defining the packets (command and telemetry) that are needed to communicate with the target. Use the COSMOS plugin generator to create the correct structure.

:::info Python vs Ruby
Each CLI command requires the use of `--python` or `--ruby` unless you se the OPENC3_LANGUAGE environment variable to 'python' or 'ruby'.
:::

```batch
C:\openc3-project> openc3.bat cli generate plugin BOB --python
Plugin openc3-cosmos-bob successfully generated!
```

This should create a new directory called "openc3-cosmos-bob" with a bunch of files in it. The full description of all the files is explained by the [Plugin Generator](generators#plugin-generator) page.

:::info Run as the Root user
The cli runs as the default COSMOS container user which is the recommended practice. If you're having issues running as that user you can run as the root user (effectively `docker run --user=root` ) by running `cliroot` instead of `cli` in any of the examples.
:::

1. Starting with [COSMOS v5.5.0](https://openc3.com/news/2023/02/23/openc3-cosmos-5-5-0-released/), the plugin generator creates just the plugin framework (previously it would also create a target). From within the newly created plugin directory, we generate a target.

   ```batch
   C:\openc3-project> cd openc3-cosmos-bob
   openc3-cosmos-bob> openc3.bat cli generate target BOB --python
   Target BOB successfully generated!
   ```

:::info Generators
There are a number of generators available. Run `openc3.bat cli generate` to see all the available options.
:::

1. The target generator creates a single target named BOB. Best practice is to create a single target per plugin to make it easier to share targets and upgrade them individually. Lets see what the target generator created for us. Open the openc3-cosmos-bob/targets/BOB/cmd_tlm/cmd.txt:

   ```ruby
   COMMAND BOB EXAMPLE BIG_ENDIAN "Packet description"
     # Keyword           Name  BitSize Type   Min Max  Default  Description
     APPEND_ID_PARAMETER ID    16      INT    1   1    1        "Identifier"
     APPEND_PARAMETER    VALUE 32      FLOAT  0   10.5 2.5      "Value"
     APPEND_PARAMETER    BOOL  8       UINT   MIN MAX  0        "Boolean"
       STATE FALSE 0
       STATE TRUE 1
     APPEND_PARAMETER    LABEL 0       STRING          "OpenC3" "The label to apply"
   ```

   What does this all mean?

   - We created a COMMAND for target BOB named EXAMPLE.
   - The command is made up of BIG_ENDIAN parameters and is described by "Packet description". Here we are using the append flavor of defining parameters which stacks them back to back as it builds up the packet and you don't have to worry about defining the bit offset into the packet.
   - First we APPEND_ID_PARAMETER a parameter that is used to identify the packet called ID that is an 16-bit signed integer (INT) with a minimum value of 1, a maximum value of 1, and a default value of 1, that is described as the "Identifier".
   - Next we APPEND_PARAMETER a parameter called VALUE that is a 32-bit float (FLOAT) that has a minimum value of 0, a maximum value of 10.5, and a default value of 2.5.
   - Then we APPEND_PARAMETER a third parameter called BOOL which is a 8-bit unsigned integer (UINT) with a minimum value of MIN (meaning the smallest value a UINT supports, e.g 0), a maximum value of MAX (largest value a UINT supports, e.g. 255), and a default value of 0. BOOL has two states which are just a fancy way of giving meaning to the integer values 0 and 1. The STATE FALSE has a value of 0 and the STATE TRUE has a value of 1.
   - Finally we APPEND_PARAMETER called LABEL which is a 0-bit (meaning it takes up all the remaining space in the packet) string (STRING) with a default value of "OpenC3". Strings don't have minimum or maximum values as that doesn't make sense for STRING types.

   Check out the full [Command](../configuration/command) documentation for more.

1. Now open the openc3-cosmos-bob/targets/BOB/cmd_tlm/tlm.txt:

   ```ruby
   TELEMETRY BOB STATUS BIG_ENDIAN "Telemetry description"
     # Keyword      Name  BitSize Type   ID Description
     APPEND_ID_ITEM ID    16      INT    1  "Identifier"
     APPEND_ITEM    VALUE 32      FLOAT     "Value"
     APPEND_ITEM    BOOL  8       UINT      "Boolean"
       STATE FALSE 0
       STATE TRUE 1
     APPEND_ITEM    LABEL 0       STRING    "The label to apply"
   ```

   - This time we created a TELEMETRY packet for target BOB called STATUS that contains BIG_ENDIAN items and is described as "Telemetry description".
   - We start by defininig an ID_ITEM called ID that is a 16-bit signed integer (INT) with an id value of 1 and described as "Identifier". Id items are used to take unidentified blobs of bytes and determine which packet they are. In this case if a blob comes in with a value of 1, at bit offset 0 (since we APPEND this item first), interpreted as a 16-bit integer, then this packet will be "identified" as STATUS. Note the first packet defined without any ID_ITEMS is a "catch-all" packet that matches all incoming data (even if the data lengths don't match).
   - Next we define three items similar to the command definition above.

   Check out the full [Telemetry](../configuration/telemetry) documentation for more.

1. COSMOS has defined an example command and telemetry packet for our target. Most targets will obviously have more than one command and telemetry packet. To add more simply create additional COMMAND and TELEMETRY lines in your text files. Actual packets should match the structure of your command and telemetry. Be sure to add at least one unique [ID_PARAMETER](../configuration/command#id_parameter) and [ID_ITEM](../configuration/telemetry#id_item) so your packets can be distinguished from each other.

1. Now we need to tell COSMOS how to connect to our BOB target. Open the openc3-cosmos-bob/plugin.txt file:

   ```ruby
   # Set VARIABLEs here to allow variation in your plugin
   # See [Plugins](../configuration/plugins) for more information
   VARIABLE bob_target_name BOB

   # Modify this according to your actual target connection
   # See [Interfaces](../configuration/interfaces) for more information
   TARGET BOB <%= bob_target_name %>
   INTERFACE <%= bob_target_name %>_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 None BURST
      MAP_TARGET <%= bob_target_name %>
   ```

   - This configures the plugin with a VARIABLE called bob_target_name with a default of "BOB". When you install this plugin you will have the option to change the name of this target to something other than "BOB". This is useful to avoid name conflicts and allows you to have multiple copies of the BOB target in your COSMOS system.
   - The TARGET line declares the new BOB target using the name from the variable. The \<%= %> syntax is called ERB (embedded Ruby) and allows us to put variables into our text files, in this case referencing our bob_target_name.
   - The last line declares a new INTERFACE called (by default) BOB_INT that will connect as a TCP/IP client using the code in tcpip_client_interface.py to address host.docker.internal (This adds an /etc/hosts entry to the correct IP address for the host's gateway) using port 8080 for writing and 8081 for reading. It also has a write timeout of 10 seconds and reads will never timeout (nil). The TCP/IP stream will be interpreted using the COSMOS [BURST](../configuration/protocols#burst-protocol) protocol which means it will read as much data as it can from the interface. For all the details on how to configure COSMOS interfaces please see the [Interface Guide](../configuration/interfaces). The MAP_TARGET line tells COSMOS that it will receive telemetry from and send commands to the BOB target using the BOB_INT interface.

:::note Variables Support Reusability

In a plugin that you plan to reuse you should make things like hostnames and ports variables
:::

## Building Your Plugin

1. Now we need to build our plugin and upload it to COSMOS.

   ```batch
   openc3-cosmos-bob> openc3.bat cli rake build VERSION=1.0.0
     Successfully built RubyGem
     Name: openc3-cosmos-bob
     Version: 1.0.0
     File: openc3-cosmos-bob-1.0.0.gem
   ```

   - Note that the VERSION is required to specify the version to build. We recommend [semantic versioning](https://semver.org/) when building your plugin so people using your plugin (including you) know when there are breaking changes.

1. Once our plugin is built we need to upload it to COSMOS. Go back to the Admin page and click the Plugins Tab. Click on "Click to install plugin" and select the openc3-cosmos-bob-1.0.0.gem file. Then click Upload. Go back to the CmdTlmServer and you should see the plugin being deployed at which point the BOB_INT interface should appear and try to connect. Go ahead and click 'Cancel' because unless you really have something listening on port 8080 this will never connect. At this point you can explore the other CmdTlmServer tabs and other tools to see your newly defined BOB target.

1. Let's modify our BOB target and then update the copy in COSMOS. If you open Command Sender in COSMOS to BOB EXAMPLE you should see the VALUE parameter has value 2.5. Open the openc3-cosmos-bob/targets/BOB/cmd_tlm/cmd.txt and change the Default value for VALUE to 5 and the description to "New Value".

   ```ruby
   COMMAND BOB EXAMPLE BIG_ENDIAN "Packet description"
     # Keyword           Name  BitSize Type   Min Max  Default  Description
     APPEND_ID_PARAMETER ID    16      INT    1   1    1        "Identifier"
     APPEND_PARAMETER    VALUE 32      FLOAT  0   10.5 5        "New Value"
     APPEND_PARAMETER    BOOL  8       UINT   MIN MAX  0        "Boolean"
       STATE FALSE 0
       STATE TRUE 1
     APPEND_PARAMETER    LABEL 0       STRING          "OpenC3" "The label to apply"
   ```

1. Rebuild the plugin with a new VERSION number. Since we didn't make any breaking changes we simply bump the patch release number:

   ```batch
   openc3-cosmos-bob> openc3.bat cli rake build VERSION=1.0.1
     Successfully built RubyGem
     Name: openc3-cosmos-bob
     Version: 1.0.1
     File: openc3-cosmos-bob-1.0.1.gem
   ```

1. Go back to the Admin page and click the Plugins Tab. This time click the clock icon next to openc3-cosmos-bob-1.0.0 to Upgrade the plugin. Browse to the newly built plugin gem and select it. This will re-prompt for the plugin variables (bob_target_name) so don't change the name and just click OK. You should see a message about the plugin being installed at which point the plugins list will change to openc3-cosmos-bob-1.0.1.gem. Go back to Command Sender and you should see the new Default value for VALUE is 5 and the description is "New Value". We have upgraded our plugin!

1. At this point you can create a new plugin named after your real target and start modifying the interface and command and telemetry definitions to enable COSMOS to connect to and drive your target. If you run into trouble look for solutions on our [Github Issues](https://github.com/OpenC3/cosmos/issues) page. If you would like to enquire about support contracts or professional COSMOS development please contact us at support@openc3.com.
