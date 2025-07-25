---
title: Script Writing Guide
description: Key concepts and best practices for script writing
sidebar_custom_props:
  myEmoji: 🏃‍➡️
---

## Introduction

This guide aims to provide the best practices for using the scripting capabilities provided by COSMOS. Scripts are used to automate a series of activities for operations or testing. The goal of this document is to ensure scripts are written that are simple, easy to understand, maintainable, and correct. Guidance on some of the key details of using the COSMOS Script Runner is also provided.

## Concepts

COSMOS supports both Ruby and Python for writing scripts. Ruby and Python are very similar scripting languages and most of this guide applies directly to both. Where examples are used, both a Ruby and Python example are given.

### Ruby vs Python in COSMOS

There are many similarities and a few key differences between Ruby and Python when it comes to writing COSMOS scripts.

1. There is no 80 character limit on line length. Lines can be as long as you like, but be careful to not make them too long as it makes printed reviews of scripts more difficult.
1. Indentation white space:
   1. Ruby: Not significant. Ruby uses the `end` keyword to determine indented code blocks with a standard of 2 spaces.
   1. Python: Significant. Python uses indentation to determine code blocks with a standard of 4 spaces.
1. Variables do not have to be declared ahead of time and can be reassigned later, i.e. Ruby and Python are dynamically typed.
1. Variable interpolation:
   1. Ruby: Variable values can be placed into strings using the `"#{variable}"` syntax.
   1. Python: Variable values can be placed into f-strings using the `f"{variable}"` syntax.
1. A variable declared inside of a block or loop will not exist outside of that block unless it was already declared.

Both languages provides a script writer a lot of power. But with great power comes great responsibility. Remember when writing your scripts that you or someone else will come along later and need to understand them. Therefore use the following style guidelines:

- Use consistent spacing for indentation and do NOT use tabs
- Constants should be all caps with underscores
  - `SPEED_OF_LIGHT = 299792458 # meters per s`
- Variable names and method names should be in lowercase with underscores
  - `last_name = "Smith"`
  - `perform_setup_operation()`
- Class names (when used) should be camel case and the files which contain them should match but be lowercase with underscores
  - `class DataUploader # in 'data_uploader.rb'`
  - `class CcsdsUtility: # in 'ccsds_utility.py'`
- Don't add useless comments but instead describe intent

<div style={{"clear": 'both'}}></div>

The following is an example of good Ruby style:

```ruby
load 'TARGET/lib/upload_utility.rb' # library we do NOT want to show executing
load_utility 'TARGET/lib/helper_utility.rb' # library we do want to show executing

# Declare constants
OUR_TARGETS = ['INST','INST2']

# Clear the collect counter of the passed in target name
def clear_collects(target)
  cmd("#{target} CLEAR")
  wait_check("#{target} HEALTH_STATUS COLLECTS == 0", 5)
end

######################################
# START
######################################
helper = HelperUtility.new
helper.setup

# Perform collects on all the targets
OUR_TARGETS.each do |target|
  collects = tlm("#{target} HEALTH_STATUS COLLECTS")
  cmd("#{target} COLLECT with TYPE SPECIAL")
  wait_check("#{target} HEALTH_STATUS COLLECTS == #{collects + 1}", 5)
end

clear_collects('INST')
clear_collects('INST2')
```

The following is an example of good Python style:

```python
from openc3.script import *

import TARGET.lib.upload_utility # library we do NOT want to show executing
load_utility('TARGET/lib/helper_utility.rb') # library we do want to show executing

# Declare constants
OUR_TARGETS = ['INST','INST2']

# Clear the collect counter of the passed in target name
def clear_collects(target):
    cmd(f"{target} CLEAR")
    wait_check(f"{target} HEALTH_STATUS COLLECTS == 0", 5)

######################################
# START
######################################
helper = HelperUtility()
helper.setup()

# Perform collects on all the targets
for target in OUR_TARGETS:
    collects = tlm(f"{target} HEALTH_STATUS COLLECTS")
    cmd(f"{target} COLLECT with TYPE SPECIAL")
    wait_check(f"{target} HEALTH_STATUS COLLECTS == {collects + 1}", 5)

clear_collects('INST')
clear_collects('INST2')
```

