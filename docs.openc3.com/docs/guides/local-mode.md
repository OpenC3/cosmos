---
title: Local Mode
description: Edit scripts and screens directly on the host file system
sidebar_custom_props:
  myEmoji: 🧭
---

Local Mode is a new feature in the 5.0.9 COSMOS release. It is intended to capture the configuration of an edited plugin so it can be configuration managed. It allows you to edit portions of a plugin (scripts and screens) locally in the editor of your choice and instantly have those changes appear in the COSMOS plugin. This avoids the plugin build / install cycle which is required when editing command and telemetry or interface definitions.

## Using Local Mode

In this tutorial we will use the COSMOS Demo as configured by the [Installation Guide](../getting-started/installation.md). You should have cloned a [cosmos-project](https://github.com/OpenC3/cosmos-project) and started it using `openc3.sh run`.

If you check the project directory you should see a `plugins/DEFAULT/openc3-cosmos-demo` directory. This will contain both the gem that was installed and a `plugin_instance.json` file. The `plugin_instance.json` file captures the plugin.txt values when the plugin was installed. Note, all files in the plugins directory are meant to be configuration managed with the project. This ensures if you make local edits and check them in, another user can clone the project and get the exact same configuration. We will demonstrate this later.

### Editing scripts

:::info Visual Studio Code
This tutorial will use [VS Code](https://code.visualstudio.com) which is the editor used by the COSMOS developers.
:::

The most common use case for Local Mode is script development. Launch Script Runner and open the `INST/procedures/checks.rb` file. If you run this script you'll notice that it has a few errors (by design) which prevent it from running to completion. Let's fix it! Comment out lines 7 & 9 and save the script. You should now notice that Local Mode has saved a copy of the script to `plugins/targets_modified/INST/procedures/checks.rb`.

![Project Layout](/img/guides/local_mode/project.png)

At this point Local Mode keeps these scripts in sync so we can edit in either place. Let's edit the local script by adding a simple comment at the top: `# This is a script`. Now if we go back to Script Runner the changes have not _automatically_ appeared. However, there is a Reload button next to the filename that will refresh the file from the backend.

![Project Layout](/img/guides/local_mode/reload_file.png)

Clicking this reloads the file which has been synced into COSMOS and now we see our comment.

![Project Layout](/img/guides/local_mode/reloaded.png)

### Disabling Local Mode

If you want to disable Local Mode you can edit the .env file and delete the setting `OPENC3_LOCAL_MODE=1`.

## Configuration Management

It is recommended to configuration manage the entire project including the plugins directory. This will allow any user who starts COSMOS to launch an identical configuration. Plugins are created and updated with any modifications found in the targets_modified directory.

At some point you will probably want to release your local changes back to the plugin they originated from. Simply copy the entire targets_modified/TARGET directory back to the original plugin. At that point you can rebuild the plugin using the CLI.

```
openc3-cosmos-demo % ./openc3.sh cli rake build VERSION=1.0.1
  Successfully built RubyGem
  Name: openc3-cosmos-demo
  Version: 1.0.1
  File: openc3-cosmos-demo-1.0.1.gem
```

Upgrade the plugin using the Admin Plugins tab and the Upgrade link. When you select your newly built plugin, COSMOS detects the existing changes and asks if you want to delete them. There is a stern warning attached because this will permanently remove these changes! Since we just moved over the changes and rebuilt the plugin we will check the box and INSTALL.

![Project Layout](/img/guides/local_mode/delete_modified.png)

When the new plugin is installed, the project's `plugins` directory gets updated with the new plugin and everything under the targets_modified directory is removed because there are no modifications on a new install.

Local Mode is a powerful way to develop scripts and screens on the local file system and automatically have them sync to COSMOS.
