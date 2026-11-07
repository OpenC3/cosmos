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

:::info[Visual Studio Code]
This tutorial will use [VS Code](https://code.visualstudio.com) which is the editor used by the COSMOS developers. NOTE: There is a VS Code plugin maintained by a member of the COSMOS community at [openc3-vscode](https://github.com/JakeHillHub/openc3-vscode) (search in the Marketplace for 'OpenC3').
:::

The most common use case for Local Mode is script development. Launch Script Runner and open the `INST/procedures/checks.rb` file. If you run this script you'll notice that it has a few errors (by design) which prevent it from running to completion. Let's fix it! Comment out lines 7 & 9 and save the script. You should now notice that Local Mode has saved a copy of the script to `plugins/targets_modified/INST/procedures/checks.rb`.

![Project Layout](/img/guides/local_mode/project.png)

At this point Local Mode keeps these scripts in sync so we can edit in either place. Let's edit the local script by adding a simple comment at the top: `# This is a script`. Now if we go back to Script Runner the changes have not _automatically_ appeared. However, there is a Reload button next to the filename that will refresh the file from the backend.

![Project Layout](/img/guides/local_mode/reload_file.png)

Clicking this reloads the file which has been synced into COSMOS and now we see our comment.

![Project Layout](/img/guides/local_mode/reloaded.png)

### Disabling Local Mode

If you want to disable Local Mode you can edit the .env file and delete the setting `OPENC3_LOCAL_MODE=1`.

## Local Only Targets

Local Mode keeps two copies of each edited file in sync: one in the `plugins` directory on the host and one in the COSMOS config bucket. For some targets you may want the files to live only on the host, for example when the host's project directory should be the single source of those files and they should never be copied into the bucket. List those targets in `OPENC3_LOCAL_ONLY_TARGETS`, separated by commas:

```bash
# .env or .env.local
OPENC3_LOCAL_ONLY_TARGETS=INST,INST2
```

Restart COSMOS (`openc3.sh stop` then `openc3.sh run`) to apply the change. Target names are not case sensitive.

For each listed target, its target files (procedures, screens, tables and anything else under the target) are read from and written to `plugins/<SCOPE>/targets_modified/<TARGET>` only:

- Saving a file in Script Runner, Table Manager, Telemetry Viewer and the other tools writes it to the host directory and never to the bucket. Local Mode's sync never copies these files to or from the bucket either.
- Files are only read from the host directory. There is no fallback to the bucket, so **files shipped in the plugin are not visible for these targets**. Copy any plugin files you need into `plugins/<SCOPE>/targets_modified/<TARGET>`.
- Scripts reach these files the same way through `get_target_file` and `put_target_file`. A script running outside COSMOS (for example from your own machine using the COSMOS Python or Ruby client) reads and writes them through the COSMOS API, which serves them from the host directory.
- Asking for a bucket download or upload URL for one of these files returns an error, since the file is not in the bucket.
- Files that were already in the bucket before you added a target to the list, for example from earlier Local Mode syncs, are hidden but not deleted. Remove them from the bucket yourself if you no longer want them there.

Local only targets work whether or not `OPENC3_LOCAL_MODE` is enabled. When a plugin with a local only target is upgraded, COSMOS still finds the modified files in the host directory and offers to delete them, just as it does for Local Mode.

The target's plugin still supplies everything else: command and telemetry definitions, interfaces and microservices are installed from the plugin as usual.

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