Both examples shows several features of COSMOS scripting in action. Notice the difference between 'load' or 'import' and 'load_utility'. The first is to load additional scripts which will NOT be shown in Script Runner when executing. This is a good place to put code which takes a long time to run such as image analysis or other looping code where you just want the output. 'load_utility' will visually execute the code line by line to show the user what is happening.

Next we declare our constants and create an array of strings which we store in OUR_TARGETS. Notice the constant is all uppercase with underscores.

Then we declare our local methods of which we have one called clear_collects. Please provide a comment at the beginning of each method describing what it does and the parameters that it takes.

The 'helper_utility' is then created. Note the similarity in the class name and the file name we loaded.

The collect example shows how you can iterate over the array of strings we previously created and use variables when commanding and checking telemetry. The Ruby pound bracket #{} notation and python f-string f"{} notation puts whatever the variable holds into the string. You can even execute additional code inside the brackets like we do when checking for the collect count to increment.

Finally we call our 'clear_collects' method on each target by passing the target name.

## Scripting Philosophy

### A Super Basic Script Example

Most COSMOS scripts can be broken down into the simple pattern of sending a command to a system/subsystem and then verifying that the command worked as expected. This pattern is most commonly implemented with cmd() followed by wait_check(), like the following:

```ruby
cmd("INST COLLECT with TYPE NORMAL, TEMP 10.0")
wait_check("INST HEALTH_STATUS TYPE == 'NORMAL'", 5)
```

or similarly with a counter that is sampled before the command.

Ruby:

```ruby
count = tlm("INST HEALTH_STATUS COLLECTS")
cmd("INST COLLECT with TYPE NORMAL, TEMP 10.0")
wait_check("INST HEALTH_STATUS COLLECTS >= #{count + 1}", 5)
```

Python:

```python
count = tlm("INST HEALTH_STATUS COLLECTS")
cmd("INST COLLECT with TYPE NORMAL, TEMP 10.0")
wait_check(f"INST HEALTH_STATUS COLLECTS >= {count + 1}", 5)
```

90% of the COSMOS scripts you write should be the simple patterns shown above except that you may need to check more than one item after each command to make sure the command worked as expected.

### KISS (Keep It Simple Stupid)

Ruby and Python are very powerful languages with many ways to accomplish the same thing. Given that, always choose the method that is easiest to understand for yourself and others. While it is possible to create complex one liners or obtuse regular expressions, you'll thank yourself later by expanding complex one liners and breaking up and documenting regular expressions.

### Keep things DRY (Don't Repeat Yourself)

A widespread problem in scripts written for any command and control system is large blocks of code that are repeated multiple times. In extreme cases, this has led to 100,000+ line scripts that are impossible to maintain and review.

There are two common ways repetition presents itself: exact blocks of code to perform a common action such as powering on a subsystem, and blocks of code that only differ in the name of the mnemonic being checked or the values checked against. Both are solved by removing the repetition using methods (or functions).

For example, a script that powers on a subsystem and ensures correct telemetry would become:

Ruby:

```ruby
def power_on_subsystem
  # 100 lines of cmd(), wait_check(), etc
end
```

Python:

```python
def power_on_subsystem():
    # 100 lines of cmd(), wait_check(), etc
```

Ideally, the above methods would be stored in another file where it could be used by other scripts. If it is truly only useful in the one script, then it could be at the top of the file. The updated script would then look like:

```ruby
power_on_subsystem()
# 150 lines operating the subsystem (e.g.)
# cmd(...)
# wait_check(...)
#...
power_off_subystem()
# Unrelated activities
power_on_subsystem()
# etc.
```

Blocks of code where only the only variation is the mnemonics or values checked can be replaced by methods with arguments.

Ruby:

```ruby
def test_minimum_temp(enable_cmd_name, enable_tlm, temp_tlm, expected_temp)
  cmd("TARGET #{enable_cmd_name} with ENABLE TRUE")
  wait_check("TARGET #{enable_tlm} == 'TRUE'", 5)
  wait_check("TARGET #{temp_tlm} >= #{expected_temp}", 50)
end
```

Python:

```python
def test_minimum_temp(enable_cmd_name, enable_tlm, temp_tlm, expected_temp):
    cmd(f"TARGET {enable_cmd_name} with ENABLE TRUE")
    wait_check(f"TARGET {enable_tlm} == 'TRUE'", 5)
    wait_check(f"TARGET {temp_tlm} >= {expected_temp}", 50)
```

### Use Comments Appropriately

