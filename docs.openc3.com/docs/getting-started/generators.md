---
sidebar_position: 6
title: Code Generators
description: Using openc3.sh to generate code
sidebar_custom_props:
  myEmoji: 🏭
---

The COSMOS Code Generators are built into the scripts `openc3.sh` and `openc3.bat` that are included in the COSMOS [project](https://github.com/OpenC3/cosmos-project) (more about [projects](key-concepts#projects)).

If you followed the [Installation Guide](installation.md) you should already be inside a cloned [cosmos-project](https://github.com/OpenC3/cosmos-project) which is in your PATH (necessary for openc3.bat / openc3.sh to be resolved). To see all the available code generators type the following:

```bash
% openc3.sh cli generate
Unknown generator ''. Valid generators: plugin, target, microservice, widget, conversion,
  processor, limits_response, tool, tool_vue, tool_angular, tool_react, tool_svelte
```

:::note Training Available
If any of this gets confusing, contact us at <a href="mailto:support@openc3.com">support@openc3.com</a>. We have training classes available!
:::

## Plugin Generator

The plugin generator creates the scaffolding for a new COSMOS Plugin. It requires a plugin name and will create a new directory called `openc3-cosmos-<name>`. For example:

```bash
% openc3.sh cli generate plugin
Usage: cli generate plugin <NAME>

% openc3.sh cli generate plugin GSE
Plugin openc3-cosmos-gse successfully generated!
```

This creates the following files:

| Name                      | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| .gitignore                | Tells git to ignore any node_modules directory (for tool development)                                                                                                                                                                                                                                                                                                                                                                                                                     |
| LICENSE.txt               | License for the plugin. COSMOS Plugins should be licensed in a manner compatible with the AGPLv3, unless they are designed only for use with COSMOS Enterprise.                                                                                                                                                                                                                                                                                                                           |
| openc3-cosmos-gse.gemspec | Gemspec file which should be edited to add user specific information like description, authors, emails, homepage, etc. The name of this file is used in compiling the plugin contents into the final corresponding gem file: e.g. openc3-cosmos-gse-1.0.0.gem. COSMOS plugins should always begin with the openc3-cosmos prefix to make them easily identifiable in the Rubygems repository. The file is formatted as documented at: https://guides.rubygems.org/specification-reference/ |
| plugin.txt                | COSMOS specific file for Plugin creation. Learn more [here](../configuration/plugins).                                                                                                                                                                                                                                                                                                                                                                                                    |
| Rakefile                  | Ruby Rakefile configured to support building the plugin by running "openc3.sh cli rake build VERSION=X.X.X" where X.X.X is the plugin version number                                                                                                                                                                                                                                                                                                                                      |
| README.md                 | Markdown file used to document the plugin                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| requirements.txt          | Python dependencies file (only for Python plugins)                                                                                                                                                                                                                                                                                                                                                                                                                                        |

While this structure is required, it is not very useful by itself. The plugin generator just creates the framework for other generators to use.

## Target Generator

The target generator creates the scaffolding for a new COSMOS Target. It must operate inside an existing COSMOS plugin and requires a target name. For example:

```bash
openc3-cosmos-gse % openc3.sh cli generate target
Usage: cli generate target <NAME> (--ruby or --python)

openc3-cosmos-gse % openc3.sh cli generate target GSE --python
Target GSE successfully generated!
```

This creates the following files and directories:

| Name                                       | Description                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| targets/GSE                                | Contains the configuration for the GSE target. The target name is always defined in all caps. This is typically the default name of the target, but well-designed targets will allow themselves to be renamed at installation.                                                                                                                                                                                                 |
| targets/GSE/cmd_tlm                        | Contains the command and telemetry definition files for the GSE target. These files capture the format of the commands that can be sent to the target, and the telemetry packets that are expected to be received by COSMOS from the target. Note that the files in this folder are processed in alphabetical order by default. That can matter if you reference a packet in another file (it must already have been defined). |
| targets/GSE/cmd_tlm/cmd.txt                | Example [command](../configuration/command) configuration. Will need to be edited for the target specific commands.                                                                                                                                                                                                                                                                                                            |
| targets/GSE/cmd_tlm/tlm.txt                | Example [telemetry](../configuration/telemetry) configuration. Will need to be edited for the target specific telemetry.                                                                                                                                                                                                                                                                                                       |
| targets/GSE/lib                            | Contains any custom code required by the target. Good examples of custom code are library files, custom [interface](../configuration/interfaces) classes and [protocols](../configuration/protocols).                                                                                                                                                                                                                          |
| targets/GSE/lib/gse.\[rb/py\]              | Example library file which can be expanded as the target is developed. COSMOS recommends building up library methods to avoid code duplication and ease reuse.                                                                                                                                                                                                                                                                 |
| targets/GSE/procedures                     | This folder contains target specific procedures and helper methods which exercise functionality of the target. These procedures should be kept simple and only use the command and telemetry definitions associated with this target. See the [Scripting Guide](../guides/script-writing#script-organization) for more information.                                                                                            |
| targets/GSE/procedures/procedure.\[rb/py\] | Procedure with an example of sending a command and checking telemetry                                                                                                                                                                                                                                                                                                                                                          |
| targets/GSE/public                         | Put image files here for use in Telemetry Viewer Canvas Image widgets such as [CANVASIMAGE](../configuration/telemetry-screens.md#canvasimage) and [CANVASIMAGEVALUE](../configuration/telemetry-screens.md#canvasimagevalue)                                                                                                                                                                                                  |
| targets/GSE/screens                        | Contains telemetry [screens](../configuration/telemetry-screens.md) for the target                                                                                                                                                                                                                                                                                                                                             |
| targets/GSE/screens/status.txt             | Example [screen](../configuration/telemetry-screens.md) to display telemetry values                                                                                                                                                                                                                                                                                                                                            |
| targets/GSE/target.txt                     | [Target](../configuration/target) configuration such as ignoring command and telemetry items and how to process the cmd/tlm files                                                                                                                                                                                                                                                                                              |

It also updates the plugin.txt file to add the new target:

```ruby
VARIABLE gse_target_name GSE

TARGET GSE <%= gse_target_name %>
INTERFACE <%= gse_target_name %>_INT openc3/interfaces/tcpip_client_interface.py host.docker.internal 8080 8081 10.0 nil BURST
# INTERFACE <%= gse_target_name %>_INT tcpip_client_interface.rb host.docker.internal 8080 8081 10.0 nil BURST
  MAP_TARGET <%= gse_target_name %>
```

## Microservice Generator

The microservice generator creates the scaffolding for a new COSMOS Microservice. It must operate inside an existing COSMOS plugin and requires a target name. For example:

```bash
openc3-cosmos-gse % openc3.sh cli generate microservice
Usage: cli generate microservice <NAME> (--ruby or --python)

openc3-cosmos-gse % openc3.sh cli generate microservice background --python
Microservice BACKGROUND successfully generated!
```

This creates the following files and directories:

| Name                                   | Description                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| microservices/BACKGROUND               | Contains the code and any necessary configuration for the BACKGROUND microservice. The name is always defined in all caps. This is typically the default name of the microservice, but well-designed microservices will allow themselves to be renamed at installation.                                                                                                        |
| microservices/BACKGROUND/background.py | Fully functional microservice which will run every minute and log a message. Edit to implement any custom logic that you want to run in the background. Potential uses are safety microservices which can check and autonomously respond to complex events and take action (NOTE: Simple actions might just require a [Limits Response](/docs/configuration/limits-response)). |

It also updates the plugin.txt file to add the new microservice:

```ruby
MICROSERVICE BACKGROUND background-microservice
  CMD python background.py
```

## Conversion Generator

The conversion generator creates the scaffolding for a new COSMOS [Conversion](/docs/configuration/conversions). It must operate inside an existing COSMOS plugin and requires both a target name and conversion name. For example:

```bash
openc3-cosmos-gse % openc3.sh cli generate conversion
Usage: cli generate conversion <TARGET> <NAME> (--ruby or --python)

openc3-cosmos-gse % openc3.sh cli generate conversion GSE double --python
Conversion targets/GSE/lib/double_conversion.py successfully generated!
To use the conversion add the following to a telemetry item:
  READ_CONVERSION double_conversion.py
```

For more information about creating custom conversions and how to apply them, see the [Conversion](/docs/configuration/conversions) documentation.

## Processor Generator

The processor generator creates the scaffolding for a new COSMOS [Processor](/docs/configuration/processors). It must operate inside an existing COSMOS plugin and requires both a target name and processor name. For example:

```bash
openc3-cosmos-gse % openc3.sh cli generate processor
Usage: cli generate processor <TARGET> <NAME> (--ruby or --python)

openc3-cosmos-gse % openc3.sh cli generate processor GSE slope --python
Processor targets/GSE/lib/slope_processor.py successfully generated!
To use the processor add the following to a telemetry packet:
  PROCESSOR SLOPE slope_processor.py <PARAMS...>
```

For more information about creating custom processors and how to apply them, see the [Processor](/docs/configuration/processors) documentation.

## Limits Response Generator

The limits_response generator creates the scaffolding for a new COSMOS [Limits Response](/docs/configuration/limits-response). It must operate inside an existing COSMOS plugin and requires both a target name and limits response name. For example:

```bash
openc3-cosmos-gse % openc3.sh cli generate limits_response
Usage: cli generate limits_response <TARGET> <NAME> (--ruby or --python)

openc3-cosmos-gse % openc3.sh cli generate limits_response GSE safe --python
Limits response targets/GSE/lib/safe_limits_response.py successfully generated!
To use the limits response add the following to a telemetry item:
  LIMITS_RESPONSE safe_limits_response.py
```

For more information about creating limits responses and how to apply them, see the [Limits Response](/docs/configuration/limits-response) documentation.

## Widget Generator

The widget generator creates the scaffolding for a new COSMOS Widget for use in [Telemetry Viewer Screens](/docs/configuration/telemetry-screens). For more information see the [Custom Widget](/docs/guides/custom-widgets) guide. It must operate inside an existing COSMOS plugin and requires a widget name. For example:

```bash
openc3-cosmos-gse % openc3.sh cli generate widget
Usage: cli generate widget <SuperdataWidget>

openc3-cosmos-gse % openc3.sh cli generate widget HelloworldWidget
Widget HelloworldWidget successfully generated!
Please be sure HelloworldWidget does not overlap an existing widget: https://docs.openc3.com/docs/configuration/telemetry-screens
```

This creates the following files and directories:

| Name                     | Description                                                                                                                                                |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| src/HelloworldWidget.vue | Fully functional widget which displays a simple value. This can be expanded using existing COSMOS Vue.js code to create any data visualization imaginable. |

It also updates the plugin.txt file to add the new widget:

```ruby
WIDGET Helloworld
```

## Tool Generator

The tool generator creates the scaffolding for a new COSMOS Tool. It's It must operate inside an existing COSMOS plugin and requires a tool name. Developing a custom tool requires intensive knowledge of a Javascript framework such as Vue.js, Angular, React, or Svelte. Since all the COSMOS tools are built in Vue.js, that is the recommended framework for new tool development. For additional help on frontend development, see [Running a Frontend Application](../development/developing#running-a-frontend-application).

```bash
openc3-cosmos-gse % openc3.sh cli generate tool
Usage: cli generate tool 'Tool Name'

openc3-cosmos-gse % openc3.sh cli generate tool DataVis
Tool datavis successfully generated!
Please be sure datavis does not conflict with any other tools
```

This creates the following files and directories:

| Name                          | Description                                                                                                                                                                                                             |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| src/App.vue                   | Basic Vue template to render the application.                                                                                                                                                                           |
| src/main.js                   | Entry point for the new tool which loads Vue, Vuetify, and other libraries.                                                                                                                                             |
| src/router.js                 | Vue component router.                                                                                                                                                                                                   |
| src/tools/datavis             | Contains all the files necessary to serve a web-based tool named datavis. The name is always defined in all lowercase. Due to technical limitations, the toolname must be unique and cannot be renamed at installation. |
| src/tools/datavis/datavis.vue | Fully functional tool which displays a simple button. This can be expanded using existing COSMOS Vue.js code to create any tool imaginable.                                                                             |
| package.json                  | Build and dependency definition file. Used by pnpm to build the tool.                                                                                                                                            |
| vue.config.js                 | Vue configuration file used to serve the application in development and build the application.                                                                                                                          |
| \<dotfiles\>                  | Various dotfiles which help configure formatters and tools for Javascript frontend development                                                                                                                          |

It also updates the plugin.txt file to add the new tool. The icon can be changed to any of the material design icons found [here](https://pictogrammers.com/library/mdi/).

```ruby
TOOL datavis "DataVis"
  INLINE_URL main.js
  ICON mdi-file-cad-box
```
