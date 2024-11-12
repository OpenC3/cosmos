---
title: Script Runner
description: Run Python or Ruby scripts to send commands and check telemetry
sidebar_custom_props:
  myEmoji: 🛠️
---

## Introduction

Script Runner is both an editor of COSMOS scripts as well as executes scripts. Script files are stored within a COSMOS target and Script Runner provides the ability to open, save, download and delete these files. When a suite of scripts is opened, Script Runner provides additional options to run individual scripts, groups of scripts, or entire suites.

![Script Runner](/img/script_runner/script_runner.png)

## Script Runner Menus

### File Menu Items

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/script_runner/file_menu.png').default}
alt="File Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 250 + 'px'}} />

- Clears the editor and filename
- Creates a new test suite in Ruby or Python
- Opens a dialog to select a file to open
- Opens a recently used file
- Saves the currently opened file to disk
- Rename the current file
- Downloads the current file to the browser
- Deletes the current file (Permanently!)
  <br/>
  <br/>

#### File Open

The File Open Dialog displays a tree view of the installed targets. You can manually open the folders and browse for the file you want. You can also use the search box at the top and start typing part of the filename to filter the results.

![File Open](/img/script_runner/file_open.png)

#### File Save As

When saving a file for the first time, or using File Save As, the File Save As Dialog appears. It works similar to the File Open Dialog displaying the tree view of the installed targets. You must select a folder by clicking the folder name and then filling out the Filename field with a filename before clicking Ok. You will be prompted before over-writing an existing file.

### Script Menu Items

<!-- Image sized to match up with bullets -->

<img src={require('@site/static/img/script_runner/script_menu.png').default}
alt="Script Menu"
style={{"float": 'left', "margin-right": 50 + 'px', "height": 330 + 'px'}} />

- Display started and finished scripts
- Show environment variables
- Show defined metadata
- Show overridden telemetry values
- Perform a syntax check
- Perform a script mnemonic check
- View the instrumented script
- Shows the script call stack
- Display the [debug](script-runner.md#debugging-scripts) prompt
- Disconnect from real interfaces
- Delete all script breakpoints

The Execution Status popup lists the currently running scripts. This allows other users to connect to running scripts and follow along with the currently executing script. It also lists previously executed scripts so you can download the script log.

![Running Scripts](/img/script_runner/running_scripts.png)

## Running Scripts

Running a regular script is simply a matter of opening it and clicking the Start button. By default when you open a script the Filename is updated and the editor loads the script.

![checks.rb](/img/script_runner/checks_rb.png)

Once you click Start the script is spawned in the Server and the Script State becomes Connecting.

![connecting](/img/script_runner/connecting.png)

At that point the currently executing line is marked with green. If an error is encountered the line turns red and and the Pause button changes to Retry to allow the line to be re-tried.

![error](/img/script_runner/script_error.png)

This allows checks that depend on telemetry changing to potentially be retried as telemetry is being updated live in the background. You can also click Go to continue pass the error or Stop to end the script execution.

### Right Click Script

Right clicking a script brings up several options:

![right-click](/img/script_runner/right_click.png)

'Execute selection' causes the selected piece of code to be copied to a fresh Script Runner tab and executed independently of the current script. This is useful to run a selected section of code but be careful of references to other variables that are not selected. COSMOS will not be able to reference undefined variables!

'Run from here' causes everything from the current location of the cursor to be copied to a fresh Script Runner tab and executed independently of the current script. This is useful to avoid executing earlier pieces of code but be careful of references to other variables that are not selected. COSMOS will not be able to reference undefined variables!

'Clear all breakpoints' allows you to quickly clear breakpoints set by clicking on the editor line number.

## Running Script Suites

If a script is structured as a Suite it automatically causes Script Runner to parse the file to populate the Suite, Group, and Script drop down menus.

![Suite Script](/img/script_runner/script_suite.png)

To generate a new Suite use the File -> New Suite and then choose either Ruby or Python to create a Suite in that language.

### Group

The Group class contains the methods used to run the test or operations. Any methods starting with 'script', 'op', or 'test' which are implemented inside a Group class are automatically included as scripts to run. For example, in the above image, you'll notice the 'script_power_on' is in the Script drop down menu. Here's another simple Ruby example:

<!-- prettier-ignore -->
```ruby
require 'openc3/script/suite.rb'
class ExampleGroup < OpenC3::Group
  def setup
    puts "setup"
  end
  def script_1
    puts "script 1"
  end
  def teardown
    puts "teardown"
  end
end
```

Equivalent Python example:

<!-- prettier-ignore -->
```python
from openc3.script.suite import Suite, Group
class ExampleGroup(Group):
    def setup(self):
        print("setup")
    def script_1(self):
        print("script 1")
    def teardown(self):
        print("teardown")
```

The setup and teardown methods are special methods which enable the Setup and Teardown buttons next to the Group drop down menu. Clicking these buttons runs the associated method.

### Suite

Groups are added to Suites by creating a class inheriting from Suite and then calling the add_group method. For example in Ruby:

<!-- prettier-ignore -->
```ruby
class MySuite < OpenC3::Suite
  def initialize
    add_group('ExampleGroup')
  end
  def setup
    puts "Suite setup"
  end
  def teardown
    puts "Suite teardown"
  end
end
```

In Python:

<!-- prettier-ignore -->
```python
from openc3.script.suite import Suite, Group
class MySuite(Suite):
    def __init__(self):
        self.add_group('ExampleGroup')
    def setup(self):
        print("Suite setup")
    def teardown(self):
        print("Suite teardown")
```

Again there are setup and teardown methods which enable the Setup and Teardown buttons next to the Suite drop down menu.

Multiple Suites and Groups can be created in the same file and will be parsed and added to the drop down menus. Clicking Start at the Suite level will run ALL Groups and ALL Scripts within each Group. Similarly, clicking Start at the Group level will run all Scripts in the Group. Clicking Start next to the Script will run just the single Script.

### Script Suite Options

Opening a Script Suite creates six checkboxes which provide options to the running script.

![Suite Checkboxes](/img/script_runner/suite_checkboxes.png)

#### Pause on Error

Pauses the script if an error is encountered. This is the default and identical to how normal scripts are executed. Unchecking this box allows the script to continue past errors without user intervention. Similar to the User clicking Go upon encountering an error.

#### Continue after Error

Continue the script if an error is encountered. This is the default and identical to how normal scripts are executed. Unchecking this box means that the script will end after the first encountered error and execution will continue with any other scripts in the Suite/Group.

#### Abort after Error

Abort the entire execution upon encountering an error. If the first Script in a Suite's Group encounters an error the entire Suite will stop execution. Note, if Continue after Error is set, the current script is allowed to continue and complete.

#### Manual

In Ruby, sets the global variable called `$manual` to true. In Python, sets `RunningScript.manual` to True. Setting this box only allows the script author to determine if the operator wants to execute manual steps or not. It is up the script author to use the variable in their scripts.

#### Loop

Loop whatever the user started continuously. If the user clicks Start next to the Group then the entire Group will be looped. This is useful to catch and debug those tricky timing errors that only sometimes happen.

#### Break Loop on Error

Break the loop if an Error occurs. Only available if the Loop option is set.

## Debugging Scripts

When you enable the Debug prompt an additional line appears between the script and the Log Messages. You can type local variables to cause them to be output in the Log Messages. You can also set local variables by typing `var = 10`.

![Debug](/img/script_runner/debug.png)

The Step button allows you to step line by line through the script. Clicking Go continues regular execution.