Use comments when what you are doing is unclear or there is a higher-level purpose to a set of lines. Try to avoid putting numbers or other details in a comment as they can become out of sync with the underlying code. Ruby and Python comments start with a # pound symbol and can be anywhere on a line.

```ruby
# This line sends an abort command - BAD COMMENT, UNNECESSARY
cmd("INST ABORT")
# Rotate the gimbal to look at the calibration target - GOOD COMMENT
cmd("INST ROTATE with ANGLE 180.0") # Rotate 180 degrees - BAD COMMENT
```

### Script Runner

COSMOS provides two unique ways to run scripts (also known as procedures). Script Runner provides both a script execution environment and a script editor. The script editor includes code completion for both COSMOS methods and command/telemetry item names. It is also a great environment to develop and test scripts. Script Runner provides a framework for users that are familiar with a traditional scripting model with longer style procedures, and for users that want to be able to edit their scripts in place.

When opening a suite file (named with 'suite') Script Runner provides a more formal, but also more powerful, environment for running scripts. Suite files breaks scripts down into suites, groups, and scripts (individual methods). Suites are the highest-level concept and would typically cover a large procedure such as a thermal vacuum test, or a large operations scenario such as performing on orbit checkout. Groups capture a related set of scripts such as all the scripts regarding a specific mechanism. A Group might be a collection of scripts all related to a subsystem, or a specific series of tests such as an RF checkout. Scripts capture individual activities that can either pass or fail. Script Runner allows for running an entire suite, one or more groups, or one or more scripts easily. It also automatically produces reports containing timing, pass / fail counts, etc.

The correct environment for the job is up to individual users, and many programs will use both script formats to complete their goals.

### Looping vs Unrolled Loops

Loops are powerful constructs that allow you to perform the same operations multiple times without having to rewrite the same code over and over (See the DRY Concept). However, they can make restarting a COSMOS script at the point of a failure difficult or impossible. If there is a low probability of something failing, then loops are an excellent choice. If a script is running a loop over a list of telemetry points, it may be a better choice to “unroll” the loop by making the loop body into a method, and then calling that method directly for each iteration of a loop that would have occurred.

Ruby:

```ruby
10.times do |temperature_number|
  check_temperature(temperature_number + 1)
end
```

Python:

```python
for temperature_number in range(1, 11):
    check_temperature(temperature_number)
```

If the above script was stopped after temperature number 3, there would be no way to restart the loop at temperature number 4. A better solution for small loop counts is to unroll the loop.

```ruby
check_temperature(1)
check_temperature(2)
check_temperature(3)
check_temperature(4)
check_temperature(5)
check_temperature(6)
check_temperature(7)
check_temperature(8)
check_temperature(9)
check_temperature(10)
```

In the unrolled version above, the COSMOS “Start script at selected line” feature can be used to resume the script at any point.

## Script Organization

All scripts must be part of a [Plugin](../configuration/plugins.md). You can create a simple plugin called SCRIPTS or PROCEDURES that only contains lib and procedures directories to store scripts. If COSMOS detects a plugin without defined cmd/tlm it will not spawn microservices for telemetry processing.

### Organizing Your Scripts into a Plugin

As your scripts become large with many methods, it makes sense to break them up into multiple files within a plugin. Here is a recommended organization for your plugin's scripts/procedures.

| Folder                         | Description                                                               |
| ------------------------------ | ------------------------------------------------------------------------- |
| targets/TARGET_NAME/lib        | Place script files containing reusable target specific methods here       |
| targets/TARGET_NAME/procedures | Place simple procedures that are centered around one specific target here |

In your main procedure you will usually bring in the other files with instrumentation using load_utility.

```ruby
# Ruby:
load_utility('TARGET/lib/my_other_script.rb')
# Python:
load_utility('TARGET/procedures/my_other_script.py')
```

### Organize Scripts into Methods

Put each activity into a distinct method. Putting your scripts into methods makes organization easy and gives a great high-level overview of what the overall script does (assuming you name the methods well). There are no bonus points for vague, short method names. Make your method names long and clear.

Ruby:

```ruby
def test_1_heater_zone_control
  puts "Verifies requirements 304, 306, and 310"
  # Test code here
end

def script_1_heater_zone_control
  puts "Verifies requirements 304, 306, and 310"
  # Test code here
end
```

Python:

