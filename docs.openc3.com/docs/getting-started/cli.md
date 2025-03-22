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
  cli script list /PATH SCOPE       # lists script names filtered by path within scope, 'DEFAULT' if not given
  cli script spawn NAME SCOPE  variable1=value1 variable2=value2  # Starts named script remotely
  cli script run NAME SCOPE variable1=value1 variable2=value2  # Starts named script, monitoring status on console,  by default until error or exit
    PARAMETERS name-value pairs to form the script's runtime environment
    OPTIONS: --wait 0 seconds to monitor status before detaching from the running script; ie --wait 100
             --disconnect run the script in disconnect mode
  cli validate /PATH/FILENAME.gem SCOPE variables.txt # Validate a COSMOS plugin gem file
  cli load /PATH/FILENAME.gem SCOPE variables.txt     # Loads a COSMOS plugin gem file
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

The script methods allow you to list the available scripts, spawn a script, and run a script while monitoring its output. Note that you must set the OPENC3_API_PASSWORD in Open Source and both the OPENC3_API_USER and OPENC3_API_PASSWORD in Enterprise.

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
% openc3.sh spawn INST/procedures/checks.rb
1
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

## Validate

Validate is used to validate built COSMOS plugins. It walks through the installation process without actually installing the plugin.

```bash
% openc3.sh cli validate openc3-cosmos-test-1.0.0.gem
Installing openc3-cosmos-test-1.0.0.gem
Successfully validated openc3-cosmos-test-1.0.0.gem
```

## Load

Load can load a plugin into COSMOS without using the GUI. This is useful for scripts or CI/CD pipelines.

```bash
% openc3.sh cli load openc3-cosmos-test-1.0.0.gem
Installing openc3-cosmos-test-1.0.0.gem
Successfully installed openc3-cosmos-test-1.0.0.gem
```

## List

List displays all the installed plugins.

```bash
% openc3.sh cli load openc3-cosmos-test-1.0.0.gem
Installing openc3-cosmos-test-1.0.0.gem
Successfully installed openc3-cosmos-test-1.0.0.gem
```

## Generate

Generate is used to scaffold new COSMOS plugins, targets, conversions, and more! See the [Generators](/docs/getting-started/generators) page for more information.

## Bridge

A COSMOS Bridge is a small application that is run on the local computer to connect to hardware not available to Docker containers. A good example is connecting to a serial port on a non-linux system. See the
[Bridge Guide](/docs/guides/bridges) for more information.

## Pkginstall and pkguninstall

Allows you to install or remove Ruby gems or Python wheels into COSMOS. These are dependencies that are not packaged with the COSMOS plugin itself.

```bash
% openc3.sh cli pkginstall local_gem.gem
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
