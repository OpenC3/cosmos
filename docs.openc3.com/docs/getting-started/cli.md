---
sidebar_position: 5
title: Command Line Interface
description: Using openc3.sh
sidebar_custom_props:
  myEmoji: ⌨️
---

The COSMOS Command Line Interface is `openc3.sh` and `openc3.bat` which are included in the COSMOS [project](https://github.com/OpenC3/cosmos-project) (more about [projects](key-concepts#projects)).

If you followed the [Installation Guide](installation.md) you should already be inside a cloned [openc3-project](https://github.com/OpenC3/cosmos-project) which is in your PATH (necessary for openc3.bat / openc3.sh to be resolved). To see all the available type the following:

```bash
% openc3.sh cli
Usage:
  cli help                          # Displays this information
  cli rake                          # Runs rake in the local directory
  cli irb                           # Runs irb in the local directory
  cli script                        # Interact with scripts. Run with --help for more info.
  cli validate /PATH/FILENAME.gem SCOPE variables.json  # Validate a COSMOS plugin gem file
  cli load /PATH/FILENAME.gem SCOPE plugin_hash.json    # Loads a COSMOS plugin gem file
    OPTIONS: --variables lets you pass a path to a JSON file containing your plugin\'s variables
  cli list <SCOPE>                  # Lists installed plugins, SCOPE is DEFAULT if not given
  cli generate TYPE OPTIONS         # Generate various COSMOS entities
    OPTIONS: --ruby or --python is required to specify the language in the generated code unless OPENC3_LANGUAGE is set
  cli bridge CONFIG_FILENAME        # Run COSMOS host bridge
  cli bridgegem gem_name variable1=value1 variable2=value2 # Runs bridge using gem bridge.txt
  cli bridgesetup CONFIG_FILENAME   # Create a default config file
  cli pkginstall PKGFILENAME SCOPE  # Install loaded package (Ruby gem or python package)
  cli pkguninstall PKGFILENAME SCOPE  # Uninstall loaded package (Ruby gem or python package)
  cli rubysloc                      # DEPRECATED: Please use scc (https://github.com/boyter/scc)
  cli xtce_converter                # Convert to and from the XTCE format. Run with --help for more info.
  cli cstol_converter               # Converts CSTOL files (.prc) to COSMOS. Run with --help for more info.
```

:::note seccomp profile
You can safely ignore `WARNING: daemon is not using the default seccomp profile`
:::

## Rake

You can execute rake tasks using `openc3.sh cli rake`. The most typical usage is to generate a plugin and then build it. For example:

```bash
% openc3.sh cli rake build VERSION=1.0.0
```

## IRB

IRB stands for Interactive Ruby and is a way to start a Ruby interpreter that you can play around with. When using it from the CLI, it includes the COSMOS Ruby path so you can `require 'cosmos'` and try out various methods. For example:

```bash
% openc3.sh cli irb
irb(main):001:0> require 'cosmos'
=> true
irb(main):002:0> Cosmos::Api::WHITELIST
=>
["get_interface",
 "get_interface_names",
 ...
]
```

## Script

The script methods allow you to list the available scripts, spawn a script, and run a script while monitoring its output. Note that you must set the OPENC3_API_PASSWORD in COSMOS Core and both the OPENC3_API_USER and OPENC3_API_PASSWORD in COSMOS Enterprise.

:::note Offline Access Token (since 6.3.0)
You must visit the frontend Script Runner page as the OPENC3_API_USER or run "openc3.sh cli script init" in order to obtain an offline access token before the other script cli methods will work.
:::

### Init (Enterprise Only since 6.3.0)

Obtain an offline access token without visiting the frontend GUI. This is required when running in a headless CI/CD environment before accessing any of the other commands.

### List

List all the available scripts which includes all the files in every target directory. You can filter this list using bash to only include procedures, Ruby files, Python files, etc.

```bash
% export OPENC3_API_USER=operator
% export OPENC3_API_PASSWORD=operator
% openc3.sh cli script list
EXAMPLE/cmd_tlm/example_cmds.txt
EXAMPLE/cmd_tlm/example_tlm.txt
...
```

### Spawn

The ID of the spawned script is returned. You can connect to it in Script Runner by visiting `http://localhost:2900/tools/scriptrunner/1` where the final value is the ID.

```bash
% openc3.sh cli script spawn INST/procedures/checks.rb
4
```

### Run

Run spawns the script and then captures the output and prints it to the shell. Note that this will not work with user input prompts so the script must be written to prevent user input. You can also pass variables to the script as shown in the CLI help.

```bash
% openc3.sh cli script run INST/procedures/stash.rb
Filename INST/procedures/stash.rb scope DEFAULT
2025/03/22 19:50:40.429 (SCRIPTRUNNER): Script config/DEFAULT/targets/INST/procedures/stash.rb spawned in 0.796683293 seconds <ruby 3.2.6>
2025/03/22 19:50:40.453 (SCRIPTRUNNER): Starting script: stash.rb, line_delay = 0.1
At [INST/procedures/stash.rb:3] state [running]
At [INST/procedures/stash.rb:4] state [running]
2025/03/22 19:50:40.732 (stash.rb:4): key1: val1
At [INST/procedures/stash.rb:5] state [running]
At [INST/procedures/stash.rb:6] state [running]
2025/03/22 19:50:40.936 (stash.rb:6): key2: val2
At [INST/procedures/stash.rb:7] state [running]
2025/03/22 19:50:41.039 (stash.rb:7): CHECK: 'val1' == 'val1' is TRUE
At [INST/procedures/stash.rb:8] state [running]
2025/03/22 19:50:41.146 (stash.rb:8): CHECK: 'val2' == 'val2' is TRUE
At [INST/procedures/stash.rb:9] state [running]
2025/03/22 19:50:41.256 (stash.rb:9): CHECK: '["key1", "key2"]' == '["key1", "key2"]' is TRUE
At [INST/procedures/stash.rb:10] state [running]
At [INST/procedures/stash.rb:11] state [running]
At [INST/procedures/stash.rb:12] state [running]
2025/03/22 19:50:41.556 (stash.rb:12): CHECK: '{"key1"=>1, "key2"=>2}' == '{"key1"=>1, "key2"=>2}' is TRUE
At [INST/procedures/stash.rb:13] state [running]
At [INST/procedures/stash.rb:14] state [running]
2025/03/22 19:50:41.763 (stash.rb:14): CHECK: true == true is TRUE
At [INST/procedures/stash.rb:15] state [running]
At [INST/procedures/stash.rb:16] state [running]
At [INST/procedures/stash.rb:17] state [running]
At [INST/procedures/stash.rb:18] state [running]
2025/03/22 19:50:42.176 (stash.rb:18): CHECK: '[1, 2, [3, 4]]' == '[1, 2, [3, 4]]' is TRUE
At [INST/procedures/stash.rb:19] state [running]
At [INST/procedures/stash.rb:21] state [running]
At [INST/procedures/stash.rb:22] state [running]
At [INST/procedures/stash.rb:23] state [running]
2025/03/22 19:50:42.587 (stash.rb:23): CHECK: '{"one"=>1, "two"=>2, "string"=>"string"}' == '{"one"=>1, "two"=>2, "string"=>"string"}' is TRUE
At [INST/procedures/stash.rb:24] state [running]
2025/03/22 19:50:42.697 (SCRIPTRUNNER): Script completed: stash.rb
At [INST/procedures/stash.rb:0] state [stopped]
script complete
%
```

### Running (since 6.5.0)

List all the running scripts. Add the --verbose option to print the raw output.

```bash
% openc3.sh cli script running
ID    User                 Filename                       Start Time             State
5     The Operator         INST/procedures/collect.rb     2025-06-06T22:40:48Z   paused
4     The Operator         INST/procedures/checks.rb      2025-06-06T22:40:21Z   error
```

### Status (since 6.5.0)

List status for a specific script based on the script ID. Add the --verbose option to print the raw output.

```bash
% openc3.sh cli script status 5
ID    User                 Filename                       Start Time             State
5     The Operator         INST/procedures/collect.rb     2025-06-06T22:40:48Z   paused
```

### Stop (since 6.5.0)

Stop a script based on the script ID.

```bash
% openc3.sh cli script stop 5
```

## Validate

Validate is used to validate built COSMOS plugins. It walks through the installation process without actually installing the plugin.

```bash
% openc3.sh cli validate openc3-cosmos-cfdp-1.0.0.gem
Installing openc3-cosmos-cfdp-1.0.0.gem
Successfully validated openc3-cosmos-cfdp-1.0.0.gem
```

You can optionally pass it the scope to install the plugin in (for Enterprise) and the path to a JSON file containing your plugin variables. If using COSMOS Core, use `DEFAULT` for the scope. If you pass a variables file, any variables not defined in the file will take the default value (as defined in your `plugin.txt` file).

## Load

Load can load a plugin into COSMOS without using the GUI. This is useful for scripts or CI/CD pipelines.

```bash
% openc3.sh cli load openc3-cosmos-cfdp-1.0.0.gem
Loading new plugin: openc3-cosmos-cfdp-1.0.0.gem
{"name"=>"openc3-cosmos-cfdp-1.0.0.gem", "variables"=>{"cfdp_microservice_name"=>"CFDP", "cfdp_route_prefix"=>"/cfdp", "cfdp_port"=>"2905", "cfdp_cmd_target_name"=>"CFDP2", "cfdp_cmd_packet_name"=>"CFDP_PDU", "cfdp_cmd_item_name"=>"PDU", "cfdp_tlm_target_name"=>"CFDP2", "cfdp_tlm_packet_name"=>"CFDP_PDU", "cfdp_tlm_item_name"=>"PDU", "source_entity_id"=>"1", "destination_entity_id"=>"2", "root_path"=>"/DEFAULT/targets_modified/CFDP/tmp", "bucket"=>"config", "plugin_test_mode"=>"false"}, "plugin_txt_lines"=>["VARIABLE cfdp_microservice_name CFDP", "VARIABLE cfdp_route_prefix /cfdp", "VARIABLE cfdp_port 2905", "", "VARIABLE cfdp_cmd_target_name CFDP2", "VARIABLE cfdp_cmd_packet_name CFDP_PDU", "VARIABLE cfdp_cmd_item_name PDU", "", "VARIABLE cfdp_tlm_target_name CFDP2", "VARIABLE cfdp_tlm_packet_name CFDP_PDU", "VARIABLE cfdp_tlm_item_name PDU", "", "VARIABLE source_entity_id 1", "VARIABLE destination_entity_id 2", "VARIABLE root_path /DEFAULT/targets_modified/CFDP/tmp", "VARIABLE bucket config", "", "# Set to true to enable a test configuration", "VARIABLE plugin_test_mode \"false\"", "", "MICROSERVICE CFDP <%= cfdp_microservice_name %>", "  WORK_DIR .", "  ROUTE_PREFIX <%= cfdp_route_prefix %>", "  ENV OPENC3_ROUTE_PREFIX <%= cfdp_route_prefix %>", "  ENV SECRET_KEY_BASE 324973597349867207430793759437697498769349867349674", "  PORT <%= cfdp_port %>", "  CMD rails s -b 0.0.0.0 -p <%= cfdp_port %> -e production", "  # MIB Options Follow -", "  # You will need to modify these for your mission", "  OPTION source_entity_id <%= source_entity_id %>", "  OPTION tlm_info <%= cfdp_tlm_target_name %> <%= cfdp_tlm_packet_name %> <%= cfdp_tlm_item_name %>", "  OPTION destination_entity_id <%= destination_entity_id %>", "  OPTION cmd_info <%= cfdp_cmd_target_name %> <%= cfdp_cmd_packet_name %> <%= cfdp_cmd_item_name %>", "  OPTION root_path <%= root_path %>", "  <% if bucket.to_s.strip != '' %>", "    OPTION bucket <%= bucket %>", "  <% end %>", "", "<% include_test = (plugin_test_mode.to_s.strip.downcase == \"true\") %>", "<% if include_test %>", "  TARGET CFDPTEST CFDP", "  TARGET CFDPTEST CFDP2", "", "  MICROSERVICE CFDP CFDP2", "    WORK_DIR .", "    ROUTE_PREFIX /cfdp2", "    ENV OPENC3_ROUTE_PREFIX /cfdp2", "    ENV SECRET_KEY_BASE 324973597349867207430793759437697498769349867349674", "    PORT 2906", "    CMD rails s -b 0.0.0.0 -p 2906 -e production", "    OPTION source_entity_id <%= destination_entity_id %>", "    OPTION tlm_info CFDP CFDP_PDU PDU", "    OPTION destination_entity_id <%= source_entity_id %>", "    OPTION cmd_info CFDP CFDP_PDU PDU", "    OPTION root_path <%= root_path %>", "    <% if bucket.to_s.strip != '' %>", "      OPTION bucket <%= bucket %>", "    <% end %>", "", "  <% test_host = ENV['KUBERNETES_SERVICE_HOST'] ? (scope.to_s.downcase + \"-interface-cfdp2-int-service\") : \"openc3-operator\" %>", "  INTERFACE CFDP_INT tcpip_client_interface.rb <%= test_host %> 2907 2907 10.0 nil LENGTH 0 32 4 1 BIG_ENDIAN 0 nil nil true", "    MAP_TARGET CFDP", "", "  INTERFACE CFDP2_INT tcpip_server_interface.rb 2907 2907 10.0 nil LENGTH 0 32 4 1 BIG_ENDIAN 0 nil nil true", "    PORT 2907", "    MAP_TARGET CFDP2", "<% end %>"], "needs_dependencies"=>false, "updated_at"=>nil}
Updating local plugin files: /plugins/DEFAULT/openc3-cosmos-cfdp
```

You can optionally pass it the scope to install the plugin in (for Enterprise) and the path to a JSON file containing the entire `plugin_hash` for your plugin. This lets you manually set things like the installed name, `updated_at` timestamp, and other properties. Use this carefully.

There is also a `--variables` option, which allows you to pass the path to a JSON file containing your plugin variables. This is the same as the optional variables file mentioned above for `cli validate`.

## List

List displays all the installed plugins.

```bash
% openc3.sh cli list
openc3-cosmos-cfdp-1.0.0.gem__20250325160956
openc3-cosmos-demo-6.2.2.pre.beta0.20250325143120.gem__20250325160201
openc3-cosmos-enterprise-tool-admin-6.2.2.pre.beta0.20250325155648.gem__20250325160159
openc3-cosmos-tool-autonomic-6.2.2.pre.beta0.20250325155658.gem__20250325160225
openc3-cosmos-tool-bucketexplorer-6.2.2.pre.beta0.20250325143107.gem__20250325160227
openc3-cosmos-tool-calendar-6.2.2.pre.beta0.20250325155654.gem__20250325160224
openc3-cosmos-tool-cmdhistory-6.2.2.pre.beta0.20250325155651.gem__20250325160212
openc3-cosmos-tool-cmdsender-6.2.2.pre.beta0.20250325143111.gem__20250325160211
openc3-cosmos-tool-cmdtlmserver-6.2.2.pre.beta0.20250325143114.gem__20250325160208
openc3-cosmos-tool-dataextractor-6.2.2.pre.beta0.20250325143104.gem__20250325160219
openc3-cosmos-tool-dataviewer-6.2.2.pre.beta0.20250325143108.gem__20250325160220
openc3-cosmos-tool-docs-6.2.2.pre.beta0.20250325155535.gem__20250325160228
openc3-cosmos-tool-grafana-6.2.2.pre.beta0.20250325155658.gem__20250325160233
openc3-cosmos-tool-handbooks-6.2.2.pre.beta0.20250325143113.gem__20250325160222
openc3-cosmos-tool-iframe-6.2.2.pre.beta0.20250325143110.gem__20250325160158
openc3-cosmos-tool-limitsmonitor-6.2.2.pre.beta0.20250325155448.gem__20250325160209
openc3-cosmos-tool-packetviewer-6.2.2.pre.beta0.20250325143104.gem__20250325160215
openc3-cosmos-tool-scriptrunner-6.2.2.pre.beta0.20250325143111.gem__20250325160214
openc3-cosmos-tool-tablemanager-6.2.2.pre.beta0.20250325143116.gem__20250325160223
openc3-cosmos-tool-tlmgrapher-6.2.2.pre.beta0.20250325143105.gem__20250325160218
openc3-cosmos-tool-tlmviewer-6.2.2.pre.beta0.20250325143108.gem__20250325160216
openc3-enterprise-tool-base-6.2.2.pre.beta0.20250325155704.gem__20250325160153
```

## Generate

Generate is used to scaffold new COSMOS plugins, targets, conversions, and more! See the [Generators](/docs/getting-started/generators) page for more information.

## Bridge

A COSMOS Bridge is a small application that is run on the local computer to connect to hardware not available to Docker containers. A good example is connecting to a serial port on a non-linux system. See the
[Bridge Guide](/docs/guides/bridges) for more information.

## Pkginstall and pkguninstall

Allows you to install or remove Ruby gems or Python wheels into COSMOS. These are dependencies that are not packaged with the COSMOS plugin itself.

```bash
% openc3.sh cli pkginstall rspec-3.13.0.gem
```

## Rubysloc (deprecated)

Calculates the Ruby Source Lines of Code (SLOC) from the current directory recursively. We recommend using [scc](https://github.com/boyter/scc) as it works across any programming language, calculates many more statistics, and is blazing fast.

## XTCE Converter

Converts from the XTCE format to the COSMOS format and also exports XTCE files given a COSMOS plugin.

```bash
% openc3.sh cli xtce_converter
Usage: xtce_converter [options] --import input_xtce_filename --output output_dir
       xtce_converter [options] --plugin /PATH/FILENAME.gem --output output_dir --variables variables.txt

    -h, --help                       Show this message
    -i, --import VALUE               Import the specified .xtce file
    -o, --output DIRECTORY           Create files in the directory
    -p, --plugin PLUGIN              Export .xtce file(s) from the plugin
    -v, --variables                  Optional variables file to pass to the plugin
```

## CSTOL Converter

Converts from the Colorado System Test and Operations Language (CSTOL) to a COSMOS Script Runner Ruby script. It currently does not support conversion to Python. Simply run it in the same directory as CSTOL files (\*.prc) and it will convert them all.

```bash
% openc3.sh cli cstol_converter
```