```python
def test_1_heater_zone_control():
    print("Verifies requirements 304, 306, and 310")
    # Test code here

def script_1_heater_zone_control():
    print("Verifies requirements 304, 306, and 310")
    # Test code here
```

### Using Classes vs Unscoped Methods

Classes in object-oriented programming allow you to organize a set of related methods and some associated state. The most important aspect is that the methods work on some shared state. For example, if you have code that moves a gimbal around, and need to keep track of the number of moves, or steps, performed across methods, then that is a wonderful place to use a class. If you just need a helper method to do something that happens multiple times in a script without copy and pasting, it probably does not need to be in a class.

NOTE: The convention in COSMOS is to have a TARGET/lib/target.\[rb/py\] file which is named after the TARGET name and contains a class called Target. This discussion refers to scripts in the TARGET/procedures directory.

Ruby:

```ruby
class Gimbal
  attr_accessor :gimbal_steps
  def initialize()
    @gimbal_steps = 0
  end
  def move(steps_to_move)
    # Move the gimbal
    @gimbal_steps += steps_to_move
  end
  def home_gimbal
    # Home the gimbal
    @gimbal_steps = 0
  end
end

def perform_common_math(x, y)
  x + y
end

gimbal = Gimbal.new
gimbal.home_gimbal
gimbal.move(100)
gimbal.move(200)
puts "Moved gimbal #{gimbal.gimbal_steps}"
result = perform_common_math(gimbal.gimbal_steps, 10)
puts "Math:#{result}"
```

Python:

```python
class Gimbal:
    def __init__(self):
        self.gimbal_steps = 0

    def move(self, steps_to_move):
        # Move the gimbal
        self.gimbal_steps += steps_to_move

    def home_gimbal(self):
        # Home the gimbal
        self.gimbal_steps = 0

def perform_common_math(x, y):
    return x + y

gimbal = Gimbal()
gimbal.home_gimbal()
gimbal.move(100)
gimbal.move(200)
print(f"Moved gimbal {gimbal.gimbal_steps}")
result = perform_common_math(gimbal.gimbal_steps, 10)
print(f"Math:{result}")
```

### Instrumented vs Uninstrumented Lines (require vs load)

COSMOS scripts are normally “instrumented”. This means that each line has some extra code added behind the scenes that primarily highlights the current executing line and catches exceptions if things fail such as a wait_check. If your script needs to use code in other files, there are a few ways to bring in that code. Some techniques bring in instrumented code and others bring in uninstrumented code. There are reasons to use both.

load_utility (and the deprecated require_utility), bring in instrumented code from other files. When COSMOS runs the code in the other file, Script Runner will dive into the other file and show each line highlighted as it executes. This should be the default way to bring in other files, as it allows continuing if something fails, and provides better visibility to operators.

However, sometimes you don't want to display code executing from other files. Externally developed libraries generally do not like to be instrumented, and code that contains large loops or that just takes a long time to execute when highlighting lines, will be much faster if included in a method that does not instrument lines. Ruby provides two ways to bring in uninstrumented code. The first is the “load” keyword. Load will bring in the code from another file and will bring in any changes to the file if it is updated on the next call to load. “require” is like load but is optimized to only bring in the code from another file once. Therefore, if you use require and then change the file it requires, you must restart Script Runner to re-require the file and bring in the changes. In general, load is recommended over require for COSMOS scripting. One gotcha with load is that it requires the full filename including extension, while the require keyword does not.

In Python, libraries are included using the import syntax. Any code imported using import is not instrumented. Only the code imported using load_utility is instrumented.

Finally, COSMOS scripting has a special syntax for disabling instrumentation in the middle of an instrumented script, with the disable_instrumentation method. This allows you to disable instrumentation for large loops and other activities that are too slow when running instrumented.

Ruby:

```ruby
temp = 0
disable_instrumentation do
  # Make sure nothing in here will raise exceptions!
  5000000.times do
    temp += 1
  end
end
puts temp
```

Python:

```python
temp = 0
with disable_instrumentation():
    # Make sure nothing in here will raise exceptions!
    for x in range(0,5000000):
        temp += 1
print(temp)
```

:::warning When Running Uninstrumented Code
Make sure that the code will not raise any exceptions or have any check failures. If an exception is raised from uninstrumented code, then your entire script will stop.
:::

## Debugging and Auditing

### Built-In Debugging Capabilities

