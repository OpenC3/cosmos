---
sidebar_position: 4
title: Upgrading
description: How to upgrade and migrate COSMOS
sidebar_custom_props:
  myEmoji: ⬆️
---

### COSMOS Upgrades

COSMOS is released as Docker containers. Since we're using Docker containers and volumes we can simply stop the existing COSMOS application, then download and run the new release.

This example assumes an existing COSMOS project at C:\cosmos-project.

1. Stop the current COSMOS application

   ```batch
   C:\cosmos-project> openc3.bat stop
   ```

1. Change the release in the .env file to the desired release

   ```batch
   OPENC3_TAG=5.1.1
   ```

1. Run the new COSMOS application

   ```batch
   C:\cosmos-project> openc3.bat run
   ```

:::warning Downgrades
Downgrades are not necessarily supported. When upgrading COSMOS we need to upgrade databases and sometimes migrate internal data structures. While we perform a full regression test on every release, we recommend upgrading an individual machine with your specific plugins and do local testing before rolling out the upgrade to your production system.

In general, patch releases (x.y.Z) can be downgraded, minor releases (x.Y.z) _might_ be able to be downgraded and major releases (X.y.z) are NOT able to be downgraded.
:::

### Migrating From COSMOS 4 to COSMOS 5

COSMOS 5 is a new architecture and treats targets as independent [plugins](../configuration/plugins.md). Thus the primary effort in porting from COSMOS 4 to COSMOS 5 is converting targets to plugins. We recommend creating plugins for each independent target (with its own interface) but targets which share an interface will need to be part of the same plugin. The reason for independent plugins is it allows the plugin to be versioned separately and more easily shared outside your specific project. If you have very project specific targets (e.g. custom hardware) those can potentially be combined for ease of deployment.

COSMOS 5 includes a migration tool for converting an existing COSMOS 4 configuration into a COSMOS 5 plugin. This example assumes an existing COSMOS 4 configuration at C:\COSMOS and a new COSMOS 5 installation at C:\cosmos-project. Linux users can adjust paths and change from .bat to .sh to follow along.

1. Change to the existing COSMOS 4 configuration directory. You should see the config, lib, procedures, outputs directory. You can then run the migration tool by specifying the absolute path to the COSMOS 5 installation.

   ```batch
   C:\COSMOS> C:\cosmos-project\openc3.bat cli migrate -a demo
   ```

   This creates a new COSMOS 5 plugin called openc3-cosmos-demo with a target named DEMO containing the existing lib and procedures files as well as all the existing targets.

   ```batch
   C:\COSMOS> C:\cosmos-project\openc3.bat cli migrate demo-part INST
   ```

   This would create a new COSMOS 5 plugin called openc3-cosmos-demo-part with a target named DEMO_PART containing the existing lib and procedures files as well as the INST target (but no others).

1. Open the new COSMOS 5 plugin and ensure the [plugin.txt](../configuration/plugins.md#plugintxt-configuration-file) file is correctly configured. The migration tool doesn't create VARIABLEs or MICROSERVICEs or handle target substitution so those features will have to added manually.

1. Follow the [building your plugin](gettingstarted.md#building-your-plugin) part of the Getting Started tutorial to build your new plugin and upload it to COSMOS 5.