Script Runner has built in debugging capabilities that can be useful in determining why your script is behaving in a certain way. Of primary importance is the ability to inspect and set script variables.

To use the debugging functionality, first select the “Toggle Debug” option from the Script Menu. This will add a small Debug: prompt to the bottom of the tool. Any code entered in this prompt will be executed when Enter is pressed. To inspect variables in a running script, pause the script and then type the variable name to print out the value of the variable in the debug prompt.

```ruby
variable_name
```

Variables can also be set simply by using equals.

```ruby
variable_name = 5
```

If necessary, you can also inject commands from the debug prompt using the normal commanding methods. These commands will be logged to the Script Runner message log, which may be advantageous over using a different COSMOS tool like CmdSender (where the command would only be logged in the CmdTlmServer message log).

```ruby
cmd("INST COLLECT with TYPE NORMAL")
```

Note that the debug prompt keeps the command history and you can scroll through the history by using the up and down arrows.

### Breakpoints

You can click the line number (left side gutter) in Script Runner to add a breakpoint. The script will automatically pause when it hits the breakpoint. Once stopped at the breakpoint, you can evaluate variables using the Debug line.

### Using Disconnect Mode

Disconnect mode is a feature of Script Runner that allows testing scripts in an environment without real hardware in the loop. Disconnect mode is started by selecting Script -> Toggle Disconnect. Once selected, the user is prompted to select which targets to disconnect. By default, all targets are disconnected, which allows for testing scripts without any real hardware. Optionally, only a subset of targets can be selected which can be useful for trying out scripts in partially integrated environments.

While in disconnect mode, commands to the disconnected targets always succeed. Additionally, all checks of disconnected targets' telemetry are immediately successful. This allows for a quick run-through of procedures for logic errors and other script specific errors without having to worry about the behavior and proper functioning of hardware.

### Auditing your Scripts

Script Runner includes several tools to help audit your scripts both before and after execution.

#### Ruby Syntax Check

The Ruby Syntax Check tool is found under the Script Menu. This tool uses the ruby executable with the -c flag to run a syntax check on your script. If any syntax errors are found the exact message presented by the Ruby interpreter is shown to the user. These can be cryptic, but the most common faults are not closing a quoted string, forgetting an “end” keyword, or using a block but forgetting the proceeding “do” keyword.

## Common Scenarios

### User Input Best Practices

COSMOS provides several different methods to gather manual user input in scripts. When using user input methods that allow for arbitrary values (like ask() and ask_string()), it is very important to validate the value given in your script before moving on. When asking for text input, it is extra important to handle different casing possibilities and to ensure that invalid input will either re-prompt the user or take a safe path.

Ruby:

```ruby
answer = ask_string("Do you want to continue (y/n)?")
if answer != 'y' and answer != 'Y'
  raise "User entered: #{answer}"
end

temp = 0.0
while temp < 10.0 or temp > 50.0
  temp = ask("Enter the desired temperature between 10.0 and 50.0")
end
```

Python:

```python
answer = ask_string("Do you want to continue (y/n)?")
if answer != 'y' and answer != 'Y':
    raise RuntimeError(f"User entered: {answer}")

temp = 0.0
while temp < 10.0 or temp > 50.0:
    temp = ask("Enter the desired temperature between 10.0 and 50.0")
```

When possible, always use one of the other user input methods that has a constrained list of choices for your users (message_box, vertical_message_box, combo_box).

Note that all these user input methods provide the user the option to “Cancel”. When cancel is clicked, the script is paused but remains at the user input line. When hitting “Go” to the continue, the user will be re-prompted to enter the value.

### Conditionally Require Manual User Input Steps

When possible, a useful design pattern is to write your scripts such that they can run without prompting for any user input. This allows the scripts to be more easily tested and provides a documented default value for any user input choices or values. To implement this pattern, all manual steps such as ask(), prompt(), and infinite wait() statements need to be wrapped with an if statement that checks the value of $manual in Ruby or RunningScript.manual in Python. If the variable is set, then the manual steps should be executed. If not, then a default value should be used.

<Tabs groupId="script-language">
<TabItem value="python" label="Python">
```python
if RunningScript.manual:
    temp = ask("Please enter the temperature")
else:
    temp = 20.0
if not RunningScript.manual:
    print("Skipping infinite wait in auto mode")
else:
    wait()
```
</TabItem>
<TabItem value="ruby" label="Ruby">
```ruby
if $manual
  temp = ask("Please enter the temperature")
else
  temp = 20.0
end
if !$manual
  puts "Skipping infinite wait in auto mode"
else
  wait
end
```
</TabItem>
</Tabs>

When running suites, there is a checkbox at the top of the tool called “Manual” that affects this $manual variable directly.

### Outputting Extra Information to a Report

COSMOS Script Runner operating on a script suite automatically generates a report that shows the PASS/FAILED/SKIPPED state for each script. You can also inject arbitrary text into this report using the example as follows. Alternatively, you can simply use print text into the Script Runner message log.

Ruby:

```ruby
class MyGroup < OpenC3::Group
  def script_1
    # The following text will be placed in the report
    OpenC3::Group.puts "Verifies requirements 304, 306, 310"
    # This puts line will show up in the sr_messages log file
    puts "script_1 complete"
  end
end
```

Python:

```python
from openc3.script.suite import Group
class MyGroup(Group):
    def script_1():
        # The following text will be placed in the report
        Group.print("Verifies requirements 304, 306, 310")
        # This puts line will show up in the sr_messages log file
        print("script_1 complete")
```

### Getting the Most Recent Value of a Telemetry Point from Multiple Packets

Some systems include high rate data points with the same name in every packet. COSMOS supports getting the most recent value of a telemetry point that is in multiple packets using a special packet name of LATEST. Assume the target INST has two packets, PACKET1 and PACKET2. Both packets have a telemetry point called TEMP.

```ruby
# Get the value of TEMP from the most recently received PACKET1
value = tlm("INST PACKET1 TEMP")
# Get the value of TEMP from the most recently received PACKET2
value = tlm("INST PACKET2 TEMP")
# Get the value of TEMP from the most recently received PACKET1 or PACKET2
value = tlm("INST LATEST TEMP")
```

### Checking Every Single Sample of a Telemetry Point

When writing COSMOS scripts, checking the most recent value of a telemetry point normally gets the job done. The tlm(), tlm_raw(), etc methods all retrieve the most recent value of a telemetry point. Sometimes you need to perform analysis on every single sample of a telemetry point. This can be done using the COSMOS packet subscription system. The packet subscription system lets you choose one or more packets and receive them all from a queue. You can then pick out the specific telemetry points you care about from each packet.

Ruby:

```ruby
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
wait 1.5
id, packets = get_packets(id)
packets.each do |packet|
  puts "#{packet['PACKET_TIMESECONDS']}: #{packet['target_name']} #{packet['packet_name']}"
end
# Wait for some time later and reuse the last returned ID
id, packets = get_packets(id)
```

Python:

```python
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
wait(1.5)
id, packets = get_packets(id)
for packet in packets:
    print(f"{packet['PACKET_TIMESECONDS']}: {packet['target_name']} {packet['packet_name']}")
# Wait for some time later and reuse the last returned ID
id, packets = get_packets(id)
```

### Using Variables in Mnemonics

Because command and telemetry mnemonics are just strings in COSMOS scripts, you can make use of variables in some contexts to make reusable code. For example, a method can take a target name as an input to support multiple instances of a target. You could also pass in the value for a set of numbered telemetry points.

Ruby:

```ruby
def example(target_name, temp_number)
  cmd("#{target_name} COLLECT with TYPE NORMAL")
  wait_check("#{target_name} TEMP#{temp_number} > 50.0")
end
```

Python:

```python
def example(target_name, temp_number):
    cmd(f"{target_name} COLLECT with TYPE NORMAL")
    wait_check(f"{target_name} TEMP{temp_number} > 50.0")
```

This can also be useful when looping through a numbered set of telemetry points but be considerate of the downsides of looping as discussed in the [Looping vs Unrolled Loops](#looping-vs-unrolled-loops) section.

### Using Custom wait_check_expression

The COSMOS wait_check_expression (and check_expression) allow you to perform more complicated checks and still stop the script with a CHECK error message if something goes wrong. For example, you can check variables against each other or check a telemetry point against a range. The exact string of text passed to wait_check_expression is repeatedly evaluated until it passes, or a timeout occurs. It is important to not use string interpolation within the actual expression or the values inside of the string interpolation syntax will only be evaluated once when it is converted into a string.

Ruby:

```ruby
one = 1
two = 2

wait_check_expression("one == two", 1)
# ERROR: CHECK: one == two is FALSE after waiting 1.017035 seconds

# Checking an integer range
wait_check_expression("one > 0 and one < 10 # init value one = #{one}", 1)
```

Python:

```python
one = 1
two = 2

wait_check_expression("one == two", 1, 0.25, locals())
# ERROR: CHECK: one == two is FALSE after waiting 1.017035 seconds

# Checking an integer range
wait_check_expression("one > 0 and one < 10", 1, 0.25, locals())
```

### COSMOS Scripting Differences from Regular Ruby Scripting

#### Do not use single line if statements

COSMOS scripting instruments each line to catch exceptions if things go wrong. With single line if statements the exception handling doesn't know which part of the statement failed and cannot properly continue. If an exception is raised in a single line if statement, then the entire script will stop and not be able to continue. Do not use single line if statements in COSMOS scripts. (However, they are fine to use in interfaces and other Ruby code, just not COSMOS scripts).

Don't do this:

```ruby
run_method() if tlm("INST HEALTH_STATUS TEMP1") > 10.0
```

Do this instead:

```ruby
# It is best not to execute any code that could fail in an if statement, ie
# tlm() could fail if the CmdTlmServer was not running or a mnemonic
# was misspelled
temp1 = tlm("INST HEALTH_STATUS TEMP1")
if temp1 > 10.0
  run_method()
end
```

## When Things Go Wrong

### Common Reasons Checks Fail

There are three common reasons that checks fail in COSMOS scripts:

1. The delay given was too short

   The wait_check() method takes a timeout that indicates how long to wait for the referenced telemetry point to pass the check. The timeout needs to be large enough for the system under test to finish its action and for updated telemetry to be received. Note that the script will continue as soon as the check completes successfully. Thus, the only penalty for a longer timeout is the additional wait time in a failure condition.

2. The range or value checked against was incorrect or too stringent

   Often the actual telemetry value is ok, but the expected value checked against was too tight. Loosen the ranges on checks when it makes sense. Ensure your script is using the wait_check_tolerance() routine when checking floating point numbers and verify you're using an appropriate tolerance value.

3. The check really failed

   Of course, sometimes there are real failures. See the next section for how to handle them and recover.

### How to Recover from Anomalies

Once something has failed, and your script has stopped with a pink highlighted line, how can you recover? Fortunately, COSMOS provides several mechanisms that can be used to recover after something in your script fails.

1. Retry

   After a failure, the Script Runner “Pause” button changes to “Retry”. Clicking on the Retry button will re-execute the line the failed. For failures due to timing issues, this will often resolve the issue and allow the script to continue. Make note of the failure and be sure to update your script prior to the next run.

1. Use the Debug Prompt

   By selecting Script -> Toggle Debug, you can perform arbitrary actions that may be needed to correct the situation without stopping the running script. You can also inspect variables to help determine why something failed.

1. Execute Selection

   If only a small section of a script needs to be run, then “Execute Selection" can be used to execute only a small portion of the script. This can also be used when a script is paused or stopped in error.

1. Run from here

   By clicking into a script, and right clicking to select "Run from here", users can restart a script at an arbitrary point. This works well if no required variable definitions exist earlier in the script.

## Advanced Topics

### Advanced Script Configuration with CSV or Excel

Using a spreadsheet to store the values for use by a script can be a great option if you have a CM-controlled script but need to be able to tweak some values for a test or if you need to use different values for different serial numbers.

The Ruby CSV class be used to easily read data from CSV files (recommended for cross platform projects).

```ruby
require 'csv'
values = CSV.read('test.csv')
puts values[0][0]
```

If you are only using Windows, COSMOS also contains a library for reading Excel files.

```ruby
require 'openc3/win32/excel'
ss = ExcelSpreadsheet.new('C:/git/cosmos/test.xlsx')
puts ss[0][0][0]
```

### When to use Ruby Modules

Modules in Ruby have two purposes: namespacing and mixins. Namespacing allows having classes and methods with the same name, but with different meanings. For example, if they are namespaced, COSMOS can have a Packet class and another Ruby library can have a Packet class. This isn't typically useful for COSMOS scripting though.

Mixins allow adding common methods to classes without using inheritance. Mixins can be useful to add common functionality to some classes but not others, or to break up classes into multiple files.

```ruby
module MyModule
  def module_method
  end
end
class MyTest < OpenC3::Group
  include MyModule
  def test_1
    module_method()
  end
end
```
