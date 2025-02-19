---
title: Scripting API Guide
description: Scripting API methods, deprecations and migrations
sidebar_custom_props:
  myEmoji: 📝
---

This document provides the information necessary to write test procedures using the COSMOS scripting API. Scripting in COSMOS is designed to be simple and intuitive. The code completion ability for command and telemetry mnemonics makes Script Runner the ideal place to write your procedures, however any text editor will do. If there is functionality that you don't see here or perhaps an easier syntax for doing something, please submit a ticket.

## Concepts

### Programming Languages

COSMOS scripting is implemented using either Ruby or Python. Ruby and Python are very similar scripting languages and in many cases the COSMOS APIs are identical between the two. This guide is written to support both with additional language specific information found in the [Script Writing Guide](../guides/script-writing.md).

### Using Script Runner

Script Runner is a graphical application that provides the ideal environment for running and implementing your test procedures. The Script Runner tool is broken into 4 main sections. At the top of the tool is a menu bar that allows you to do such things as open and save files, perform a syntax check, and execute your script.

Next is a tool bar that displays the currently executing script and three buttons, "Start/Go", "Pause/Retry", and "Stop". The Start/Go button is used to start the script and continue past errors or waits. The Pause/Retry button will pause the executing script. If an error is encountered the Pause button changes to Retry to re-execute the errored line. Finally, the Stop button will stop the executing script at any time.

Third is the display of the actual script. While the script is not running, you may edit and compose scripts in this area. A handy code completion feature is provided that will list out the available commands or telemetry points as you are writing your script. Simply begin writing a cmd( or tlm( line to bring up code completion. This feature greatly reduces typos in command and telemetry mnemonics.

Finally, the bottom of the display is the log messages. All commands that are sent, errors that occur, and user print statements appear in this area.

### Telemetry Types

There are four different ways that telemetry values can be retrieved in COSMOS. The following chart explains their differences.

| Telemetry Type       | Description                                                                                                                                                                                                                                                                                                                  |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Raw                  | Raw telemetry is exactly as it is in the telemetry packet before any conversions. All telemetry items will have a raw value except for Derived telemetry points which have no real location in a packet. Requesting raw telemetry on a derived item will return nil.                                                         |
| Converted            | Converted telemetry is raw telemetry that has gone through a conversion factor such as a state conversion or a polynomial conversion. If a telemetry item does not have a conversion defined, then converted telemetry will be the same as raw telemetry. This is the most common type of telemety used in scripts.          |
| Formatted            | Formatted telemetry is converted telemetry that has gone through a printf style conversion into a string. Formatted telemetry will always have a string representation. If no format string is defined for a telemetry point, then formatted telemetry will be the same as converted telemetry except represented as string. |
| Formatted with Units | Formatted with Units telemetry is the same as Formatted telemetry except that a space and the units of the telemetry item are appended to the end of the string. If no units are defined for a telemetry item then this type is the same as Formatted telemetry.                                                             |

## Script Runner API

The following methods are designed to be used in Script Runner procedures. Many can also be used in custom built COSMOS tools. Please see the COSMOS Tool API section for methods that are more efficient to use in custom tools.

### Migration from COSMOS v5 to v6

The following API methods have been removed from COSMOS v6. Most of the deprecated API methods still remain for backwards compatibility.

| Method              | Tool                         | Status                             |
| ------------------- | ---------------------------- | ---------------------------------- |
| get_all_target_info | Command and Telemetry Server | Removed, use get_target_interfaces |
| play_wav_file       | Script Runner                | Removed                            |
| status_bar          | Script Runner                | Removed                            |

### Migration from COSMOS v4 to v5

The following API methods are either deprecated (will not be ported to COSMOS 5) or currently unimplemented (eventually will be ported to COSMOS 5):

| Method                                | Tool                         | Status                                                              |
| ------------------------------------- | ---------------------------- | ------------------------------------------------------------------- |
| clear                                 | Telemetry Viewer             | Deprecated, use clear_screen                                        |
| clear_all                             | Telemetry Viewer             | Deprecated, use clear_all_screens                                   |
| close_local_screens                   | Telemetry Viewer             | Deprecated, use clear_screen                                        |
| clear_disconnected_targets            | Script Runner                | Deprecated                                                          |
| cmd_tlm_clear_counters                | Command and Telemetry Server | Deprecated                                                          |
| cmd_tlm_reload                        | Command and Telemetry Server | Deprecated                                                          |
| display                               | Telemetry Viewer             | Deprecated, use display_screen                                      |
| get_all_packet_logger_info            | Command and Telemetry Server | Deprecated                                                          |
| get_all_target_info                   | Command and Telemetry Server | Deprecated, use get_target_interfaces                               |
| get_background_tasks                  | Command and Telemetry Server | Deprecated                                                          |
| get_all_cmd_info                      | Command and Telemetry Server | Deprecated, use get_all_cmds                                        |
| get_all_tlm_info                      | Command and Telemetry Server | Deprecated, use get_all_tlm                                         |
| get_cmd_list                          | Command and Telemetry Server | Deprecated, use get_all_cmds                                        |
| get_cmd_log_filename                  | Command and Telemetry Server | Deprecated                                                          |
| get_cmd_param_list                    | Command and Telemetry Server | Deprecated, use get_cmd                                             |
| get_cmd_tlm_disconnect                | Script Runner                | Deprecated, use $disconnect                                         |
| get_disconnected_targets              | Script Runner                | Unimplemented                                                       |
| get_interface_info                    | Command and Telemetry Server | Deprecated, use get_interface                                       |
| get_interface_targets                 | Command and Telemetry Server | Deprecated                                                          |
| get_output_logs_filenames             | Command and Telemetry Server | Deprecated                                                          |
| get_packet                            | Command and Telemetry Server | Deprecated, use get_packets                                         |
| get_packet_data                       | Command and Telemetry Server | Deprecated, use get_packets                                         |
| get_packet_logger_info                | Command and Telemetry Server | Deprecated                                                          |
| get_packet_loggers                    | Command and Telemetry Server | Deprecated                                                          |
| get_replay_mode                       | Replay                       | Deprecated                                                          |
| get_router_info                       | Command and Telemetry Server | Deprecated, use get_router                                          |
| get_scriptrunner_message_log_filename | Command and Telemetry Server | Deprecated                                                          |
| get_server_message                    | Command and Telemetry Server | Deprecated                                                          |
| get_server_message_log_filename       | Command and Telemetry Server | Deprecated                                                          |
| get_server_status                     | Command and Telemetry Server | Deprecated                                                          |
| get_stale                             | Command and Telemetry Server | Deprecated                                                          |
| get_target_ignored_items              | Command and Telemetry Server | Deprecated, use get_target                                          |
| get_target_ignored_parameters         | Command and Telemetry Server | Deprecated, use get_target                                          |
| get_target_info                       | Command and Telemetry Server | Deprecated, use get_target                                          |
| get_target_list                       | Command and Telemetry Server | Deprecated, use get_target_names                                    |
| get_tlm_details                       | Command and Telemetry Server | Deprecated                                                          |
| get_tlm_item_list                     | Command and Telemetry Server | Deprecated                                                          |
| get_tlm_list                          | Command and Telemetry Server | Deprecated                                                          |
| get_tlm_log_filename                  | Command and Telemetry Server | Deprecated                                                          |
| interface_state                       | Command and Telemetry Server | Deprecated, use get_interface                                       |
| override_tlm_raw                      | Command and Telemetry Server | Deprecated, use override_tlm                                        |
| open_directory_dialog                 | Script Runner                | Deprecated                                                          |
| play_wav_file                         | Script Runner                | Deprecated                                                          |
| replay_move_end                       | Replay                       | Deprecated                                                          |
| replay_move_index                     | Replay                       | Deprecated                                                          |
| replay_move_start                     | Replay                       | Deprecated                                                          |
| replay_play                           | Replay                       | Deprecated                                                          |
| replay_reverse_play                   | Replay                       | Deprecated                                                          |
| replay_select_file                    | Replay                       | Deprecated                                                          |
| replay_set_playback_delay             | Replay                       | Deprecated                                                          |
| replay_status                         | Replay                       | Deprecated                                                          |
| replay_step_back                      | Replay                       | Deprecated                                                          |
| replay_step_forward                   | Replay                       | Deprecated                                                          |
| replay_stop                           | Replay                       | Deprecated                                                          |
| require_utility                       | Script Runner                | Deprecated but exists for backwards compatibility, use load_utility |
| router_state                          | Command and Telemetry Server | Deprecated, use get_router                                          |
| save_file_dialog                      | Script Runner                | Deprecated                                                          |
| save_setting                          | Command and Telemetry Server | Deprecated but exists for backwards compatibility, use set_setting  |
| set_cmd_tlm_disconnect                | Script Runner                | Deprecated, use disconnect_script                                   |
| set_disconnected_targets              | Script Runner                | Unimplemented                                                       |
| set_replay_mode                       | Replay                       | Deprecated                                                          |
| set_stdout_max_lines                  | Script Runner                | Deprecated                                                          |
| set_tlm_raw                           | Script Runner                | Deprecated, use set_tlm                                             |
| show_backtrace                        | Script Runner                | Deprecated, backtrace always shown                                  |
| status_bar                            | Script Runner                | Deprecated                                                          |
| shutdown_cmd_tlm                      | Command and Telemetry Server | Deprecated                                                          |
| start_cmd_log                         | Command and Telemetry Server | Deprecated                                                          |
| start_logging                         | Command and Telemetry Server | Deprecated                                                          |
| start_new_scriptrunner_message_log    | Command and Telemetry Server | Deprecated                                                          |
| start_new_server_message_log          | Command and Telemetry Server | Deprecated                                                          |
| start_tlm_log                         | Command and Telemetry Server | Deprecated                                                          |
| stop_background_task                  | Command and Telemetry Server | Deprecated                                                          |
| stop_cmd_log                          | Command and Telemetry Server | Deprecated                                                          |
| stop_logging                          | Command and Telemetry Server | Deprecated                                                          |
| stop_tlm_log                          | Command and Telemetry Server | Deprecated                                                          |
| subscribe_limits_events               | Command and Telemetry Server | Deprecated                                                          |
| subscribe_packet_data                 | Command and Telemetry Server | Deprecated, use subscribe_packets                                   |
| subscribe_server_messages             | Command and Telemetry Server | Unimplemented                                                       |
| tlm_variable                          | Script Runner                | Deprecated, use tlm() and pass type                                 |
| unsubscribe_limits_events             | Command and Telemetry Server | Deprecated                                                          |
| unsubscribe_packet_data               | Command and Telemetry Server | Deprecated                                                          |
| unsubscribe_server_messages           | Command and Telemetry Server | Deprecated                                                          |
| wait_raw                              | Script Runner                | Deprecated, use wait(..., type: :RAW)                               |
| wait_check_raw                        | Script Runner                | Deprecated, use wait_check(..., type: :RAW)                         |
| wait_tolerance_raw                    | Script Runner                | Deprecated, use wait_tolerance(..., type: :RAW)                     |
| wait_check_tolerance_raw              | Script Runner                | Deprecated, use wait_check_tolerance(..., type: :RAW)               |

## Retrieving User Input

These methods allow the user to enter values that are needed by the script.

### ask

Prompts the user for input with a question. User input is automatically converted from a string to the appropriate data type. For example if the user enters "1", the number 1 as an integer will be returned.

Ruby / Python Syntax:

```ruby
ask("<question>", <Blank or Default>, <Password>)
```

| Parameter        | Description                                                                                                                             |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| question         | Question to prompt the user with.                                                                                                       |
| Blank or Default | Whether or not to allow empty responses (optional - defaults to false). If a non-boolean value is passed it is used as a default value. |
| Password         | Whether to treat the entry as a password which is displayed with dots and not logged. Default is false.                                 |

Ruby Example:

```ruby
value = ask("Enter an integer")
value = ask("Enter a value or nothing", true)
value = ask("Enter a value", 10)
password = ask("Enter your password", false, true)
```

Python Example:

```python
value = ask("Enter an integer")
value = ask("Enter a value or nothing", True)
value = ask("Enter a value", 10)
password = ask("Enter your password", False, True)
```

### ask_string

Prompts the user for input with a question. User input is always returned as a string. For example if the user enters "1", the string "1" will be returned.

Ruby / Python Syntax:

```ruby
ask_string("<question>", <Blank or Default>, <Password>)
```

| Parameter        | Description                                                                                                                             |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| question         | Question to prompt the user with.                                                                                                       |
| Blank or Default | Whether or not to allow empty responses (optional - defaults to false). If a non-boolean value is passed it is used as a default value. |
| Password         | Whether to treat the entry as a password which is displayed with dots and not logged. Default is false.                                 |

Ruby Example:

```ruby
string = ask_string("Enter a String")
string = ask_string("Enter a value or nothing", true)
string = ask_string("Enter a value", "test")
password = ask_string("Enter your password", false, true)
```

Python Example:

```python
string = ask_string("Enter a String")
string = ask_string("Enter a value or nothing", True)
string = ask_string("Enter a value", "test")
password = ask_string("Enter your password", False, True)
```

### message_box

### vertical_message_box

### combo_box

The message_box, vertical_message_box, and combo_box methods create a message box with arbitrary buttons or selections that the user can click. The text of the button clicked is returned.

Ruby / Python Syntax:

```ruby
message_box("<Message>", "<button text 1>", ...)
vertical_message_box("<Message>", "<button text 1>", ...)
combo_box("<Message>", "<selection text 1>", ...)
```

| Parameter             | Description                      |
| --------------------- | -------------------------------- |
| Message               | Message to prompt the user with. |
| Button/Selection Text | Text for a button or selection   |

Ruby Example:

```ruby
value = message_box("Select the sensor number", 'One', 'Two')
value = vertical_message_box("Select the sensor number", 'One', 'Two')
value = combo_box("Select the sensor number", 'One', 'Two')
case value
when 'One'
  puts 'Sensor One'
when 'Two'
  puts 'Sensor Two'
end
```

Python Example:

```python
value = message_box("Select the sensor number", 'One', 'Two')
value = vertical_message_box("Select the sensor number", 'One', 'Two')
value = combo_box("Select the sensor number", 'One', 'Two')
match value:
    case 'One':
        print('Sensor One')
    case 'Two':
        print('Sensor Two')
```

### get_target_file

Return a file handle to a file in the target directory

Ruby Syntax:

```ruby
get_target_file("<File Path>", original: false)
```

Python Syntax:

```ruby
get_target_file("<File Path>", original=False)
```

| Parameter | Description                                                                                                                                                                                                                           |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| File Path | The path to the file in the target directory. Should assume to start with a TARGET name, e.g. INST/procedures/proc.rb                                                                                                                 |
| original  | Whether to get the original file from the plug-in, or any modifications to the file. Default is false which means to grab the modified file. If the modified file does not exist the API will automatically try to pull the original. |

Ruby Example:

```ruby
file = get_target_file("INST/data/attitude.bin")
puts file.read().formatted # format a binary file
file.unlink # delete file
file = get_target_file("INST/procedures/checks.rb", original: true)
puts file.read()
file.unlink # delete file
```

Python Example:

```python
from openc3.utilities.string import formatted

file = get_target_file("INST/data/attitude.bin")
print(formatted(file.read())) # format a binary file
file.close() # delete file
file = get_target_file("INST/procedures/checks.rb", original=True)
print(file.read())
file.close() # delete file
```

### put_target_file

Writes a file to the target directory

Ruby or Python Syntax:

```ruby
put_target_file("<File Path>", "IO or String")
```

| Parameter    | Description                                                                                                                                                                                                                                                                      |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| File Path    | The path to the file in the target directory. Should assume to start with a TARGET name, e.g. INST/procedures/proc.rb. The file can previously exist or not. Note: The original file from the plug-in will not be modified, however existing modified files will be overwritten. |
| IO or String | The data can be an IO object or String                                                                                                                                                                                                                                           |

Ruby Example:

```ruby
put_target_file("INST/test1.txt", "this is a string test")
file = Tempfile.new('test')
file.write("this is a Io test")
file.rewind
put_target_file("INST/test2.txt", file)
put_target_file("INST/test3.bin", "\x00\x01\x02\x03\xFF\xEE\xDD\xCC") # binary
```

Python Example:

```python
put_target_file("INST/test1.txt", "this is a string test")
file = tempfile.NamedTemporaryFile(mode="w+t")
file.write("this is a Io test")
file.seek(0)
put_target_file("INST/test2.txt", file)
put_target_file("INST/test3.bin", b"\x00\x01\x02\x03\xFF\xEE\xDD\xCC") # binary
```

### delete_target_file

Delete a file in the target directory

Ruby / Python Syntax:

```ruby
delete_target_file("<File Path>")
```

| Parameter | Description                                                                                                                                                                                                                                   |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| File Path | The path to the file in the target directory. Should assume to start with a TARGET name, e.g. INST/procedures/proc.rb. Note: Only files created with put_target_file can be deleted. Original files from the plugin installation will remain. |

Ruby / Python Example:

```ruby
put_target_file("INST/delete_me.txt", "to be deleted")
delete_target_file("INST/delete_me.txt")
```

### open_file_dialog

### open_files_dialog

The open_file_dialog and open_files_dialog methods create a file dialog box so the user can select a single or multiple files. The selected file(s) is returned.

Note: COSMOS 5 has deprecated the save_file_dialog and open_directory_dialog methods. save_file_dialog can be replaced by put_target_file if you want to write a file back to the target. open_directory_dialog doesn't make sense in new architecture so you must request individual files.

Ruby Syntax:

```ruby
open_file_dialog("<Title>", "<Message>", filter: "<filter>")
open_files_dialog("<Title>", "<Message>", filter: "<filter>")
```

Python Syntax:

```python
open_file_dialog("<Title>", "<Message>", filter="<filter>")
open_files_dialog("<Title>", "<Message>", filter="<filter>")
```

| Parameter | Description                                                                                                                                                                                                                        |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Title     | The title to put on the dialog. Required.                                                                                                                                                                                          |
| Message   | The message to display in the dialog box. Optional parameter.                                                                                                                                                                      |
| filter    | Named parameter to filter allowed file types. Optional parameter, specified as comma delimited file types, e.g. ".txt,.doc". See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input/file#accept for more information. |

Ruby Example:

```ruby
file = open_file_dialog("Open a single file", "Choose something interesting", filter: ".txt")
puts file # Ruby File object
puts file.read
file.delete

files = open_files_dialog("Open multiple files") # message is optional
puts files # Array of File objects (even if you select only one)
files.each do |file|
  puts file
  puts file.read
  file.delete
end
```

Python Example:

```python
file = open_file_dialog("Open a single file", "Choose something interesting", filter=".txt")
print(file)
print(file.read())
file.close()

files = open_files_dialog("Open multiple files") # message is optional
print(files) # Array of File objects (even if you select only one)
for file in files:
    print(file)
    print(file.read())
    file.close()
```

## Providing information to the user

These methods notify the user that something has occurred.

### prompt

Displays a message to the user and waits for them to press an ok button.

Ruby / Python Syntax:

```ruby
prompt("<Message>")
```

| Parameter | Description                      |
| --------- | -------------------------------- |
| Message   | Message to prompt the user with. |

Ruby / Python Example:

```ruby
prompt("Press OK to continue")
```

## Commands

These methods provide capability to send commands to a target and receive information about commands in the system.

### cmd

Sends a specified command.

Ruby Syntax:

```ruby
cmd("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd("<Target Name>", "<Command Name>", "Param #1 Name" => <Param #1 Value>, "Param #2 Name" => <Param #2 Value>, ...)
```

Python Syntax:

```python
cmd("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd("<Target Name>", "<Command Name>", {"Param #1 Name": <Param #1 Value>, "Param #2 Name": <Param #2 Value>, ...})
```

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target this command is associated with.                                                  |
| Command Name   | Name of this command. Also referred to as its mnemonic.                                              |
| Param #x Name  | Name of a command parameter. If there are no parameters then the 'with' keyword should not be given. |
| Param #x Value | Value of the command parameter. Values are automatically converted to the appropriate type.          |
| timeout        | Optional named parameter to change the default timeout value of 5 seconds                            |
| log_message    | Optional named parameter to prevent logging of the command                                           |

Ruby Example:

```ruby
cmd("INST COLLECT with DURATION 10, TYPE NORMAL")
# In Ruby the brackets around parameters are optional
cmd("INST", "COLLECT", "DURATION" => 10, "TYPE" => "NORMAL")
cmd("INST", "COLLECT", { "DURATION" => 10, "TYPE" => "NORMAL" })
cmd("INST ABORT", timeout: 10, log_message: false)
```

Python Example:

```python
cmd("INST COLLECT with DURATION 10, TYPE NORMAL")
cmd("INST", "COLLECT", { "DURATION": 10, "TYPE": "NORMAL" })
cmd("INST ABORT", timeout=10, log_message=False)
```

### cmd_no_range_check

Sends a specified command without performing range checking on its parameters. This should only be used when it is necessary to intentionally send a bad command parameter to test a target.

Ruby Syntax:

```ruby
cmd_no_range_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_range_check("<Target Name>", "<Command Name>", "Param #1 Name" => <Param #1 Value>, "Param #2 Name" => <Param #2 Value>, ...)
```

Python Syntax:

```python
cmd_no_range_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_range_check("<Target Name>", "<Command Name>", {"Param #1 Name": <Param #1 Value>, "Param #2 Name": <Param #2 Value>, ...})
```

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target this command is associated with.                                                  |
| Command Name   | Name of this command. Also referred to as its mnemonic.                                              |
| Param #x Name  | Name of a command parameter. If there are no parameters then the 'with' keyword should not be given. |
| Param #x Value | Value of the command parameter. Values are automatically converted to the appropriate type.          |
| timeout        | Optional named parameter to change the default timeout value of 5 seconds                            |
| log_message    | Optional named parameter to prevent logging of the command                                           |

Ruby Example:

```ruby
cmd_no_range_check("INST COLLECT with DURATION 11, TYPE NORMAL")
cmd_no_range_check("INST", "COLLECT", "DURATION" => 11, "TYPE" => "NORMAL")
```

Python Example:

```python
cmd_no_range_check("INST COLLECT with DURATION 11, TYPE NORMAL")
cmd_no_range_check("INST", "COLLECT", {"DURATION": 11, "TYPE": "NORMAL"})
```

### cmd_no_hazardous_check

Sends a specified command without performing the notification if it is a hazardous command. This should only be used when it is necessary to fully automate testing involving hazardous commands.

Ruby Syntax:

```ruby
cmd_no_hazardous_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_hazardous_check("<Target Name>", "<Command Name>", "Param #1 Name" => <Param #1 Value>, "Param #2 Name" => <Param #2 Value>, ...)
```

Python Syntax:

```python
cmd_no_hazardous_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_hazardous_check("<Target Name>", "<Command Name>", {"Param #1 Name": <Param #1 Value>, "Param #2 Name": <Param #2 Value>, ...})
```

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target this command is associated with.                                                  |
| Command Name   | Name of this command. Also referred to as its mnemonic.                                              |
| Param #x Name  | Name of a command parameter. If there are no parameters then the 'with' keyword should not be given. |
| Param #x Value | Value of the command parameter. Values are automatically converted to the appropriate type.          |
| timeout        | Optional named parameter to change the default timeout value of 5 seconds                            |
| log_message    | Optional named parameter to prevent logging of the command                                           |

Ruby / Python Example:

```ruby
cmd_no_hazardous_check("INST CLEAR")
cmd_no_hazardous_check("INST", "CLEAR")
```

### cmd_no_checks

Sends a specified command without performing the parameter range checks or notification if it is a hazardous command. This should only be used when it is necessary to fully automate testing involving hazardous commands that intentionally have invalid parameters.

Ruby Syntax:

```ruby
cmd_no_checks("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_checks("<Target Name>", "<Command Name>", "Param #1 Name" => <Param #1 Value>, "Param #2 Name" => <Param #2 Value>, ...)
```

Python Syntax:

```python
cmd_no_checks("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_no_checks("<Target Name>", "<Command Name>", {"Param #1 Name": <Param #1 Value>, "Param #2 Name": <Param #2 Value>, ...})
```

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target this command is associated with.                                                  |
| Command Name   | Name of this command. Also referred to as its mnemonic.                                              |
| Param #x Name  | Name of a command parameter. If there are no parameters then the 'with' keyword should not be given. |
| Param #x Value | Value of the command parameter. Values are automatically converted to the appropriate type.          |
| timeout        | Optional named parameter to change the default timeout value of 5 seconds                            |
| log_message    | Optional named parameter to prevent logging of the command                                           |

Ruby Example:

```ruby
cmd_no_checks("INST COLLECT with DURATION 11, TYPE SPECIAL")
cmd_no_checks("INST", "COLLECT", "DURATION" => 11, "TYPE" => "SPECIAL")
```

Python Example:

```python
cmd_no_checks("INST COLLECT with DURATION 11, TYPE SPECIAL")
cmd_no_checks("INST", "COLLECT", {"DURATION": 11, "TYPE": "SPECIAL"})
```

### cmd_raw

Sends a specified command without running conversions.

Ruby Syntax:

```ruby
cmd_raw("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw("<Target Name>", "<Command Name>", "<Param #1 Name>" => <Param #1 Value>, "<Param #2 Name>" => <Param #2 Value>, ...)
```

Python Syntax:

```python
cmd_raw("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw("<Target Name>", "<Command Name>", {"<Param #1 Name>": <Param #1 Value>, "<Param #2 Name>": <Param #2 Value>, ...})
```

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target this command is associated with.                                                  |
| Command Name   | Name of this command. Also referred to as its mnemonic.                                              |
| Param #x Name  | Name of a command parameter. If there are no parameters then the 'with' keyword should not be given. |
| Param #x Value | Value of the command parameter. Values are automatically converted to the appropriate type.          |
| timeout        | Optional named parameter to change the default timeout value of 5 seconds                            |
| log_message    | Optional named parameter to prevent logging of the command                                           |

Ruby Example:

```ruby
cmd_raw("INST COLLECT with DURATION 10, TYPE 0")
cmd_raw("INST", "COLLECT", "DURATION" => 10, "TYPE" => 0)
```

Python Example:

```python
cmd_raw("INST COLLECT with DURATION 10, TYPE 0")
cmd_raw("INST", "COLLECT", {"DURATION": 10, "TYPE": 0})
```

### cmd_raw_no_range_check

Sends a specified command without running conversions or performing range checking on its parameters. This should only be used when it is necessary to intentionally send a bad command parameter to test a target.

Ruby Syntax:

```ruby
cmd_raw_no_range_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_range_check("<Target Name>", "<Command Name>", "<Param #1 Name>" => <Param #1 Value>, "<Param #2 Name>" => <Param #2 Value>, ...)
```

Python Syntax:

```python
cmd_raw_no_range_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_range_check("<Target Name>", "<Command Name>", {"<Param #1 Name>": <Param #1 Value>, "<Param #2 Name>": <Param #2 Value>, ...})
```

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target this command is associated with.                                                  |
| Command Name   | Name of this command. Also referred to as its mnemonic.                                              |
| Param #x Name  | Name of a command parameter. If there are no parameters then the 'with' keyword should not be given. |
| Param #x Value | Value of the command parameter. Values are automatically converted to the appropriate type.          |
| timeout        | Optional named parameter to change the default timeout value of 5 seconds                            |
| log_message    | Optional named parameter to prevent logging of the command                                           |

Ruby Example:

```ruby
cmd_raw_no_range_check("INST COLLECT with DURATION 11, TYPE 0")
cmd_raw_no_range_check("INST", "COLLECT", "DURATION" => 11, "TYPE" => 0)
```

Python Example:

```python
cmd_raw_no_range_check("INST COLLECT with DURATION 11, TYPE 0")
cmd_raw_no_range_check("INST", "COLLECT", {"DURATION": 11, "TYPE": 0})
```

### cmd_raw_no_hazardous_check

Sends a specified command without running conversions or performing the notification if it is a hazardous command. This should only be used when it is necessary to fully automate testing involving hazardous commands.

Ruby Syntax:

```ruby
cmd_raw_no_hazardous_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_hazardous_check("<Target Name>", "<Command Name>", "<Param #1 Name>" => <Param #1 Value>, "<Param #2 Name>" => <Param #2 Value>, ...)
```

Python Syntax:

```python
cmd_raw_no_hazardous_check("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_hazardous_check("<Target Name>", "<Command Name>", {"<Param #1 Name>": <Param #1 Value>, "<Param #2 Name>": <Param #2 Value>, ...})
```

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target this command is associated with.                                                  |
| Command Name   | Name of this command. Also referred to as its mnemonic.                                              |
| Param #x Name  | Name of a command parameter. If there are no parameters then the 'with' keyword should not be given. |
| Param #x Value | Value of the command parameter. Values are automatically converted to the appropriate type.          |
| timeout        | Optional named parameter to change the default timeout value of 5 seconds                            |
| log_message    | Optional named parameter to prevent logging of the command                                           |

Ruby / Python Example:

```ruby
cmd_raw_no_hazardous_check("INST CLEAR")
cmd_raw_no_hazardous_check("INST", "CLEAR")
```

### cmd_raw_no_checks

Sends a specified command without running conversions or performing the parameter range checks or notification if it is a hazardous command. This should only be used when it is necessary to fully automate testing involving hazardous commands that intentionally have invalid parameters.

Ruby Syntax:

```ruby
cmd_raw_no_checks("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_checks("<Target Name>", "<Command Name>", "<Param #1 Name>" => <Param #1 Value>, "<Param #2 Name>" => <Param #2 Value>, ...)
```

Python Syntax:

```python
cmd_raw_no_checks("<Target Name> <Command Name> with <Param #1 Name> <Param #1 Value>, <Param #2 Name> <Param #2 Value>, ...")
cmd_raw_no_checks("<Target Name>", "<Command Name>", {"<Param #1 Name>": <Param #1 Value>, "<Param #2 Name>": <Param #2 Value>, ...})
```

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target this command is associated with.                                                  |
| Command Name   | Name of this command. Also referred to as its mnemonic.                                              |
| Param #x Name  | Name of a command parameter. If there are no parameters then the 'with' keyword should not be given. |
| Param #x Value | Value of the command parameter. Values are automatically converted to the appropriate type.          |
| timeout        | Optional named parameter to change the default timeout value of 5 seconds                            |
| log_message    | Optional named parameter to prevent logging of the command                                           |

Ruby Example:

```ruby
cmd_raw_no_checks("INST COLLECT with DURATION 11, TYPE 1")
cmd_raw_no_checks("INST", "COLLECT", "DURATION" => 11, "TYPE" => 1)
```

Python Example:

```python
cmd_raw_no_checks("INST COLLECT with DURATION 11, TYPE 1")
cmd_raw_no_checks("INST", "COLLECT", {"DURATION": 11, "TYPE": 1})
```

### build_cmd

> Since 5.13.0, since 5.8.0 as build_command

Builds a command binary string so you can see the raw bytes for a given command. Use the [get_cmd](#get_cmd) to get information about a command like endianness, description, items, etc.

Ruby Syntax:

```ruby
build_cmd(<ARGS>, range_check: true, raw: false)
```

Python Syntax:

```python
build_cmd(<ARGS>, range_check=True, raw=False)
```

| Parameter   | Description                                                                             |
| ----------- | --------------------------------------------------------------------------------------- |
| ARGS        | Command parameters (see cmd)                                                            |
| range_check | Whether to perform range checking on the command. Default is true.                      |
| raw         | Whether to write the command arguments as RAW or CONVERTED value. Default is CONVERTED. |

Ruby Example:

```ruby
x = build_cmd("INST COLLECT with DURATION 10, TYPE NORMAL")
puts x  #=> {"id"=>"1696437370872-0", "result"=>"SUCCESS", "time"=>"1696437370872305961", "received_time"=>"1696437370872305961", "target_name"=>"INST", "packet_name"=>"COLLECT", "received_count"=>"3", "buffer"=>"\x13\xE7\xC0\x00\x00\f\x00\x01\x00\x00A \x00\x00\xAB\x00\x00\x00\x00"}
```

Python Example:

```python
x = build_cmd("INST COLLECT with DURATION 10, TYPE NORMAL")
print(x)  #=> {'id': '1697298167748-0', 'result': 'SUCCESS', 'time': '1697298167749155717', 'received_time': '1697298167749155717', 'target_name': 'INST', 'packet_name': 'COLLECT', 'received_count': '2', 'buffer': bytearray(b'\x13\xe7\xc0\x00\x00\x0c\x00\x01\x00\x00A \x00\x00\xab\x00\x00\x00\x00')}
```

### enable_cmd

> Since 5.15.1

Enables a disabled command. Sending a disabled command raises `DisabledError` with a message like 'INST ABORT is Disabled'.

Ruby / Python Syntax:

```ruby
buffer = enable_cmd("<Target Name> <Command Name>")
buffer = enable_cmd("<Target Name>", "<Command Name>")
```

| Parameter   | Description                   |
| ----------- | ----------------------------- |
| Target Name | Name of the target.           |
| Packet Name | Name of the command (packet). |

Ruby / Python Example:

```ruby
enable_cmd("INST ABORT")
```

### disable_cmd

> Since 5.15.1

Disables a command. Sending a disabled command raises `DisabledError` with a message like 'INST ABORT is Disabled'.

Ruby / Python Syntax:

```ruby
buffer = disable_cmd("<Target Name> <Command Name>")
buffer = disable_cmd("<Target Name>", "<Command Name>")
```

| Parameter   | Description                   |
| ----------- | ----------------------------- |
| Target Name | Name of the target.           |
| Packet Name | Name of the command (packet). |

Ruby / Python Example:

```ruby
disable_cmd("INST ABORT")
```

### send_raw

Sends raw data on an interface.

Ruby / Python Syntax:

```ruby
send_raw(<Interface Name>, <Data>)
```

| Parameter      | Description                                    |
| -------------- | ---------------------------------------------- |
| Interface Name | Name of the interface to send the raw data on. |
| Data           | Raw ruby string of data to send.               |

Ruby / Python Example:

```ruby
send_raw("INST_INT", data)
```

### get_all_cmds

> Since 5.13.0, since 5.0.0 as get_all_commands

Returns an array of the commands that are available for a particular target. The returned array is an array of hashes / list of dicts which fully describe the command packet.

Ruby / Python Syntax:

```ruby
get_all_cmds("<Target Name>")
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Target Name | Name of the target. |

Ruby Example:

```ruby
cmd_list = get_all_cmds("INST")
puts cmd_list  #=>
# [{"target_name"=>"INST",
#   "packet_name"=>"ABORT",
#   "endianness"=>"BIG_ENDIAN",
#   "description"=>"Aborts a collect on the instrument",
#   "items"=> [{"name"=>"CCSDSVER", "bit_offset"=>0, "bit_size"=>3, ... }]
# ...
# }]
```

Python Example:

```python
cmd_list = get_all_cmds("INST")
print(cmd_list)  #=>
# [{'target_name': 'INST',
#   'packet_name': 'ABORT',
#   'endianness': 'BIG_ENDIAN',
#   'description': 'Aborts a collect on the INST instrument',
#   'items': [{'name': 'CCSDSVER', 'bit_offset': 0, 'bit_size': 3, ... }]
# ...
# }]
```

### get_all_cmd_names

> Since 5.13.0, since 5.0.6 as get_all_command_names

Returns an array of the command names for a particular target.

Ruby / Python Syntax:

```ruby
get_all_cmd_names("<Target Name>")
```

| Parameter   | Description        |
| ----------- | ------------------ |
| Target Name | Name of the target |

Ruby Example:

```ruby
cmd_list = get_all_cmd_names("INST")
puts cmd_list  #=> ['ABORT', 'ARYCMD', 'ASCIICMD', ...]
```

Python Example:

```python
cmd_list = get_all_cmd_names("INST")
print(cmd_list)  #=> ['ABORT', 'ARYCMD', 'ASCIICMD', ...]
```

### get_cmd

> Since 5.13.0, since 5.0.0 as get_command

Returns a command hash which fully describes the command packet. To get the binary buffer of an as-built command use [build_cmd](#build_cmd).

Ruby / Python Syntax:

```ruby
get_cmd("<Target Name> <Packet Name>")
get_cmd("<Target Name>", "<Packet Name>")
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Target Name | Name of the target. |
| Packet Name | Name of the packet. |

Ruby / Python Example:

```ruby
abort_cmd = get_cmd("INST ABORT")
puts abort_cmd  #=>
# [{"target_name"=>"INST",
#   "packet_name"=>"ABORT",
#   "endianness"=>"BIG_ENDIAN",
#   "description"=>"Aborts a collect on the instrument",
#   "items"=> [{"name"=>"CCSDSVER", "bit_offset"=>0, "bit_size"=>3, ... }]
# ...
# }]
```

Python Example:

```python
abort_cmd = get_cmd("INST ABORT")
print(abort_cmd)  #=>
# [{'target_name': 'INST',
#   'packet_name': 'ABORT',
#   'endianness': 'BIG_ENDIAN',
#   'description': 'Aborts a collect on the INST instrument',
#   'items': [{'name': 'CCSDSVER', 'bit_offset': 0, 'bit_size': 3, ... }]
# ...
# }]
```

### get_param

> Since 5.13.0, since 5.0.0 as get_parameter

Returns a hash of the given command parameter

Ruby / Python Syntax:

```ruby
get_param("<Target Name> <Command Name> <Parameter Name>")
get_param("<Target Name>", "<Command Name>", "<Parameter Name>")
```

| Parameter      | Description            |
| -------------- | ---------------------- |
| Target Name    | Name of the target.    |
| Command Name   | Name of the command.   |
| Parameter Name | Name of the parameter. |

Ruby Example:

```ruby
param = get_param("INST COLLECT TYPE")
puts param  #=>
# {"name"=>"TYPE", "bit_offset"=>64, "bit_size"=>16, "data_type"=>"UINT",
#  "description"=>"Collect type which can be normal or special", "default"=>0,
#  "minimum"=>0, "maximum"=>65535, "endianness"=>"BIG_ENDIAN", "required"=>true, "overflow"=>"ERROR",
#  "states"=>{"NORMAL"=>{"value"=>0}, "SPECIAL"=>{"value"=>1, "hazardous"=>""}}, "limits"=>{}}
```

Python Example:

```python
param = get_param("INST COLLECT TYPE")
print(param)  #=>
# {'name': 'TYPE', 'bit_offset': 64, 'bit_size': 16, 'data_type': 'UINT',
#  'description': 'Collect type which can be normal or special', 'default': 0,
#  'minimum': 0, 'maximum': 65535, 'endianness': 'BIG_ENDIAN', 'required': True, 'overflow': 'ERROR',
#  'states': {'NORMAL': {'value': 0}, 'SPECIAL': {'value': 1, 'hazardous': ''}}, 'limits': {}}
```

### get_cmd_buffer

Returns a packet hash (similar to get_cmd) along with the raw packet buffer as a Ruby string.

Ruby / Python Syntax:

```ruby
buffer = get_cmd_buffer("<Target Name> <Packet Name>")['buffer']
buffer = get_cmd_buffer("<Target Name>", "<Packet Name>")['buffer']
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Target Name | Name of the target. |
| Packet Name | Name of the packet. |

Ruby Example:

```ruby
packet = get_cmd_buffer("INST COLLECT")
puts packet  #=>
# {"time"=>"1697298846752053420", "received_time"=>"1697298846752053420",
#  "target_name"=>"INST", "packet_name"=>"COLLECT", "received_count"=>"20", "stored"=>"false",
#  "buffer"=>"\x13\xE7\xC0\x00\x00\f\x00\x01\x00\x00@\xE0\x00\x00\xAB\x00\x00\x00\x00"}
```

Python Example:

```python
packet = get_cmd_buffer("INST COLLECT")
print(packet)  #=>
# {'time': '1697298923745982470', 'received_time': '1697298923745982470',
#  'target_name': 'INST', 'packet_name': 'COLLECT', 'received_count': '21', 'stored': 'false',
#  'buffer': bytearray(b'\x13\xe7\xc0\x00\x00\x0c\x00\x01\x00\x00@\xe0\x00\x00\xab\x00\x00\x00\x00')}
```

### get_cmd_hazardous

Returns true/false indicating whether a particular command is flagged as hazardous.

Ruby / Python Syntax:

```ruby
get_cmd_hazardous("<Target Name>", "<Command Name>", <Command Params - optional>)
```

| Parameter      | Description                                                                                                                   |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target.                                                                                                           |
| Command Name   | Name of the command.                                                                                                          |
| Command Params | Hash of the parameters given to the command (optional). Note that some commands are only hazardous based on parameter states. |

Ruby Example:

```ruby
hazardous = get_cmd_hazardous("INST", "COLLECT", {'TYPE' => 'SPECIAL'})
puts hazardous  #=> true
```

Python Example:

```python
hazardous = get_cmd_hazardous("INST", "COLLECT", {'TYPE': 'SPECIAL'})
print(hazardous) #=> True
```

### get_cmd_value

Returns reads a value from the most recently sent command packet. The pseudo-parameters 'PACKET_TIMESECONDS', 'PACKET_TIMEFORMATTED', 'RECEIVED_COUNT', 'RECEIVED_TIMEFORMATTED', and 'RECEIVED_TIMESECONDS' are also supported.

Ruby / Python Syntax:

```ruby
get_cmd_value("<Target Name>", "<Command Name>", "<Parameter Name>", <Value Type - optional>)
```

| Parameter      | Description                                                                                          |
| -------------- | ---------------------------------------------------------------------------------------------------- |
| Target Name    | Name of the target.                                                                                  |
| Command Name   | Name of the command.                                                                                 |
| Parameter Name | Name of the command parameter.                                                                       |
| Value Type     | Value Type to read. RAW, CONVERTED, FORMATTED, or WITH_UNITS. NOTE: Symbol in Ruby and str in Python |

Ruby Example:

```ruby
value = get_cmd_value("INST", "COLLECT", "TEMP", :RAW)
puts value  #=> 0.0
```

Python Example:

```python
value = get_cmd_value("INST", "COLLECT", "TEMP", "RAW")
print(value)  #=> 0.0
```

### get_cmd_time

Returns the time of the most recent command sent.

Ruby / Python Syntax:

```ruby
get_cmd_time("<Target Name - optional>", "<Command Name - optional>")
```

| Parameter    | Description                                                                                               |
| ------------ | --------------------------------------------------------------------------------------------------------- |
| Target Name  | Name of the target. If not given, then the most recent command time to any target will be returned        |
| Command Name | Name of the command. If not given, then the most recent command time to the given target will be returned |

Ruby / Python Example:

```ruby
target_name, command_name, time = get_cmd_time() # Name of the most recent command sent to any target and time
target_name, command_name, time = get_cmd_time("INST") # Name of the most recent command sent to the INST target and time
target_name, command_name, time = get_cmd_time("INST", "COLLECT") # Name of the most recent INST COLLECT command and time
```

### get_cmd_cnt

Returns the number of times a specified command has been sent.

Ruby / Python Syntax:

```ruby
get_cmd_cnt("<Target Name> <Command Name>")
get_cmd_cnt("<Target Name>", "<Command Name>")
```

| Parameter    | Description          |
| ------------ | -------------------- |
| Target Name  | Name of the target.  |
| Command Name | Name of the command. |

Ruby / Python Example:

```ruby
cmd_cnt = get_cmd_cnt("INST COLLECT") # Number of times the INST COLLECT command has been sent
```

### get_cmd_cnts

Returns the number of times the specified commands have been sent.

Ruby / Python Syntax:

```ruby
get_cmd_cnts([["<Target Name>", "<Command Name>"], ["<Target Name>", "<Command Name>"], ...])
```

| Parameter    | Description          |
| ------------ | -------------------- |
| Target Name  | Name of the target.  |
| Command Name | Name of the command. |

Ruby / Python Example:

```ruby
cmd_cnt = get_cmd_cnts([['INST', 'COLLECT'], ['INST', 'ABORT']]) # Number of times the INST COLLECT and INST ABORT commands have been sent
```

### critical_cmd_status

Returns the status of a critical command. One of APPROVED, REJECTED, or WAITING.

> Since 5.20.0

Ruby / Python Syntax:

```ruby
critical_cmd_status(uuid)
```

| Parameter | Description                                                 |
| --------- | ----------------------------------------------------------- |
| uuid      | UUID for the critical command (displayed in the COSMOS GUI) |

Ruby / Python Example:

```ruby
status = critical_cmd_status("2fa14183-3148-4399-9a74-a130257118f9") #=> WAITING
```

### critical_cmd_approve

Approve the critical command as the current user.

> Since 5.20.0

Ruby / Python Syntax:

```ruby
critical_cmd_approve(uuid)
```

| Parameter | Description                                                 |
| --------- | ----------------------------------------------------------- |
| uuid      | UUID for the critical command (displayed in the COSMOS GUI) |

Ruby / Python Example:

```ruby
critical_cmd_approve("2fa14183-3148-4399-9a74-a130257118f9")
```

### critical_cmd_reject

Reject the critical command as the current user.

> Since 5.20.0

Ruby / Python Syntax:

```ruby
critical_cmd_reject(uuid)
```

| Parameter | Description                                                 |
| --------- | ----------------------------------------------------------- |
| uuid      | UUID for the critical command (displayed in the COSMOS GUI) |

Ruby / Python Example:

```ruby
critical_cmd_reject("2fa14183-3148-4399-9a74-a130257118f9")
```

### critical_cmd_can_approve

Returns whether or not the current user can approve the critical command.

> Since 5.20.0

Ruby / Python Syntax:

```ruby
critical_cmd_can_approve(uuid)
```

| Parameter | Description                                                 |
| --------- | ----------------------------------------------------------- |
| uuid      | UUID for the critical command (displayed in the COSMOS GUI) |

Ruby / Python Example:

```ruby
status = critical_cmd_can_approve("2fa14183-3148-4399-9a74-a130257118f9") #=> true / false
```

## Handling Telemetry

These methods allow the user to interact with telemetry items.

### check, check_raw, check_formatted, check_with_units

Performs a verification of a telemetry item using its specified telemetry type. If the verification fails then the script will be paused with an error. If no comparison is given to check then the telemetry item is simply printed to the script output. Note: In most cases using wait_check is a better choice than using check.

Ruby / Python Syntax:

```ruby
check("<Target Name> <Packet Name> <Item Name> <Comparison - optional>")
```

| Parameter   | Description                                                                                                                                        |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Target Name | Name of the target of the telemetry item.                                                                                                          |
| Packet Name | Name of the telemetry packet of the telemetry item.                                                                                                |
| Item Name   | Name of the telemetry item.                                                                                                                        |
| Comparison  | A comparison to perform against the telemetry item. If a comparison is not given then the telemetry item will just be printed into the script log. |

Ruby Example:

```ruby
check("INST HEALTH_STATUS COLLECTS > 1")
check_raw("INST HEALTH_STATUS COLLECTS > 1")
check_formatted("INST HEALTH_STATUS COLLECTS > 1")
check_with_units("INST HEALTH_STATUS COLLECTS > 1")
# Ruby passes type as symbol
check("INST HEALTH_STATUS COLLECTS > 1", type: :RAW)
```

Python Example:

```python
check("INST HEALTH_STATUS COLLECTS > 1")
check_raw("INST HEALTH_STATUS COLLECTS > 1")
check_formatted("INST HEALTH_STATUS COLLECTS > 1")
check_with_units("INST HEALTH_STATUS COLLECTS > 1")
# Python passes type as string
check("INST HEALTH_STATUS COLLECTS > 1", type='RAW')
```

### check_tolerance

Checks a converted telemetry item against an expected value with a tolerance. If the verification fails then the script will be paused with an error. Note: In most cases using wait_check_tolerance is a better choice than using check_tolerance.

Ruby / Python Syntax:

```ruby
check_tolerance("<Target Name> <Packet Name> <Item Name>", <Expected Value>, <Tolerance>)
```

| Parameter      | Description                                             |
| -------------- | ------------------------------------------------------- |
| Target Name    | Name of the target of the telemetry item.               |
| Packet Name    | Name of the telemetry packet of the telemetry item.     |
| Item Name      | Name of the telemetry item.                             |
| Expected Value | Expected value of the telemetry item.                   |
| Tolerance      | ± Tolerance on the expected value.                      |
| type           | CONVERTED (default) or RAW (Ruby symbol, Python string) |

Ruby Example:

```ruby
check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0)
check_tolerance("INST HEALTH_STATUS TEMP1", 50000, 20000, type: :RAW)
```

Python Example:

```python
check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0)
check_tolerance("INST HEALTH_STATUS TEMP1", 50000, 20000, type='RAW')
```

### check_expression

Evaluates an expression. If the expression evaluates to false the script will be paused with an error. This method can be used to perform more complicated comparisons than using check as shown in the example. Note: In most cases using [wait_check_expression](#wait_check_expression) is a better choice than using check_expression.

Remember that everything inside the check_expression string will be evaluated directly and thus must be valid syntax. A common mistake is to check a variable like so (Ruby variable interpolation):

`check_expression("#{answer} == 'yes'") # where answer contains 'yes'`

This evaluates to `yes == 'yes'` which is not valid syntax because the variable yes is not defined (usually). The correct way to write this expression is as follows:

`check_expression("'#{answer}' == 'yes'") # where answer contains 'yes'`

Now this evaluates to `'yes' == 'yes'` which is true so the check passes.

Ruby Syntax:

```ruby
check_expression(exp_to_eval, context = nil)
```

Python Syntax:

```python
check_expression(exp_to_eval, globals=None, locals=None)
```

| Parameter             | Description                                                                                                                   |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| exp_to_eval           | An expression to evaluate.                                                                                                    |
| context (ruby only)   | The context to call eval with. Defaults to nil. Context in Ruby is typically binding() and is usually not needed.             |
| globals (python only) | The globals to call eval with. Defaults to None. Note that to use COSMOS APIs like tlm() you must pass globals().             |
| locals (python only)  | The locals to call eval with. Defaults to None. Note that if you're using local variables in a method you must pass locals(). |

Ruby Example:

```ruby
check_expression("tlm('INST HEALTH_STATUS COLLECTS') > 5 and tlm('INST HEALTH_STATUS TEMP1') > 25.0")
```

Python Example:

```python
def check(value):
    # Here we using both tlm() and a local 'value' so we need to pass globals() and locals()
    check_expression("tlm('INST HEALTH_STATUS COLLECTS') > value", 5, 0.25, globals(), locals())
check(5)
```

### check_exception

Executes a method and expects an exception to be raised. If the method does not raise an exception, a CheckError is raised.

Ruby / Python Syntax:

```ruby
check_exception("<Method Name>", "<Method Params - optional>")
```

| Parameter     | Description                                              |
| ------------- | -------------------------------------------------------- |
| Method Name   | The COSMOS scripting method to execute, e.g. 'cmd', etc. |
| Method Params | Parameters for the method                                |

Ruby Example:

```ruby
check_exception("cmd", "INST", "COLLECT", "TYPE" => "NORMAL")
```

Python Example:

```python
check_exception("cmd", "INST", "COLLECT", {"TYPE": "NORMAL"})
```

### tlm, tlm_raw, tlm_formatted, tlm_with_units

Reads the specified form of a telemetry item.

Ruby / Python Syntax:

```ruby
tlm("<Target Name> <Packet Name> <Item Name>")
tlm("<Target Name>", "<Packet Name>", "<Item Name>")
```

| Parameter   | Description                                                                                                        |
| ----------- | ------------------------------------------------------------------------------------------------------------------ |
| Target Name | Name of the target of the telemetry item.                                                                          |
| Packet Name | Name of the telemetry packet of the telemetry item.                                                                |
| Item Name   | Name of the telemetry item.                                                                                        |
| type        | Named parameter specifying the type. RAW, CONVERTED (default), FORMATTED, WITH_UNITS (Ruby symbol, Python string). |

Ruby Example:

```ruby
value = tlm("INST HEALTH_STATUS COLLECTS")
value = tlm("INST", "HEALTH_STATUS", "COLLECTS")
value = tlm_raw("INST HEALTH_STATUS COLLECTS")
value = tlm_formatted("INST HEALTH_STATUS COLLECTS")
value = tlm_with_units("INST HEALTH_STATUS COLLECTS")
# Equivalent to tlm_raw
raw_value = tlm("INST HEALTH_STATUS COLLECTS", type: :RAW)
```

Python Example:

```python
value = tlm("INST HEALTH_STATUS COLLECTS")
value = tlm("INST", "HEALTH_STATUS", "COLLECTS")
value = tlm_raw("INST HEALTH_STATUS COLLECTS")
value = tlm_formatted("INST HEALTH_STATUS COLLECTS")
value = tlm_with_units("INST HEALTH_STATUS COLLECTS")
# Equivalent to tlm_raw
raw_value = tlm("INST HEALTH_STATUS COLLECTS", type='RAW')
```

### get_tlm_buffer

Returns a packet hash (similar to get_tlm) along with the raw packet buffer.

Ruby / Python Syntax:

```ruby
buffer = get_tlm_buffer("<Target Name> <Packet Name>")['buffer']
buffer = get_tlm_buffer("<Target Name>", "<Packet Name>")['buffer']
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Target Name | Name of the target. |
| Packet Name | Name of the packet. |

Ruby / Python Example:

```ruby
packet = get_tlm_buffer("INST HEALTH_STATUS")
packet['buffer']
```

### get_tlm_packet

Returns the names, values, and limits states of all telemetry items in a specified packet. The value is returned as an array of arrays with each entry containing [item_name, item_value, limits_state].

Ruby / Python Syntax:

```ruby
get_tlm_packet("<Target Name> <Packet Name>", <type>)
get_tlm_packet("<Target Name>", "<Packet Name>", <type>)
```

| Parameter   | Description                                                                                                           |
| ----------- | --------------------------------------------------------------------------------------------------------------------- |
| Target Name | Name of the target.                                                                                                   |
| Packet Name | Name of the packet.                                                                                                   |
| type        | Named parameter specifying the type. RAW, CONVERTED (default), FORMATTED, or WITH_UNITS (Ruby symbol, Python string). |

Ruby Example:

```ruby
names_values_and_limits_states = get_tlm_packet("INST HEALTH_STATUS", type: :FORMATTED)
```

Python Example:

```python
names_values_and_limits_states = get_tlm_packet("INST HEALTH_STATUS", type='FORMATTED')
```

### get_tlm_values

Returns the values and current limits state for a specified set of telemetry items. Items can be in any telemetry packet in the system. They can all be retrieved using the same value type or a specific value type can be specified for each item.

Ruby / Python Syntax:

```ruby
values, limits_states, limits_settings, limits_set = get_tlm_values(<Items>)
```

| Parameter | Description                                                 |
| --------- | ----------------------------------------------------------- |
| Items     | Array of strings of the form ['TGT__PKT__ITEM__TYPE', ... ] |

Ruby / Python Example:

```ruby
values = get_tlm_values(["INST__HEALTH_STATUS__TEMP1__CONVERTED", "INST__HEALTH_STATUS__TEMP2__RAW"])
print(values) # [[-100.0, :RED_LOW], [0, :RED_LOW]]
```

### get_all_tlm

> Since 5.13.0, since 5.0.0 as get_all_telemetry

Returns an array of all target packet hashes.

Ruby / Python Syntax:

```ruby
get_all_tlm("<Target Name>")
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Target Name | Name of the target. |

Ruby / Python Example:

```ruby
packets = get_all_tlm("INST")
print(packets)
#[{"target_name"=>"INST",
#  "packet_name"=>"ADCS",
#  "endianness"=>"BIG_ENDIAN",
#  "description"=>"Position and attitude data",
#  "stale"=>true,
#  "items"=>
#   [{"name"=>"CCSDSVER",
#     "bit_offset"=>0,
#     "bit_size"=>3,
#     ...
```

### get_all_tlm_names

> Since 5.13.0, since 5.0.6 as get_all_telemetry_names

Returns an array of all target packet names.

Ruby / Python Syntax:

```ruby
get_all_tlm_names("<Target Name>")
```

| Parameter   | Description        |
| ----------- | ------------------ |
| Target Name | Name of the target |

Ruby / Python Example:

```ruby
get_all_tlm_names("INST")  #=> ["ADCS", "HEALTH_STATUS", ...]
```

### get_tlm

> Since 5.13.0, since 5.0.0 as get_telemetry

Returns a packet hash.

Ruby / Python Syntax:

```ruby
get_tlm("<Target Name> <Packet Name>")
get_tlm("<Target Name>", "<Packet Name>")
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Target Name | Name of the target. |
| Packet Name | Name of the packet. |

Ruby / Python Example:

```ruby
packet = get_tlm("INST HEALTH_STATUS")
print(packet)
#{"target_name"=>"INST",
# "packet_name"=>"HEALTH_STATUS",
# "endianness"=>"BIG_ENDIAN",
# "description"=>"Health and status from the instrument",
# "stale"=>true,
# "processors"=>
#  [{"name"=>"TEMP1STAT",
#    "class"=>"OpenC3::StatisticsProcessor",
#    "params"=>["TEMP1", 100, "CONVERTED"]},
#   {"name"=>"TEMP1WATER",
#    "class"=>"OpenC3::WatermarkProcessor",
#    "params"=>["TEMP1", "CONVERTED"]}],
# "items"=>
#  [{"name"=>"CCSDSVER",
#    "bit_offset"=>0,
#    "bit_size"=>3,
#    ...
```

### get_item

Returns an item hash.

Ruby / Python Syntax:

```ruby
get_item("<Target Name> <Packet Name> <Item Name>")
get_item("<Target Name>", "<Packet Name>", "<Item Name>")
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Target Name | Name of the target. |
| Packet Name | Name of the packet. |
| Item Name   | Name of the item.   |

Ruby / Python Example:

```ruby
item = get_item("INST HEALTH_STATUS CCSDSVER")
print(item)
#{"name"=>"CCSDSVER",
# "bit_offset"=>0,
# "bit_size"=>3,
# "data_type"=>"UINT",
# "description"=>"CCSDS packet version number (See CCSDS 133.0-B-1)",
# "endianness"=>"BIG_ENDIAN",
# "required"=>false,
# "overflow"=>"ERROR"}
```

### get_tlm_cnt

Returns the number of times a specified telemetry packet has been received.

Ruby / Python Syntax:

```ruby
get_tlm_cnt("<Target Name> <Packet Name>")
get_tlm_cnt("<Target Name>", "<Packet Name>")
```

| Parameter   | Description                   |
| ----------- | ----------------------------- |
| Target Name | Name of the target.           |
| Packet Name | Name of the telemetry packet. |

Ruby / Python Example:

```ruby
tlm_cnt = get_tlm_cnt("INST HEALTH_STATUS") # Number of times the INST HEALTH_STATUS telemetry packet has been received.
```

### set_tlm

Sets a telemetry item value in the Command and Telemetry Server. This value will be overwritten if a new packet is received from an interface. For that reason this method is most useful if interfaces are disconnected or for testing via the Script Runner disconnect mode. Manually setting telemetry values allows for the execution of many logical paths in scripts.

Ruby / Python Syntax:

```ruby
set_tlm("<Target> <Packet> <Item> = <Value>", <type>)
```

| Parameter | Description                                                                             |
| --------- | --------------------------------------------------------------------------------------- |
| Target    | Target name                                                                             |
| Packet    | Packet name                                                                             |
| Item      | Item name                                                                               |
| Value     | Value to set                                                                            |
| type      | Value type RAW, CONVERTED (default), FORMATTED, WITH_UNITS (Ruby symbol, Python string) |

Ruby Example:

```ruby
set_tlm("INST HEALTH_STATUS COLLECTS = 5") # type is :CONVERTED by default
check("INST HEALTH_STATUS COLLECTS == 5")
set_tlm("INST HEALTH_STATUS COLLECTS = 10", type: :RAW)
check("INST HEALTH_STATUS COLLECTS == 10", type: :RAW)
```

Python Example:

```python
set_tlm("INST HEALTH_STATUS COLLECTS = 5") # type is CONVERTED by default
check("INST HEALTH_STATUS COLLECTS == 5")
set_tlm("INST HEALTH_STATUS COLLECTS = 10", type='RAW')
check("INST HEALTH_STATUS COLLECTS == 10", type='RAW')
```

### inject_tlm

Injects a packet into the system as if it was received from an interface.

Ruby / Packet Syntax:

```ruby
inject_tlm("<target_name>", "<packet_name>", <item_hash>, <type>)
```

| Parameter | Description                                                                                                                                                      |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Target    | Target name                                                                                                                                                      |
| Packet    | Packet name                                                                                                                                                      |
| Item Hash | Hash of item name/value for each item. If an item is not specified in the hash, the current value table value will be used. Optional parameter, defaults to nil. |
| type      | Type of values in the item hash, RAW, CONVERTED (default), FORMATTED, WITH_UNITS (Ruby symbol, Python string)                                                    |

Ruby Example:

```ruby
inject_tlm("INST", "PARAMS", {'VALUE1' => 5.0, 'VALUE2' => 7.0})
```

Python Example:

```python
inject_tlm("INST", "PARAMS", {'VALUE1': 5.0, 'VALUE2': 7.0})
```

### override_tlm

Sets the converted value for a telmetry point in the Command and Telemetry Server. This value will be maintained even if a new packet is received on the interface unless the override is canceled with the normalize_tlm method.

Ruby / Python Syntax:

```ruby
override_tlm("<Target> <Packet> <Item> = <Value>", <type>)
```

| Parameter | Description                                                                                         |
| --------- | --------------------------------------------------------------------------------------------------- |
| Target    | Target name                                                                                         |
| Packet    | Packet name                                                                                         |
| Item      | Item name                                                                                           |
| Value     | Value to set                                                                                        |
| type      | Type to override, ALL (default), RAW, CONVERTED, FORMATTED, WITH_UNITS (Ruby symbol, Python string) |

Ruby Example:

```ruby
override_tlm("INST HEALTH_STATUS TEMP1 = 5") # All requests for TEMP1 return 5
override_tlm("INST HEALTH_STATUS TEMP2 = 0", type: :RAW) # Only RAW tlm set to 0
```

Python Example:

```python
override_tlm("INST HEALTH_STATUS TEMP1 = 5") # All requests for TEMP1 return 5
override_tlm("INST HEALTH_STATUS TEMP2 = 0", type='RAW') # Only RAW tlm set to 0
```

### normalize_tlm

Clears the override of a telmetry point in the Command and Telemetry Server.

Ruby / Python Syntax:

```ruby
normalize_tlm("<Target> <Packet> <Item>", <type>)
```

| Parameter | Description                                                                                          |
| --------- | ---------------------------------------------------------------------------------------------------- |
| Target    | Target name                                                                                          |
| Packet    | Packet name                                                                                          |
| Item      | Item name                                                                                            |
| type      | Type to normalize, ALL (default), RAW, CONVERTED, FORMATTED, WITH_UNITS (Ruby symbol, Python string) |

Ruby Example:

```ruby
normalize_tlm("INST HEALTH_STATUS TEMP1") # clear all overrides
normalize_tlm("INST HEALTH_STATUS TEMP1", type: :RAW) # clear only the RAW override
```

Python Example:

```python
normalize_tlm("INST HEALTH_STATUS TEMP1") # clear all overrides
normalize_tlm("INST HEALTH_STATUS TEMP1", type='RAW') # clear only the RAW override
```

### get_overrides

Returns an array of the the currently overridden values set by override_tlm. NOTE: This returns all the value types that are overridden which by default is all 4 values types when using override_tlm.

Ruby / Python Syntax:

```ruby
get_overrides()
```

Ruby Example:

```ruby
override_tlm("INST HEALTH_STATUS TEMP1 = 5")
puts get_overrides() #=>
# [ {"target_name"=>"INST", "packet_name"=>"HEALTH_STATUS", "item_name"=>"TEMP1", "value_type"=>"RAW", "value"=>5}
#   {"target_name"=>"INST", "packet_name"=>"HEALTH_STATUS", "item_name"=>"TEMP1", "value_type"=>"CONVERTED", "value"=>5}
#   {"target_name"=>"INST", "packet_name"=>"HEALTH_STATUS", "item_name"=>"TEMP1", "value_type"=>"FORMATTED", "value"=>"5"}
#   {"target_name"=>"INST", "packet_name"=>"HEALTH_STATUS", "item_name"=>"TEMP1", "value_type"=>"WITH_UNITS", "value"=>"5"} ]
```

Python Example:

```python
override_tlm("INST HEALTH_STATUS TEMP1 = 5")
print(get_overrides()) #=>
# [ {'target_name': 'INST', 'packet_name': 'HEALTH_STATUS', 'item_name': 'TEMP1', 'value_type': 'RAW', 'value': 5},
#   {'target_name': 'INST', 'packet_name': 'HEALTH_STATUS', 'item_name': 'TEMP1', 'value_type': 'CONVERTED', 'value': 5},
#   {'target_name': 'INST', 'packet_name': 'HEALTH_STATUS', 'item_name': 'TEMP1', 'value_type': 'FORMATTED', 'value': '5'},
#   {'target_name': 'INST', 'packet_name': 'HEALTH_STATUS', 'item_name': 'TEMP1', 'value_type': 'WITH_UNITS', 'value': '5'} ]
```

## Packet Data Subscriptions

APIs for subscribing to specific packets of data. This provides an interface to ensure that each telemetry packet is received and handled rather than relying on polling where some data may be missed.

### subscribe_packets

Allows the user to listen for one or more telemetry packets of data to arrive. A unique id is returned which is used to retrieve the data.

Ruby / Python Syntax:

```ruby
subscribe_packets(packets)
```

| Parameter | Description                                                                         |
| --------- | ----------------------------------------------------------------------------------- |
| packets   | Nested array of target name/packet name pairs that the user wishes to subscribe to. |

Ruby / Python Example:

```ruby
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
```

### get_packets

Streams packet data from a previous subscription.

Ruby Syntax:

```ruby
get_packets(id, block: nil, count: 1000)
```

Python Syntax:

```python
get_packets(id, block=None, count=1000)
```

| Parameter | Description                                                                                                  |
| --------- | ------------------------------------------------------------------------------------------------------------ |
| id        | Unique id returned by subscribe_packets                                                                      |
| block     | Number of milliseconds to block while waiting for packets form ANY stream, default nil / None (do not block) |
| count     | Maximum number of packets to return from EACH packet stream                                                  |

Ruby Example:

```ruby
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
wait 0.1
id, packets = get_packets(id)
packets.each do |packet|
  puts "#{packet['PACKET_TIMESECONDS']}: #{packet['target_name']} #{packet['packet_name']}"
end
# Reuse ID from last call, allow for 1s wait, only get 1 packet
id, packets = get_packets(id, block: 1000, count: 1)
packets.each do |packet|
  puts "#{packet['PACKET_TIMESECONDS']}: #{packet['target_name']} #{packet['packet_name']}"
end
```

Python Example:

```python
id = subscribe_packets([['INST', 'HEALTH_STATUS'], ['INST', 'ADCS']])
wait(0.1)
id, packets = get_packets(id)
for packet in packets:
    print(f"{packet['PACKET_TIMESECONDS']}: {packet['target_name']} {packet['packet_name']}")

# Reuse ID from last call, allow for 1s wait, only get 1 packet
id, packets = get_packets(id, block=1000, count=1)
for packet in packets:
    print(f"{packet['PACKET_TIMESECONDS']}: {packet['target_name']} {packet['packet_name']}")
```

### get_tlm_cnt

Get the receive count for a telemetry packet

Ruby / Python Syntax:

```ruby
get_tlm_cnt("<Target> <Packet>")
get_tlm_cnt("<Target>", "<Packet>")
```

| Parameter | Description |
| --------- | ----------- |
| Target    | Target name |
| Packet    | Packet name |

Ruby / Python Example:

```ruby
get_tlm_cnt("INST HEALTH_STATUS")  #=> 10
```

### get_tlm_cnts

Get the receive counts for an array of telemetry packets

Ruby / Python Syntax:

```ruby
get_tlm_cnts([["<Target>", "<Packet>"], ["<Target>", "<Packet>"]])
```

| Parameter | Description |
| --------- | ----------- |
| Target    | Target name |
| Packet    | Packet name |

Ruby / Python Example:

```ruby
get_tlm_cnts([["INST", "ADCS"], ["INST", "HEALTH_STATUS"]])  #=> [100, 10]
```

### get_packet_derived_items

Get the list of derived telemetry items for a packet

Ruby / Python Syntax:

```ruby
get_packet_derived_items("<Target> <Packet>")
get_packet_derived_items("<Target>", "<Packet>")
```

| Parameter | Description |
| --------- | ----------- |
| Target    | Target name |
| Packet    | Packet name |

Ruby / Python Example:

```ruby
get_packet_derived_items("INST HEALTH_STATUS")  #=> ['PACKET_TIMESECONDS', 'PACKET_TIMEFORMATTED', ...]
```

## Delays

These methods allow the user to pause the script to wait for telemetry to change or for an amount of time to pass.

### wait

Pauses the script for a configurable amount of time (minimum 10ms) or until a converted telemetry item meets given criteria. It supports three different syntaxes as shown. If no parameters are given then an infinite wait occurs until the user presses Go. Note that on a timeout, wait does not stop the script, usually wait_check is a better choice.

Ruby / Python Syntax:

```ruby
elapsed = wait() #=> Returns the actual time waited
elapsed = wait(<Time>) #=> Returns the actual time waited
```

| Parameter | Description                   |
| --------- | ----------------------------- |
| Time      | Time in Seconds to delay for. |

Ruby / Python Syntax:

```ruby
# Returns true or false based on the whether the expression is true or false
success = wait("<Target Name> <Packet Name> <Item Name> <Comparison>", <Timeout>, <Polling Rate (optional)>, type, quiet)
```

| Parameter    | Description                                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------------------------ |
| Target Name  | Name of the target of the telemetry item.                                                                          |
| Packet Name  | Name of the telemetry packet of the telemetry item.                                                                |
| Item Name    | Name of the telemetry item.                                                                                        |
| Comparison   | A comparison to perform against the telemetry item.                                                                |
| Timeout      | Timeout in seconds. Script will proceed if the wait statement times out waiting for the comparison to be true.     |
| Polling Rate | How often the comparison is evaluated in seconds. Defaults to 0.25 if not specified.                               |
| type         | Named parameter specifying the type. RAW, CONVERTED (default), FORMATTED, WITH_UNITS (Ruby symbol, Python string). |
| quiet        | Named parameter indicating whether to log the result. Defaults to true.                                            |

Ruby Example:

```ruby
elapsed = wait
elapsed = wait 5
success = wait("INST HEALTH_STATUS COLLECTS == 3", 10)
success = wait("INST HEALTH_STATUS COLLECTS == 3", 10, type: :RAW, quiet: false)
```

Python Example:

```python
elapsed = wait()
elapsed = wait(5)
success = wait("INST HEALTH_STATUS COLLECTS == 3", 10)
success = wait("INST HEALTH_STATUS COLLECTS == 3", 10, type='RAW', quiet=False)
```

### wait_tolerance

Pauses the script for a configurable amount of time or until a converted telemetry item meets equals an expected value within a tolerance. Note that on a timeout, wait_tolerance does not stop the script, usually wait_check_tolerance is a better choice.

Ruby Python Syntax:

```ruby
# Returns true or false based on the whether the expression is true or false
success = wait_tolerance("<Target Name> <Packet Name> <Item Name>", <Expected Value>, <Tolerance>, <Timeout>, <Polling Rate (optional), type, quiet>)
```

| Parameter      | Description                                                                                                        |
| -------------- | ------------------------------------------------------------------------------------------------------------------ |
| Target Name    | Name of the target of the telemetry item.                                                                          |
| Packet Name    | Name of the telemetry packet of the telemetry item.                                                                |
| Item Name      | Name of the telemetry item.                                                                                        |
| Expected Value | Expected value of the telemetry item.                                                                              |
| Tolerance      | ± Tolerance on the expected value.                                                                                 |
| Timeout        | Timeout in seconds. Script will proceed if the wait statement times out waiting for the comparison to be true.     |
| Polling Rate   | How often the comparison is evaluated in seconds. Defaults to 0.25 if not specified.                               |
| type           | Named parameter specifying the type. RAW, CONVERTED (default), FORMATTED, WITH_UNITS (Ruby symbol, Python string). |
| quiet          | Named parameter indicating whether to log the result. Defaults to true.                                            |

Ruby Examples:

```ruby
success = wait_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10)
success = wait_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10, type: :RAW, quiet: true)
```

Python Examples:

```python
success = wait_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10)
success = wait_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10, type='RAW', quiet=True)
```

### wait_expression

Pauses the script until an expression is evaluated to be true or a timeout occurs. If a timeout occurs the script will continue. This method can be used to perform more complicated comparisons than using wait as shown in the example. Note that on a timeout, wait_expression does not stop the script, usually [wait_check_expression](#wait_check_expression) is a better choice.

Ruby Syntax:

```ruby
# Return true or false based the expression evaluation
wait_expression(
  exp_to_eval,
  timeout,
  polling_rate = DEFAULT_TLM_POLLING_RATE,
  context = nil,
  quiet: false
) -> boolean
```

Python Syntax:

```python
# Return True or False based on the expression evaluation
wait_expression(
    exp_to_eval,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    globals=None,
    locals=None,
    quiet=False,
) -> bool
```

| Parameter             | Description                                                                                                                   |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| expression            | An expression to evaluate.                                                                                                    |
| timeout               | Timeout in seconds. Script will proceed if the wait statement times out waiting for the comparison to be true.                |
| polling_rate          | How often the comparison is evaluated in seconds. Defaults to 0.25 if not specified.                                          |
| context (ruby only)   | The context to call eval with. Defaults to nil. Context in Ruby is typically binding() and is usually not needed.             |
| globals (python only) | The globals to call eval with. Defaults to None. Note that to use COSMOS APIs like tlm() you must pass globals().             |
| locals (python only)  | The locals to call eval with. Defaults to None. Note that if you're using local variables in a method you must pass locals(). |
| quiet                 | Whether to log the result. Defaults to false which means to log.                                                              |

Ruby Example:

```ruby
success = wait_expression("tlm('INST HEALTH_STATUS COLLECTS') > 5 and tlm('INST HEALTH_STATUS TEMP1') > 25.0", 10, 0.25, nil, quiet: true)
```

Python Example:

```python
def check(value):
    # Here we using both tlm() and a local 'value' so we need to pass globals() and locals()
    return wait_expression("tlm('INST HEALTH_STATUS COLLECTS') > value", 5, 0.25, globals(), locals(), quiet=True)
success = check(5)
```

### wait_packet

Pauses the script until a certain number of packets have been received. If a timeout occurs the script will continue. Note that on a timeout, wait_packet does not stop the script, usually wait_check_packet is a better choice.

Ruby / Python Syntax:

```ruby
# Returns true or false based on the whether the packet was received
success = wait_packet("<Target>", "<Packet>", <Num Packets>, <Timeout>, <Polling Rate (optional)>, quiet)
```

| Parameter    | Description                                                                          |
| ------------ | ------------------------------------------------------------------------------------ |
| Target       | The target name                                                                      |
| Packet       | The packet name                                                                      |
| Num Packets  | The number of packets to receive                                                     |
| Timeout      | Timeout in seconds.                                                                  |
| Polling Rate | How often the comparison is evaluated in seconds. Defaults to 0.25 if not specified. |
| quiet        | Named parameter indicating whether to log the result. Defaults to true.              |

Ruby / Python Example:

```ruby
success = wait_packet('INST', 'HEALTH_STATUS', 5, 10) # Wait for 5 INST HEALTH_STATUS packets over 10s
```

### wait_check

Combines the wait and check keywords into one. This pauses the script until the converted value of a telemetry item meets given criteria or times out. On a timeout the script stops.

Ruby / Python Syntax:

```ruby
# Returns the amount of time elapsed waiting for the expression
elapsed = wait_check("<Target Name> <Packet Name> <Item Name> <Comparison>", <Timeout>, <Polling Rate (optional)>, type)
```

| Parameter    | Description                                                                                                        |
| ------------ | ------------------------------------------------------------------------------------------------------------------ |
| Target Name  | Name of the target of the telemetry item.                                                                          |
| Packet Name  | Name of the telemetry packet of the telemetry item.                                                                |
| Item Name    | Name of the telemetry item.                                                                                        |
| Comparison   | A comparison to perform against the telemetry item.                                                                |
| Timeout      | Timeout in seconds. Script will stop if the wait statement times out waiting for the comparison to be true.        |
| Polling Rate | How often the comparison is evaluated in seconds. Defaults to 0.25 if not specified.                               |
| type         | Named parameter specifying the type. RAW, CONVERTED (default), FORMATTED, WITH_UNITS (Ruby symbol, Python string). |

Ruby Example:

```ruby
elapsed = wait_check("INST HEALTH_STATUS COLLECTS > 5", 10)
elapsed = wait_check("INST HEALTH_STATUS COLLECTS > 5", 10, type: :RAW)
```

Python Example:

```python
elapsed = wait_check("INST HEALTH_STATUS COLLECTS > 5", 10)
elapsed = wait_check("INST HEALTH_STATUS COLLECTS > 5", 10, type='RAW')
```

### wait_check_tolerance

Pauses the script for a configurable amount of time or until a converted telemetry item equals an expected value within a tolerance. On a timeout the script stops.

Ruby / Python Syntax:

```ruby
# Returns the amount of time elapsed waiting for the expression
elapsed = wait_check_tolerance("<Target Name> <Packet Name> <Item Name>", <Expected Value>, <Tolerance>, <Timeout>, <Polling Rate (optional)>, type)
```

| Parameter      | Description                                                                                                        |
| -------------- | ------------------------------------------------------------------------------------------------------------------ |
| Target Name    | Name of the target of the telemetry item.                                                                          |
| Packet Name    | Name of the telemetry packet of the telemetry item.                                                                |
| Item Name      | Name of the telemetry item.                                                                                        |
| Expected Value | Expected value of the telemetry item.                                                                              |
| Tolerance      | ± Tolerance on the expected value.                                                                                 |
| Timeout        | Timeout in seconds. Script will stop if the wait statement times out waiting for the comparison to be true.        |
| Polling Rate   | How often the comparison is evaluated in seconds. Defaults to 0.25 if not specified.                               |
| type           | Named parameter specifying the type. RAW, CONVERTED (default), FORMATTED, WITH_UNITS (Ruby symbol, Python string). |

Ruby Example:

```ruby
elapsed = wait_check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10)
elapsed = wait_check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10, type: :RAW)
```

Python Example:

```python
elapsed = wait_check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10)
elapsed = wait_check_tolerance("INST HEALTH_STATUS COLLECTS", 10.0, 5.0, 10, type='RAW')
```

### wait_check_expression

Pauses the script until an expression is evaluated to be true or a timeout occurs. If a timeout occurs the script will stop. This method can be used to perform more complicated comparisons than using wait as shown in the example. Also see the syntax notes for [check_expression](#check_expression).

Ruby Syntax:

```ruby
# Return time spent waiting for the expression to evaluate to true
wait_check_expression(
  exp_to_eval,
  timeout,
  polling_rate = DEFAULT_TLM_POLLING_RATE,
  context = nil
) -> int
```

Python Syntax:

```python
# Return time spent waiting for the expression to evaluate to True
wait_check_expression(
    exp_to_eval,
    timeout,
    polling_rate=DEFAULT_TLM_POLLING_RATE,
    globals=None,
    locals=None
) -> int
```

| Parameter             | Description                                                                                                                   |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| expression            | An expression to evaluate.                                                                                                    |
| timeout               | Timeout in seconds. Script will proceed if the wait statement times out waiting for the comparison to be true.                |
| polling_rate          | How often the comparison is evaluated in seconds. Defaults to 0.25 if not specified.                                          |
| context (ruby only)   | The context to call eval with. Defaults to nil. Context in Ruby is typically binding() and is usually not needed.             |
| globals (python only) | The globals to call eval with. Defaults to None. Note that to use COSMOS APIs like tlm() you must pass globals().             |
| locals (python only)  | The locals to call eval with. Defaults to None. Note that if you're using local variables in a method you must pass locals(). |

Ruby Example:

```ruby
elapsed = wait_check_expression("tlm('INST HEALTH_STATUS COLLECTS') > 5 and tlm('INST HEALTH_STATUS TEMP1') > 25.0", 10)
```

Python Example:

```python
# Note that for Python we need to pass globals() to be able to use COSMOS API methods like tlm()
elapsed = wait_check_expression("tlm('INST HEALTH_STATUS COLLECTS') > 5 and tlm('INST HEALTH_STATUS TEMP1') > 25.0", 10, 0.25, globals())
```

### wait_check_packet

Pauses the script until a certain number of packets have been received. If a timeout occurs the script will stop.

Ruby / Python Syntax:

```ruby
# Returns the amount of time elapsed waiting for the packets
elapsed = wait_check_packet("<Target>", "<Packet>", <Num Packets>, <Timeout>, <Polling Rate (optional)>, quiet)
```

| Parameter    | Description                                                                                               |
| ------------ | --------------------------------------------------------------------------------------------------------- |
| Target       | The target name                                                                                           |
| Packet       | The packet name                                                                                           |
| Num Packets  | The number of packets to receive                                                                          |
| Timeout      | Timeout in seconds. Script will stop if the wait statement times out waiting specified number of packets. |
| Polling Rate | How often the comparison is evaluated in seconds. Defaults to 0.25 if not specified.                      |
| quiet        | Named parameter indicating whether to log the result. Defaults to true.                                   |

Ruby / Python Example:

```ruby
elapsed = wait_check_packet('INST', 'HEALTH_STATUS', 5, 10) # Wait for 5 INST HEALTH_STATUS packets over 10s
```

## Limits

These methods deal with handling telemetry limits.

### limits_enabled?, limits_enabled

The limits_enabled? method returns true/false depending on whether limits are enabled for a telemetry item.

Ruby Syntax:

```ruby
limits_enabled?("<Target Name> <Packet Name> <Item Name>")
```

Python Syntax:

```python
limits_enabled("<Target Name> <Packet Name> <Item Name>")
```

| Parameter   | Description                                         |
| ----------- | --------------------------------------------------- |
| Target Name | Name of the target of the telemetry item.           |
| Packet Name | Name of the telemetry packet of the telemetry item. |
| Item Name   | Name of the telemetry item.                         |

Ruby Example:

```ruby
enabled = limits_enabled?("INST HEALTH_STATUS TEMP1") #=> true or false
```

Python Example:

```python
enabled = limits_enabled("INST HEALTH_STATUS TEMP1") #=> True or False
```

### enable_limits

Enables limits monitoring for the specified telemetry item.

Ruby / Python Syntax:

```ruby
enable_limits("<Target Name> <Packet Name> <Item Name>")
```

| Parameter   | Description                                         |
| ----------- | --------------------------------------------------- |
| Target Name | Name of the target of the telemetry item.           |
| Packet Name | Name of the telemetry packet of the telemetry item. |
| Item Name   | Name of the telemetry item.                         |

Ruby / Python Example:

```ruby
enable_limits("INST HEALTH_STATUS TEMP1")
```

### disable_limits

Disables limits monitoring for the specified telemetry item.

Ruby / Python Syntax:

```ruby
disable_limits("<Target Name> <Packet Name> <Item Name>")
```

| Parameter   | Description                                         |
| ----------- | --------------------------------------------------- |
| Target Name | Name of the target of the telemetry item.           |
| Packet Name | Name of the telemetry packet of the telemetry item. |
| Item Name   | Name of the telemetry item.                         |

Ruby / Python Example:

```ruby
disable_limits("INST HEALTH_STATUS TEMP1")
```

### enable_limits_group

Enables limits monitoring on a set of telemetry items specified in a limits group.

Ruby / Python Syntax:

```ruby
enable_limits_group("<Limits Group Name>")
```

| Parameter         | Description               |
| ----------------- | ------------------------- |
| Limits Group Name | Name of the limits group. |

Ruby / Python Example:

```ruby
enable_limits_group("SAFE_MODE")
```

### disable_limits_group

Disables limits monitoring on a set of telemetry items specified in a limits group.

Ruby / Python Syntax:

```ruby
disable_limits_group("<Limits Group Name>")
```

| Parameter         | Description               |
| ----------------- | ------------------------- |
| Limits Group Name | Name of the limits group. |

Ruby / Python Example:

```ruby
disable_limits_group("SAFE_MODE")
```

### get_limits_groups

Returns the list of limits groups in the system.

Ruby / Python Example:

```ruby
limits_groups = get_limits_groups()
```

### set_limits_set

Sets the current limits set. The default limits set is DEFAULT.

Ruby / Python Syntax:

```ruby
set_limits_set("<Limits Set Name>")
```

| Parameter       | Description             |
| --------------- | ----------------------- |
| Limits Set Name | Name of the limits set. |

Ruby / Python Example:

```ruby
set_limits_set("DEFAULT")
```

### get_limits_set

Returns the name of the current limits set. The default limits set is DEFAULT.

Ruby / Python Example:

```ruby
limits_set = get_limits_set()
```

### get_limits_sets

Returns the list of limits sets in the system.

Ruby / Python Example:

```ruby
limits_sets = get_limits_sets()
```

### get_limits

Returns hash / dict of all the limits settings for a telemetry point.

Ruby / Python Syntax:

```ruby
get_limits(<Target Name>, <Packet Name>, <Item Name>)
```

| Parameter   | Description                                        |
| ----------- | -------------------------------------------------- |
| Target Name | Name of the target of the telemetry item           |
| Packet Name | Name of the telemetry packet of the telemetry item |
| Item Name   | Name of the telemetry item                         |

Ruby Example:

```ruby
result = get_limits('INST', 'HEALTH_STATUS', 'TEMP1')
puts result #=> {"DEFAULT"=>[-80.0, -70.0, 60.0, 80.0, -20.0, 20.0], "TVAC"=>[-80.0, -30.0, 30.0, 80.0]}
puts result.keys #=> ['DEFAULT', 'TVAC']
puts result['DEFAULT'] #=> [-80.0, -70.0, 60.0, 80.0, -20.0, 20.0]
```

Python Example:

```python
result = get_limits('INST', 'HEALTH_STATUS', 'TEMP1')
print(result) #=> {'DEFAULT'=>[-80.0, -70.0, 60.0, 80.0, -20.0, 20.0], 'TVAC'=>[-80.0, -30.0, 30.0, 80.0]}
print(result.keys()) #=> dict_keys(['DEFAULT', 'TVAC'])
print(result['DEFAULT']) #=> [-80.0, -70.0, 60.0, 80.0, -20.0, 20.0]
```

### set_limits

The set_limits_method sets limits settings for a telemetry point. Note: In most cases it would be better to update your config files or use different limits sets rather than changing limits settings in realtime.

Ruby / Python Syntax:

```ruby
set_limits(<Target Name>, <Packet Name>, <Item Name>, <Red Low>, <Yellow Low>, <Yellow High>, <Red High>, <Green Low (optional)>, <Green High (optional)>, <Limits Set (optional)>, <Persistence (optional)>, <Enabled (optional)>)
```

| Parameter   | Description                                                                                                                                                                         |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Target Name | Name of the target of the telemetry item.                                                                                                                                           |
| Packet Name | Name of the telemetry packet of the telemetry item.                                                                                                                                 |
| Item Name   | Name of the telemetry item.                                                                                                                                                         |
| Red Low     | Red Low setting for this limits set. Any value below this value will be make the item red.                                                                                          |
| Yellow Low  | Yellow Low setting for this limits set. Any value below this value but greater than Red Low will be make the item yellow.                                                           |
| Yellow High | Yellow High setting for this limits set. Any value above this value but less than Red High will be make the item yellow.                                                            |
| Red High    | Red High setting for this limits set. Any value above this value will be make the item red.                                                                                         |
| Green Low   | Optional. If given, any value greater than Green Low and less than Green_High will make the item blue indicating a good operational value.                                          |
| Green High  | Optional. If given, any value greater than Green Low and less than Green_High will make the item blue indicating a good operational value.                                          |
| Limits Set  | Optional. Set the limits for a specific limits set. If not given then it defaults to setting limits for the CUSTOM limits set.                                                      |
| Persistence | Optional. Set the number of samples this item must be out of limits before changing limits state. Defaults to no change. Note: This affects all limits settings across limits sets. |
| Enabled     | Optional. Whether or not limits are enabled for this item. Defaults to true. Note: This affects all limits settings across limits sets.                                             |

Ruby / Python Example:

```ruby
set_limits('INST', 'HEALTH_STATUS', 'TEMP1', -10.0, 0.0, 50.0, 60.0, 30.0, 40.0, 'TVAC', 1, true)
```

### get_out_of_limits

Returns an array with the target_name, packet_name, item_name, and limits_state of all items that are out of their limits ranges.

Ruby / Python Example:

```ruby
out_of_limits_items = get_out_of_limits()
```

### get_overall_limits_state

Returns the overall limits state for the COSMOS system. Returns 'GREEN', 'YELLOW', or 'RED'.

Ruby / Python Syntax:

```ruby
get_overall_limits_state(<Ignored Items> (optional))
```

| Parameter     | Description                                                                                                                        |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Ignored Items | Array of arrays with items to ignore when determining the overall limits state. [['TARGET_NAME', 'PACKET_NAME', 'ITEM_NAME'], ...] |

Ruby / Python Example:

```ruby
overall_limits_state = get_overall_limits_state()
overall_limits_state = get_overall_limits_state([['INST', 'HEALTH_STATUS', 'TEMP1']])
```

### get_limits_events

Returns limits events based on an offset returned from the last time it was called.

Ruby / Python Syntax:

```ruby
get_limits_event(<Offset>, count)
```

| Parameter | Description                                                                                   |
| --------- | --------------------------------------------------------------------------------------------- |
| Offset    | Offset returned by the previous call to get_limits_event. Default is nil for the initial call |
| count     | Named parameter specifying the maximum number of limits events to return. Default is 100      |

Ruby / Python Example:

```ruby
events = get_limits_event()
print(events)
#[["1613077715557-0",
#  {"type"=>"LIMITS_CHANGE",
#   "target_name"=>"TGT",
#   "packet_name"=>"PKT",
#   "item_name"=>"ITEM",
#   "old_limits_state"=>"YELLOW_LOW",
#   "new_limits_state"=>"RED_LOW",
#   "time_nsec"=>"1",
#   "message"=>"message"}],
# ["1613077715557-1",
#  {"type"=>"LIMITS_CHANGE",
#   "target_name"=>"TGT",
#   "packet_name"=>"PKT",
#   "item_name"=>"ITEM",
#   "old_limits_state"=>"RED_LOW",
#   "new_limits_state"=>"YELLOW_LOW",
#   "time_nsec"=>"2",
#   "message"=>"message"}]]
# The last offset is the first item ([0]) in the last event ([-1])
events = get_limits_event(events[-1][0])
print(events)
#[["1613077715657-0",
#  {"type"=>"LIMITS_CHANGE",
#   ...
```

## Plugins / Packages

APIs for getting knowledge about plugins and packages.

### plugin_list

Returns all the installed plugins.

Ruby Syntax:

```ruby
plugin_list(default: false)
```

Python Syntax:

```ruby
plugin_list(default = False)
```

| Parameter | Description                                                                  |
| --------- | ---------------------------------------------------------------------------- |
| default   | Whether to include the default COSMOS plugins (all the regular applications) |

Ruby / Python Example:

```ruby
plugins = plugin_list() #=> ['openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem__20250116214539']
plugins = plugin_list(default: true) #=>
# ['openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem__20250116214539',
#  'openc3-cosmos-tool-admin-6.0.3.pre.beta0.20250115200004.gem__20250116211504',
#  'openc3-cosmos-tool-bucketexplorer-6.0.3.pre.beta0.20250115200008.gem__20250116211525',
#  'openc3-cosmos-tool-cmdsender-6.0.3.pre.beta0.20250115200012.gem__20250116211515',
#  'openc3-cosmos-tool-cmdtlmserver-6.0.3.pre.beta0.20250115200015.gem__20250116211512',
#  'openc3-cosmos-tool-dataextractor-6.0.3.pre.beta0.20250115200005.gem__20250116211521',
#  'openc3-cosmos-tool-dataviewer-6.0.3.pre.beta0.20250115200009.gem__20250116211522',
#  'openc3-cosmos-tool-docs-6.0.3.pre.beta0.20250117042104.gem__20250117042154',
#  'openc3-cosmos-tool-handbooks-6.0.3.pre.beta0.20250115200014.gem__20250116211523',
#  'openc3-cosmos-tool-iframe-6.0.3.pre.beta0.20250115200011.gem__20250116211503',
#  'openc3-cosmos-tool-limitsmonitor-6.0.3.pre.beta0.20250115200017.gem__20250116211514',
#  'openc3-cosmos-tool-packetviewer-6.0.3.pre.beta0.20250115200004.gem__20250116211518',
#  'openc3-cosmos-tool-scriptrunner-6.0.3.pre.beta0.20250115200012.gem__20250116211517',
#  'openc3-cosmos-tool-tablemanager-6.0.3.pre.beta0.20250115200018.gem__20250116211524',
#  'openc3-cosmos-tool-tlmgrapher-6.0.3.pre.beta0.20250115200005.gem__20250116211520',
#  'openc3-cosmos-tool-tlmviewer-6.0.3.pre.beta0.20250115200008.gem__20250116211519',
#  'openc3-tool-base-6.0.3.pre.beta0.20250115195959.gem__20250116211459']
```

### plugin_get

Returns information about an installed plugin.

Ruby / Python Syntax:

```ruby
plugin_get(<Plugin Name>)
```

| Parameter   | Description                                                  |
| ----------- | ------------------------------------------------------------ |
| Plugin Name | Full name of the plugin (typically taken from plugin_list()) |

Ruby / Python Example:

```ruby
plugin_get('openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem__20250116214539') #=>
# { "name"=>"openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem__20250116214539",
#   "variables"=>{"inst_target_name"=>"INST", ...},
#   "plugin_txt_lines"=>["# Note: This plugin includes 4 targets ..."],
#   "needs_dependencies"=>true,
#   "updated_at"=>1737063941094624764 }
```

### package_list

List all the packages installed in COSMOS.

Ruby Example:

```ruby
package_list() #=> {"ruby"=>["openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem", ..., "openc3-tool-base-6.0.3.pre.beta0.20250115195959.gem"],
               #    "python"=>["numpy-2.1.1", "pip-24.0", "setuptools-65.5.0"]}
```

Python Example:

```python
package_list() #=> {'ruby': ['openc3-cosmos-demo-6.0.3.pre.beta0.20250116214358.gem', ..., 'openc3-tool-base-6.0.3.pre.beta0.20250115195959.gem'],
               #    'python': ['numpy-2.1.1', 'pip-24.0', 'setuptools-65.5.0']}
```

## Targets

APIs for getting knowledge about targets.

### get_target_names

Returns a list of the targets in the system in an array.

Ruby Example:

```ruby
targets = get_target_names() #=> ['INST', 'INST2', 'EXAMPLE', 'TEMPLATED']
```

### get_target

Returns a target hash containing all the information about the target.

Ruby Syntax:

```ruby
get_target("<Target Name>")
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Target Name | Name of the target. |

Ruby Example:

```ruby
target = get_target("INST")
print(target)
# {"name"=>"INST",
#  "folder_name"=>"INST",
#  "requires"=>[],
#  "ignored_parameters"=>
#   ["CCSDSVER",
#    "CCSDSTYPE",
#    "CCSDSSHF",
#    "CCSDSAPID",
#    "CCSDSSEQFLAGS",
#    "CCSDSSEQCNT",
#    "CCSDSLENGTH",
#    "PKTID"],
#  "ignored_items"=>
#   ["CCSDSVER",
#    "CCSDSTYPE",
#    "CCSDSSHF",
#    "CCSDSAPID",
#    "CCSDSSEQFLAGS",
#    "CCSDSSEQCNT",
#    "CCSDSLENGTH",
#    "RECEIVED_COUNT",
#    "RECEIVED_TIMESECONDS",
#    "RECEIVED_TIMEFORMATTED"],
#  "limits_groups"=>[],
#  "cmd_tlm_files"=>
#   [".../targets/INST/cmd_tlm/inst_cmds.txt",
#    ".../targets/INST/cmd_tlm/inst_tlm.txt"],
#  "cmd_unique_id_mode"=>false,
#  "tlm_unique_id_mode"=>false,
#  "id"=>nil,
#  "updated_at"=>1613077058266815900,
#  "plugin"=>nil}
```

### get_target_interfaces

Returns the interfaces for all targets. The return value is an array of arrays where each subarray contains the target name, and a String of all the interface names.

Ruby / Python Example:

```ruby
target_ints = get_target_interfaces()
target_ints.each do |target_name, interfaces|
  puts "Target: #{target_name}, Interfaces: #{interfaces}"
end
```

## Interfaces

These methods allow the user to manipulate COSMOS interfaces.

### get_interface

Returns an interface status including the as built interface and its current status (cmd/tlm counters, etc).

Ruby / Python Syntax:

```
get_interface("<Interface Name>")
```

| Parameter      | Description            |
| -------------- | ---------------------- |
| Interface Name | Name of the interface. |

Ruby / Python Example:

```ruby
interface = get_interface("INST_INT")
print(interface)
# {"name"=>"INST_INT",
#  "config_params"=>["interface.rb"],
#  "target_names"=>["INST"],
#  "connect_on_startup"=>true,
#  "auto_reconnect"=>true,
#  "reconnect_delay"=>5.0,
#  "disable_disconnect"=>false,
#  "options"=>[],
#  "protocols"=>[],
#  "log"=>true,
#  "log_raw"=>false,
#  "plugin"=>nil,
#  "updated_at"=>1613076213535979900,
#  "state"=>"CONNECTED",
#  "clients"=>0,
#  "txsize"=>0,
#  "rxsize"=>0,
#  "txbytes"=>0,
#  "rxbytes"=>0,
#  "txcnt"=>0,
#  "rxcnt"=>0}
```

### get_interface_names

Returns a list of the interfaces in the system in an array.

Ruby / Python Example:

```ruby
interface_names = get_interface_names() #=> ['INST_INT', 'INST2_INT', 'EXAMPLE_INT', 'TEMPLATED_INT']
```

### connect_interface

Connects to targets associated with a COSMOS interface.

Ruby / Python Syntax:

```ruby
connect_interface("<Interface Name>", <Interface Parameters (optional)>)
```

| Parameter            | Description                                                                                                                                                 |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interface Name       | Name of the interface.                                                                                                                                      |
| Interface Parameters | Parameters used to initialize the interface. If none are given then the interface will use the parameters that were given in the server configuration file. |

Ruby / Python Example:

```ruby
connect_interface("INT1")
connect_interface("INT1", hostname, port)
```

### disconnect_interface

Disconnects from targets associated with a COSMOS interface.

Ruby / Python Syntax:

```ruby
disconnect_interface("<Interface Name>")
```

| Parameter      | Description            |
| -------------- | ---------------------- |
| Interface Name | Name of the interface. |

Ruby / Python Example:

```ruby
disconnect_interface("INT1")
```

### start_raw_logging_interface

Starts logging of raw data on one or all interfaces. This is for debugging purposes only.

Ruby / Python Syntax:

```ruby
start_raw_logging_interface("<Interface Name (optional)>")
```

| Parameter      | Description                                                                                                                                                        |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Interface Name | Name of the Interface to command to start raw data logging. Defaults to 'ALL' which causes all interfaces that support raw data logging to start logging raw data. |

Ruby / Python Example:

```ruby
start_raw_logging_interface("int1")
```

### stop_raw_logging_interface

Stops logging of raw data on one or all interfaces. This is for debugging purposes only.

Ruby / Python Syntax:

```ruby
stop_raw_logging_interface("<Interface Name (optional)>")
```

| Parameter      | Description                                                                                                                                                      |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interface Name | Name of the Interface to command to stop raw data logging. Defaults to 'ALL' which causes all interfaces that support raw data logging to stop logging raw data. |

Ruby / Python Example:

```ruby
stop_raw_logging_interface("int1")
```

### get_all_interface_info

Returns information about all interfaces. The return value is an array of arrays where each subarray contains the interface name, connection state, number of connected clients, transmit queue size, receive queue size, bytes transmitted, bytes received, command count, and telemetry count.

Ruby Example:

```ruby
interface_info = get_all_interface_info()
interface_info.each do |interface_name, connection_state, num_clients, tx_q_size, rx_q_size, tx_bytes, rx_bytes, cmd_count, tlm_count|
  puts "Interface: #{interface_name}, Connection state: #{connection_state}, Num connected clients: #{num_clients}"
  puts "Transmit queue size: #{tx_q_size}, Receive queue size: #{rx_q_size}, Bytes transmitted: #{tx_bytes}, Bytes received: #{rx_bytes}"
  puts "Cmd count: #{cmd_count}, Tlm count: #{tlm_count}"
end
```

Python Example:

```python
interface_info = get_all_interface_info()
for interface in interface_info():
    # [interface_name, connection_state, num_clients, tx_q_size, rx_q_size, tx_bytes, rx_bytes, cmd_count, tlm_count]
    print(f"Interface: {interface[0]}, Connection state: {interface[1]}, Num connected clients: {interface[2]}")
    print(f"Transmit queue size: {interface[3]}, Receive queue size: {interface[4]}, Bytes transmitted: {interface[5]}, Bytes received: {interface[6]}")
    print(f"Cmd count: {interface[7]}, Tlm count: {interface[8]}")
```

### map_target_to_interface

Map a target to an interface allowing target commands and telemetry to be processed by that interface.

Ruby / Python Syntax:

```ruby
map_target_to_interface("<Target Name>", "<Interface Name>", cmd_only, tlm_only, unmap_old)
```

| Parameter      | Description                                                                            |
| -------------- | -------------------------------------------------------------------------------------- |
| Target Name    | Name of the target                                                                     |
| Interface Name | Name of the interface                                                                  |
| cmd_only       | Named parameter whether to map target commands only to the interface (default: false)  |
| tlm_only       | Named parameter whether to map target telemetry only to the interface (default: false) |
| unmap_old      | Named parameter whether remove the target from all existing interfaces (default: true) |

Ruby Example:

```ruby
map_target_to_interface("INST", "INST_INT", unmap_old: false)
```

Python Example:

```python
map_target_to_interface("INST", "INST_INT", unmap_old=False)
```

### interface_cmd

Send a command directly to an interface. This has no effect in the standard COSMOS interfaces but can be implemented by a custom interface to change behavior.

Ruby / Python Syntax:

```ruby
interface_cmd("<Interface Name>", "<Command Name>", "<Command Parameters>")
```

| Parameter          | Description                             |
| ------------------ | --------------------------------------- |
| Interface Name     | Name of the interface                   |
| Command Name       | Name of the command to send             |
| Command Parameters | Any parameters to send with the command |

Ruby / Python Example:

```ruby
interface_cmd("INST", "DISABLE_CRC")
```

### interface_protocol_cmd

Send a command directly to an interface protocol. This has no effect in the standard COSMOS protocols but can be implemented by a custom protocol to change behavior.

Ruby / Python Syntax:

```ruby
interface_protocol_cmd("<Interface Name>", "<Command Name>", "<Command Parameters>")
```

| Parameter          | Description                                                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interface Name     | Name of the interface                                                                                                                                      |
| Command Name       | Name of the command to send                                                                                                                                |
| Command Parameters | Any parameters to send with the command                                                                                                                    |
| read_write         | Whether command gets send to read or write protocols. Must be one of READ, WRITE, or READ_WRITE (Ruby symbols, Python strings). The default is READ_WRITE. |
| index              | Which protocol in the stack the command should apply to. The default is -1 which applies the command to all.                                               |

Ruby Example:

```ruby
interface_protocol_cmd("INST", "DISABLE_CRC", read_write: :READ_WRITE, index: -1)
```

Python Example:

```python
interface_protocol_cmd("INST", "DISABLE_CRC", read_write='READ_WRITE', index=-1)
```

## Routers

These methods allow the user to manipulate COSMOS routers.

### connect_router

Connects a COSMOS router.

Ruby / Python Syntax:

```ruby
connect_router("<Router Name>", <Router Parameters (optional)>)
```

| Parameter         | Description                                                                                                                                           |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Router Name       | Name of the router.                                                                                                                                   |
| Router Parameters | Parameters used to initialize the router. If none are given then the router will use the parameters that were given in the server configuration file. |

Ruby / Python Example:

```ruby
connect_ROUTER("INST_ROUTER")
connect_router("INST_ROUTER", 7779, 7779, nil, 10.0, 'PREIDENTIFIED')
```

### disconnect_router

Disconnects a COSMOS router.

Ruby / Python Syntax:

```ruby
disconnect_router("<Router Name>")
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Router Name | Name of the router. |

Ruby / Python Example:

```ruby
disconnect_router("INT1_ROUTER")
```

### get_router_names

Returns a list of the routers in the system in an array.

Ruby / Python Example:

```ruby
router_names = get_router_names() #=> ['ROUTER_INT']
```

### get_router

Returns a router status including the as built router and its current status (cmd/tlm counters, etc).

Ruby / Python Syntax:

```ruby
get_router("<Router Name>")
```

| Parameter   | Description         |
| ----------- | ------------------- |
| Router Name | Name of the router. |

Ruby / Python Example:

```ruby
router = get_router("ROUTER_INT")
print(router)
#{"name"=>"ROUTER_INT",
# "config_params"=>["router.rb"],
# "target_names"=>["INST"],
# "connect_on_startup"=>true,
# "auto_reconnect"=>true,
# "reconnect_delay"=>5.0,
# "disable_disconnect"=>false,
# "options"=>[],
# "protocols"=>[],
# "log"=>true,
# "log_raw"=>false,
# "plugin"=>nil,
# "updated_at"=>1613076213535979900,
# "state"=>"CONNECTED",
# "clients"=>0,
# "txsize"=>0,
# "rxsize"=>0,
# "txbytes"=>0,
# "rxbytes"=>0,
# "txcnt"=>0,
# "rxcnt"=>0}
```

### get_all_router_info

Returns information about all routers. The return value is an array of arrays where each subarray contains the router name, connection state, number of connected clients, transmit queue size, receive queue size, bytes transmitted, bytes received, packets received, and packets sent.

Ruby Example:

```ruby
router_info = get_all_router_info()
router_info.each do |router_name, connection_state, num_clients, tx_q_size, rx_q_size, tx_bytes, rx_bytes, pkts_rcvd, pkts_sent|
  puts "Router: #{router_name}, Connection state: #{connection_state}, Num connected clients: #{num_clients}"
  puts "Transmit queue size: #{tx_q_size}, Receive queue size: #{rx_q_size}, Bytes transmitted: #{tx_bytes}, Bytes received: #{rx_bytes}"
  puts "Packets received: #{pkts_rcvd}, Packets sent: #{pkts_sent}"
end
```

Python Example:

```python
router_info = get_all_router_info()
# router_name, connection_state, num_clients, tx_q_size, rx_q_size, tx_bytes, rx_bytes, pkts_rcvd, pkts_sent
for router in router_info:
    print(f"Router: {router[0]}, Connection state: {router[1]}, Num connected clients: {router[2]}")
    print(f"Transmit queue size: {router[3]}, Receive queue size: {router[4]}, Bytes transmitted: {router[5]}, Bytes received: {router[6]}")
    print(f"Packets received: {router[7]}, Packets sent: {router[8]}")
```

### start_raw_logging_router

Starts logging of raw data on one or all routers. This is for debugging purposes only.

Ruby / Python Syntax:

```ruby
start_raw_logging_router("<Router Name (optional)>")
```

| Parameter   | Description                                                                                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Router Name | Name of the Router to command to start raw data logging. Defaults to 'ALL' which causes all routers that support raw data logging to start logging raw data. |

Ruby / Python Example:

```ruby
start_raw_logging_router("router1")
```

### stop_raw_logging_router

Stops logging of raw data on one or all routers. This is for debugging purposes only.

Ruby / Python Syntax:

```ruby
stop_raw_logging_router("<Router Name (optional)>")
```

| Parameter   | Description                                                                                                                                                |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Router Name | Name of the Router to command to stop raw data logging. Defaults to 'ALL' which causes all routers that support raw data logging to stop logging raw data. |

Ruby / Python Example:

```ruby
stop_raw_logging_router("router1")
```

### router_cmd

Send a command directly to a router. This has no effect in the standard COSMOS routers but can be implemented by a custom router to change behavior.

Ruby / Python Syntax:

```ruby
router_cmd("<Router Name>", "<Command Name>", "<Command Parameters>")
```

| Parameter          | Description                             |
| ------------------ | --------------------------------------- |
| Router Name        | Name of the router                      |
| Command Name       | Name of the command to send             |
| Command Parameters | Any parameters to send with the command |

Ruby / Python Example:

```ruby
router_cmd("INST", "DISABLE_CRC")
```

### router_protocol_cmd

Send a command directly to an router protocol. This has no effect in the standard COSMOS protocols but can be implemented by a custom protocol to change behavior.

Ruby / Python Syntax:

```ruby
router_protocol_cmd("<Router Name>", "<Command Name>", "<Command Parameters>", read_write, index)
```

| Parameter          | Description                                                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Router Name        | Name of the router                                                                                                                                         |
| Command Name       | Name of the command to send                                                                                                                                |
| Command Parameters | Any parameters to send with the command                                                                                                                    |
| read_write         | Whether command gets send to read or write protocols. Must be one of READ, WRITE, or READ_WRITE (Ruby symbols, Python strings). The default is READ_WRITE. |
| index              | Which protocol in the stack the command should apply to. The default is -1 which applies the command to all.                                               |

Ruby Example:

```ruby
router_protocol_cmd("INST", "DISABLE_CRC", read_write: :READ_WRITE, index: -1)
```

Python Example:

```python
router_protocol_cmd("INST", "DISABLE_CRC", read_write='READ_WRITE', index=-1)
```

## Tables

These methods allow the user to script Table Manager.

### table_create_binary

> Since 6.1.0

Creates a table binary based on a table definition file. You can achieve the same result in the Table Manager GUI with File->New File. Returns the path to the binary file created.

Ruby / Python Syntax:

```ruby
table_create_binary(<Table Definition File>)
```

| Parameter             | Description                                                                     |
| --------------------- | ------------------------------------------------------------------------------- |
| Table Definition File | Path to the table definition file, e.g. INST/tables/config/ConfigTables_def.txt |

Ruby Example:

```ruby
# Full example of using table_create_binary and then editing the binary
require 'openc3/tools/table_manager/table_config'
# This returns a hash: {"filename"=>"INST/tables/bin/MCConfigurationTable.bin"}
table = table_create_binary("INST/tables/config/MCConfigurationTable_def.txt")
file = get_target_file(table['filename'])
table_binary = file.read()

# Get the definition file so we can process the binary
def_file = get_target_file("INST/tables/config/MCConfigurationTable_def.txt")
# Access the internal TableConfig to process the definition
config = OpenC3::TableConfig.process_file(def_file.path())
# Grab the table by the definition name, e.g. TABLE "MC_Configuration"
table = config.table('MC_CONFIGURATION')
# Now you can read or write individual items in the table
table.write("MEMORY_SCRUBBING", "DISABLE")
# Finally write the table.buffer (the binary) back to storage
put_target_file("INST/tables/bin/MCConfigurationTable_NoScrub.bin", table.buffer)
```

Python Example:

```python
# NOTE: TableConfig and other TableManager classes do not yet exist in Python
# So editing like the above Ruby example is not yet possible

# Returns a dict: {'filename': 'INST/tables/bin/ConfigTables.bin'}
table = table_create_binary("INST/tables/config/ConfigTables_def.txt")
```

### table_create_report

> Since 6.1.0

Creates a table binary based on a table definition file. You can achieve the same result in the Table Manager GUI with File->New File. Returns the path to the binary file created.

Ruby / Python Syntax:

```ruby
table_create_report(<Table Binary Filename>, <Table Definition File>, <Table Name (optional)>)
```

filename, definition, table_name

| Parameter             | Description                                                                                                                                                                                                                                                                                                      |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Table Binary File     | Path to the table binary file, e.g. INST/tables/bin/ConfigTables.bin                                                                                                                                                                                                                                             |
| Table Definition File | Path to the table definition file, e.g. INST/tables/config/ConfigTables_def.txt                                                                                                                                                                                                                                  |
| Table Name            | Name of the table to create the report. This only applies if the Table Binary and Table Definition consist of multiple tables. By default the report consists of all tables and is named after the binary file. If the table name is given, the report is just the specified table and is named after the table. |

Ruby Example:

```ruby
table = table_create_report("INST/tables/bin/ConfigTables.bin", "INST/tables/config/ConfigTables_def.txt") #=>
# {"filename"=>"INST/tables/bin/ConfigTables.csv", "contents"=>"MC_CONFIGURATION\nLabel, ...
table = table_create_report("INST/tables/bin/ConfigTables.bin", "INST/tables/config/ConfigTables_def.txt", table_name: "MC_CONFIGURATION") #=>
# {"filename"=>"INST/tables/bin/McConfiguration.csv", "contents"=>"MC_CONFIGURATION\nLabel, ...
```

Python Example:

```python
table = table_create_report("INST/tables/bin/ConfigTables.bin", "INST/tables/config/ConfigTables_def.txt") #=>
# {'filename': 'INST/tables/bin/ConfigTables.csv', 'contents': 'MC_CONFIGURATION\nLabel, ...
table = table_create_report("INST/tables/bin/ConfigTables.bin", "INST/tables/config/ConfigTables_def.txt", table_name="MC_CONFIGURATION") #=>
# {'filename': 'INST/tables/bin/ConfigTables.csv', 'contents': 'MC_CONFIGURATION\nLabel, ...
```

## Stashing Data

These methods allow the user to store temporary data into COSMOS and retrieve it. The storage is implemented as a key / value storage (Ruby hash or Python dict). This can be used in scripts to store information that applies across multiple scripts or multiple runs of a single script.

### stash_set

Sets a stash item.

Ruby / Python Syntax:

```ruby
stash_set("<Stash Key>", <Stash Value>)
```

| Parameter   | Description                  |
| ----------- | ---------------------------- |
| Stash Key   | Name of the stash key to set |
| Stash Value | Value to set                 |

Ruby / Python Example:

```ruby
stash_set('run_count', 5)
stash_set('setpoint', 23.4)
```

### stash_get

Returns the specified stash item.

Ruby / Python Syntax:

```ruby
stash_get("<Stash Key>")
```

| Parameter | Description                     |
| --------- | ------------------------------- |
| Stash Key | Name of the stash key to return |

Ruby / Python Example:

```ruby
stash_get('run_count')  #=> 5
```

### stash_all

Returns all the stash items as a Ruby hash or Python dict.

Ruby Example:

```ruby
stash_all()  #=> ['run_count' => 5, 'setpoint' => 23.4]
```

Python Example:

```ruby
stash_all()  #=> ['run_count': 5, 'setpoint': 23.4]
```

### stash_keys

Returns all the stash keys.

Ruby / Python Example:

```ruby
stash_keys()  #=> ['run_count', 'setpoint']
```

### stash_delete

Deletes a stash item. Note this actions is permanent!

Ruby / Python Syntax:

```ruby
stash_delete("<Stash Key>")
```

| Parameter | Description                     |
| --------- | ------------------------------- |
| Stash Key | Name of the stash key to delete |

Ruby / Python Example:

```ruby
stash_delete("run_count")
```

## Telemetry Screens

These methods allow the user to open, close or create unique telemetry screens from within a test procedure.

### display_screen

Opens a telemetry screen at the specified position.

Ruby / Python Syntax:

```ruby
display_screen("<Target Name>", "<Screen Name>", <X Position (optional)>, <Y Position (optional)>)
```

| Parameter   | Description                                               |
| ----------- | --------------------------------------------------------- |
| Target Name | Telemetry screen target name                              |
| Screen Name | Screen name within the specified target                   |
| X Position  | X coordinate for the upper left hand corner of the screen |
| Y Position  | Y coordinate for the upper left hand corner of the screen |

Ruby / Python Example:

```ruby
display_screen("INST", "ADCS", 100, 200)
```

### clear_screen

Closes an open telemetry screen.

Ruby / Python Syntax:

```ruby
clear_screen("<Target Name>", "<Screen Name>")
```

| Parameter   | Description                             |
| ----------- | --------------------------------------- |
| Target Name | Telemetry screen target name            |
| Screen Name | Screen name within the specified target |

Ruby / Python Example:

```ruby
clear_screen("INST", "ADCS")
```

### clear_all_screens

Closes all open screens.

Ruby / Python Example:

```ruby
clear_all_screens()
```

### delete_screen

Deletes an existing Telemetry Viewer screen.

Ruby / Python Syntax:

```ruby
delete_screen("<Target Name>", "<Screen Name>")
```

| Parameter   | Description                             |
| ----------- | --------------------------------------- |
| Target Name | Telemetry screen target name            |
| Screen Name | Screen name within the specified target |

Ruby / Python Example:

```ruby
delete_screen("INST", "ADCS")
```

### get_screen_list

Returns a list of available telemetry screens.

Ruby / Python Example:

```ruby
get_screen_list() #=> ['INST ADCS', 'INST COMMANDING', ...]
```

### get_screen_definition

Returns the text file contents of a telemetry screen definition.

Syntax:

```ruby
get_screen_definition("<Target Name>", "<Screen Name>")
```

| Parameter   | Description                             |
| ----------- | --------------------------------------- |
| Target Name | Telemetry screen target name            |
| Screen Name | Screen name within the specified target |

Ruby / Python Example:

```ruby
screen_definition = get_screen_definition("INST", "HS")
```

### create_screen

Allows you to create a screen directly from a script. This screen is saved to Telemetry Viewer for future use in that application.

Ruby / Python Syntax:

```ruby
create_screen("<Target Name>", "<Screen Name>" "<Definition>")
```

| Parameter   | Description                              |
| ----------- | ---------------------------------------- |
| Target Name | Telemetry screen target name             |
| Screen Name | Screen name within the specified target  |
| Definition  | The entire screen definition as a String |

Ruby Example:

```ruby
screen_def = '
  SCREEN AUTO AUTO 0.1 FIXED
  VERTICAL
    TITLE "New Screen"
    VERTICALBOX
      LABELVALUE INST HEALTH_STATUS TEMP1
    END
  END
'
# Here we pass in the screen definition as a string
create_screen("INST", "LOCAL", screen_def)
```

Python Example:

```python
screen_def = '
  SCREEN AUTO AUTO 0.1 FIXED
  VERTICAL
    TITLE "New Screen"
    VERTICALBOX
      LABELVALUE INST HEALTH_STATUS TEMP1
    END
  END
'
# Here we pass in the screen definition as a string
create_screen("INST", "LOCAL", screen_def)
```

### local_screen

Allows you to create a local screen directly from a script which is not permanently saved to the Telemetry Viewer screen list. This is useful for one off screens that help users interact with scripts.

Ruby / Python Syntax:

```ruby
local_screen("<Screen Name>", "<Definition>", <X Position (optional)>, <Y Position (optional)>)
```

| Parameter   | Description                                               |
| ----------- | --------------------------------------------------------- |
| Screen Name | Screen name within the specified target                   |
| Definition  | The entire screen definition as a String                  |
| X Position  | X coordinate for the upper left hand corner of the screen |
| Y Position  | Y coordinate for the upper left hand corner of the screen |

NOTE: It is possible to specify a X, Y location off the visible display. If you do so and try to re-create the screen it will not display (because it is already displayed). Try issuing a `clear_all_screens()` first to clear any screens off the visible display space.

Ruby Example:

```ruby
screen_def = '
  SCREEN AUTO AUTO 0.1 FIXED
  VERTICAL
    TITLE "Local Screen"
    VERTICALBOX
      LABELVALUE INST HEALTH_STATUS TEMP1
    END
  END
'
# Here we pass in the screen definition as a string
local_screen("TESTING", screen_def, 600, 75)
```

Python Example:

```python
screen_def = """
  SCREEN AUTO AUTO 0.1 FIXED
  VERTICAL
    TITLE "Local Screen"
    VERTICALBOX
      LABELVALUE INST HEALTH_STATUS TEMP1
    END
  END
"""
# Here we pass in the screen definition as a string
local_screen("TESTING", screen_def, 600, 75)
```

## Script Runner Scripts

These methods allow the user to control Script Runner scripts.

### start

Starts execution of another high level test procedure. Script Runner will load the file and immediately start executing it before jumping back to the calling procedure. No parameters can be given to high level test procedures. If parameters are necessary, then consider using a subroutine.

Ruby / Python Syntax:

```ruby
start("<Procedure Filename>")
```

| Parameter          | Description                                                                                                                                                                 |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Procedure Filename | Name of the test procedure file. These files are normally in the procedures folder but may be anywhere in the Ruby search path. Additionally, absolute paths are supported. |

Ruby / Python Example:

```ruby
start("test1.rb")
```

### load_utility

Reads in a script file that contains useful subroutines for use in your test procedure. When these subroutines run in ScriptRunner or TestRunner, their lines will be highlighted. If you want to import subroutines but do not want their lines to be highlighted in ScriptRunner or TestRunner, use the standard Ruby 'load' or 'require' statement or Python 'import' statement.

Ruby / Python Syntax:

```ruby
load_utility("TARGET/lib/<Utility Filename>")
```

| Parameter        | Description                                                                                                                                                        |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Utility Filename | Name of the script file containing subroutines including the .rb or .py extension. You need to include the full target name and path such as TARGET/lib/utility.rb |

Ruby / Python Example:

```ruby
load_utility("TARGET/lib/mode_changes.rb") # Ruby
load_utility("TARGET/lib/mode_changes.py") # Python
```

### script_list

Returns all the available files in COSMOS as an array / list. This includes configuration files at every directory level to ensure the user has access to every file. You can filter the list client side to just the 'lib' and or 'procedures' directories if you wish. Note: script names do NOT include '\*' to indicate modified.

Ruby Example:

```ruby
scripts = script_list()
puts scripts.length #=> 139
puts scripts.select {|script| script.include?('/lib/') || script.include?('/procedures/')} #=>
# [EXAMPLE/lib/example_interface.rb, INST/lib/example_limits_response.rb, ...]
```

Python Example:

```python
scripts = script_list()
print(len(scripts))
print(list(script for script in scripts if '/lib/' in script or '/procedures/' in script)) #=>
# [EXAMPLE/lib/example_interface.rb, INST/lib/example_limits_response.rb, ...]
```

### script_create

Creates a new script with the given contents.

Ruby / Python Syntax:

```ruby
script_create("<Script Name>", "<Script Contents>")
```

| Parameter       | Description                                           |
| --------------- | ----------------------------------------------------- |
| Script Name     | Full path name of the script starting with the target |
| Script Contents | Script contents as text                               |

Ruby Example:

```ruby
contents = 'puts "Hello from Ruby"'
script_create("INST/procedures/new_script.rb", contents)
```

Python Example:

```python
contents = 'print("Hello from Python")'
script_create("INST2/procedures/new_script.py", contents)
```

### script_body

Returns the script contents.

Ruby / Python Syntax:

```ruby
script_body("<Script Name>")
```

| Parameter   | Description                                           |
| ----------- | ----------------------------------------------------- |
| Script Name | Full path name of the script starting with the target |

Ruby Example:

```ruby
script = script_body("INST/procedures/checks.rb")
puts script #=> # Display all environment variables\nputs ENV.inspect ...
```

Python Example:

```python
script = script_body("INST2/procedures/checks.py")
print(script) #=> # import os\n\n# Display the environment variables ...
```

### script_delete

Deletes a script from COSMOS. Note, you can only _really_ delete TEMP scripts and modified scripts. Scripts that are part of an installed COSMOS plugin remain as they were installed.

Ruby / Python Syntax:

```ruby
script_delete("<Script Name>")
```

| Parameter   | Description                                           |
| ----------- | ----------------------------------------------------- |
| Script Name | Full path name of the script starting with the target |

Ruby / Python Example:

```ruby
script_delete("INST/procedures/checks.rb")
```

### script_run

Runs a script in Script Runner. The script will run in the background and can be opened in Script Runner by selecting Script->Execution Status and then connecting to it.

Ruby / Python Syntax:

```ruby
script_run("<Script Name>")
```

| Parameter   | Description                                           |
| ----------- | ----------------------------------------------------- |
| Script Name | Full path name of the script starting with the target |

Ruby Example:

```ruby
id = script_run("INST/procedures/checks.rb")
puts id
```

Python Example:

```python
id = script_run("INST2/procedures/checks.py")
print(id)
```

### script_lock

Locks a script for editing. Subsequent users that open this script will get a warning that the script is currently locked.

Ruby / Python Syntax:

```ruby
script_lock("<Script Name>")
```

| Parameter   | Description                                           |
| ----------- | ----------------------------------------------------- |
| Script Name | Full path name of the script starting with the target |

Ruby / Python Example:

```ruby
script_lock("INST/procedures/checks.rb")
```

### script_unlock

Unlocks a script for editing. If the script was not previously locked this does nothing.

Ruby / Python Syntax:

```ruby
script_unlock("<Script Name>")
```

| Parameter   | Description                                           |
| ----------- | ----------------------------------------------------- |
| Script Name | Full path name of the script starting with the target |

Ruby / Python Example:

```ruby
script_unlock("INST/procedures/checks.rb")
```

### script_syntax_check

Performs a Ruby or Python syntax check on the given script.

Ruby / Python Syntax:

```ruby
script_syntax_check("<Script Name>")
```

| Parameter   | Description                                           |
| ----------- | ----------------------------------------------------- |
| Script Name | Full path name of the script starting with the target |

Ruby Example:

```ruby
result = script_syntax_check("INST/procedures/checks.rb")
puts result #=> {"title"=>"Syntax Check Successful", "description"=>"[\"Syntax OK\\n\"]", "success"=>true}
```

Python Example:

```python
result = script_syntax_check("INST2/procedures/checks.py")
print(result) #=> {'title': 'Syntax Check Successful', 'description': '["Syntax OK"]', 'success': True}
```

### script_instrumented

Returns the instrumented script which allows COSMOS Script Runner to monitor the execution and provide line by line visualization. This is primarily a low level debugging method used by COSMOS developers.

Ruby / Python Syntax:

```ruby
script_instrumented("<Script Name>")
```

| Parameter   | Description                                           |
| ----------- | ----------------------------------------------------- |
| Script Name | Full path name of the script starting with the target |

Ruby Example:

```ruby
script = script_instrumented("INST/procedures/checks.rb")
puts script #=> private; __return_val = nil; begin; RunningScript.instance.script_binding = binding(); ...
```

Python Example:

```python
script = script_instrumented("INST2/procedures/checks.py")
print(script) #=> while True:\ntry:\nRunningScript.instance.pre_line_instrumentation ...
```

### script_delete_all_breakpoints

Delete _all_ breakpoints associated with _all_ scripts.

Ruby / Python Example:

```ruby
script_delete_all_breakpoints()
```

### step_mode

Places ScriptRunner into step mode where Go must be hit to proceed to the next line.

Ruby / Python Example:

```ruby
step_mode()
```

### run_mode

Places ScriptRunner into run mode where the next line is run automatically.

Ruby / Python Example:

```ruby
run_mode()
```

### disconnect_script

Puts scripting into disconnect mode. In disconnect mode, commands are not sent to targets, checks are all successful, and waits expire instantly. Requests for telemetry (tlm()) typically return 0. Disconnect mode is useful for dry-running scripts without having connected targets.

Ruby / Python Example:

```ruby
disconnect_script()
```

### running_script_list

List the currently running scripts. Note, this will also include the script which is calling this method. Thus the list will never be empty but will always contain at least 1 item. Returns an array of hashes / list of dicts (see [running_script_get](#running_script_get) for hash / dict contents).

Ruby Example:

```ruby
running_script_list() #=> [{"id"=>5, "scope"=>"DEFAULT", "name"=>"__TEMP__/2025_01_15_13_16_26_210_temp.rb", "user"=>"Anonymous", "start_time"=>"2025-01-15 20:16:52 +0000", "disconnect"=>false, "environment"=>[]}]
```

Python Example:

```python
running_script_list() #=> [{'id': 15, 'scope': 'DEFAULT', 'name': 'INST2/procedures/scripting.py', 'user': 'Anonymous', 'start_time': '2025-01-16 17:36:22 +0000', 'disconnect': False, 'environment': []}]
```

### running_script_get

Get the currently running script with the specified ID. The information returned is the script ID, scope, name, user, start time, disconnect state, environment variables, hostname, state, line number, and update time.

Ruby / Python Syntax:

```ruby
running_script_get("<Script Id>")
```

| Parameter | Description                                     |
| --------- | ----------------------------------------------- |
| Script Id | Script ID returned by [script_run](#script_run) |

Ruby Example:

```ruby
running_script_get(15) #=> {"id"=>15, "scope"=>"DEFAULT", "name"=>"INST/procedures/new_script.rb", "user"=>"Anonymous", "start_time"=>"2025-01-16 00:28:44 +0000", "disconnect"=>false, "environment"=>[], "hostname"=>"ac9dde3c59c1", "state"=>"spawning", "line_no"=>1, "update_time"=>"2025-01-16 00:28:44 +0000"}
```

Python Example:

```python
running_script_get(15) #=> {'id': 15, 'scope': 'DEFAULT', 'name': 'INST2/procedures/new_script.py', 'user': 'Anonymous', 'start_time': '2025-01-16 18:04:03 +0000', 'disconnect': False, 'environment': [], 'hostname': 'b84dbcee54ad', 'state': 'running', 'line_no': 3, 'update_time': '2025-01-16T18:04:05.255638Z'}
```

### running_script_stop

Stop the running script with the specified ID. This is equivalent to clicking the Stop button in the Script Runner GUI.

Ruby / Python Syntax:

```ruby
running_script_stop("<Script Id>")
```

| Parameter | Description                                     |
| --------- | ----------------------------------------------- |
| Script Id | Script ID returned by [script_run](#script_run) |

Ruby / Python Example:

```ruby
running_script_stop(15)
```

### running_script_pause

Pause the running script with the specified ID. This is equivalent to clicking the Pause button in the Script Runner GUI.

Ruby / Python Syntax:

```ruby
running_script_pause("<Script Id>")
```

| Parameter | Description                                     |
| --------- | ----------------------------------------------- |
| Script Id | Script ID returned by [script_run](#script_run) |

Ruby / Python Example:

```ruby
running_script_pause(15)
```

### running_script_retry

Retry the current line of the running script with the specified ID. This is equivalent to clicking the Retry button in the Script Runner GUI.

Ruby / Python Syntax:

```ruby
running_script_retry("<Script Id>")
```

| Parameter | Description                                     |
| --------- | ----------------------------------------------- |
| Script Id | Script ID returned by [script_run](#script_run) |

Ruby / Python Example:

```ruby
running_script_retry(15)
```

### running_script_go

Unpause the running script with the specified ID. This is equivalent to clicking the Go button in the Script Runner GUI.

Ruby / Python Syntax:

```ruby
running_script_go("<Script Id>")
```

| Parameter | Description                                     |
| --------- | ----------------------------------------------- |
| Script Id | Script ID returned by [script_run](#script_run) |

Ruby / Python Example:

```ruby
running_script_go(15)
```

### running_script_step

Step the running script with the specified ID. This is equivalent to clicking the Step button in the Script Runner GUI's Debug window.

Ruby / Python Syntax:

```ruby
running_script_step("<Script Id>")
```

| Parameter | Description                                     |
| --------- | ----------------------------------------------- |
| Script Id | Script ID returned by [script_run](#script_run) |

Ruby / Python Example:

```ruby
running_script_step(15)
```

### running_script_delete

Force quit the running script with the specified ID. This is equivalent to clicking the Delete button under the Running Scripts in the Script Runner GUI's Script -> Execution Status pane. Note, the 'stop' signal is first sent to the specified script and then the script is forcibly removed. Normally you should use the [running_script_stop](#running_script_stop) method.

Ruby / Python Syntax:

```ruby
running_script_delete("<Script Id>")
```

| Parameter | Description                                     |
| --------- | ----------------------------------------------- |
| Script Id | Script ID returned by [script_run](#script_run) |

Ruby / Python Example:

```ruby
running_script_delete(15)
```

### completed_script_list

List the completed scripts. Returns an array of hashes / list of dicts containing the id, username, script name, script log, and start time.

Ruby Example:

```ruby
completed_script_list() #=> [{"id"=>"15", "user"=>"Anonymous", "name"=>"__TEMP__/2025_01_15_17_07_51_568_temp.rb", "log"=>"DEFAULT/tool_logs/sr/20250116/2025_01_16_00_28_43_sr_2025_01_15_17_07_51_568_temp.txt", "start"=>"2025-01-16 00:28:43 +0000"}, ...]
```

Python Example:

```ruby
completed_script_list() #=> [{'id': 16, 'user': 'Anonymous', 'name': 'INST2/procedures/new_script.py', 'log': 'DEFAULT/tool_logs/sr/20250116/2025_01_16_17_46_22_sr_new_script.txt', 'start': '2025-01-16 17:46:22 +0000'}, ...]
```

## Script Runner Settings

These methods allow the user to control various Script Runner settings.

### set_line_delay

This method sets the line delay in script runner.

Ruby / Python Syntax:

```ruby
set_line_delay(<Delay>)
```

| Parameter | Description                                                                                                   |
| --------- | ------------------------------------------------------------------------------------------------------------- |
| Delay     | The amount of time script runner will wait between lines when executing a script, in seconds. Should be ≥ 0.0 |

Ruby / Python Example:

```ruby
set_line_delay(0.0)
```

### get_line_delay

The method gets the line delay that script runner is currently using.

Ruby / Python Example:

```ruby
curr_line_delay = get_line_delay()
```

### set_max_output

This method sets the maximum number of characters to display in Script Runner output before truncating. Default is 50,000 characters.

Ruby / Python Syntax:

```ruby
set_max_output(<Characters>)
```

| Parameter  | Description                                      |
| ---------- | ------------------------------------------------ |
| Characters | Number of characters to output before truncating |

Ruby / Python Example:

```ruby
set_max_output(100)
```

### get_max_output

The method gets the maximum number of characters to display in Script Runner output before truncating. Default is 50,000 characters.

Ruby / Python Example:

```ruby
print(get_max_output()) #=> 50000
```

### disable_instrumentation

Disables instrumentation for a block of code (line highlighting and exception catching). This is especially useful for speeding up loops that are very slow if lines are instrumented.
Consider breaking code like this into a separate file and using either require/load to read the file for the same effect while still allowing errors to be caught by your script.

:::warning Use with Caution
Disabling instrumentation will cause any error that occurs while disabled to cause your script to completely stop.
:::

Ruby Example:

```ruby
disable_instrumentation do
  1000.times do
    # Don't want this to have to highlight 1000 times
  end
end
```

Python Example:

```python
with disable_instrumentation():
    for x in range(1000):
        # Don't want this to have to highlight 1000 times
```

## Script Runner Suites

Creating Script Runner suites utilizes APIs to add groups to the defined suites. For more information please see [running script suites](../tools/script-runner.md#running-script-suites).

### add_group, add_group_setup, add_group_teardown, add_script

Adds a group's methods to the suite. The add_group method adds all the group methods including setup, teardown, and all the methods starting with 'script\_' or 'test\_'. The add_group_setup method adds just the setup method defined in the group class. The add_group_teardown method adds just the teardown method defined in the group class. The add_script method adds an individual method to the suite. NOTE: add_script can add any method including those not named with 'script\_' or 'test\_'.

Ruby / Python Syntax:

```ruby
add_group(<Group Class>)
add_group_setup(<Group Class>)
add_group_teardown(<Group Class>)
add_script(<Group Class>, <Method>)
```

| Parameter   | Description                                                                                                                                                                               |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Group Class | Name of the previously defined class which inherits from the OpenC3 Group class. The Ruby API passes a String with the name of the group. The Python API passes the Group class directly. |
| Method      | Name of the method in the OpenC3 Group class. The Ruby API passes a String with the name of the method. The Python API passes the Group class directly.                                   |

Ruby Example:

```ruby
load 'openc3/script/suite.rb'

class ExampleGroup < OpenC3::Group
  def script_1
    # Insert test code here ...
  end
end
class WrapperGroup < OpenC3::Group
  def setup
    # Insert test code here ...
  end
  def my_method
    # Insert test code here ...
  end
  def teardown
    # Insert test code here ...
  end
end

class MySuite < OpenC3::Suite
  def initialize
    super()
    add_group('ExampleGroup')
    add_group_setup('WrapperGroup')
    add_script('WrapperGroup', 'my_method')
    add_group_teardown('WrapperGroup')
  end
end
```

Python Example:

```python
from openc3.script import *
from openc3.script.suite import Group, Suite

class ExampleGroup(Group):
    def script_1(self):
        # Insert test code here ...
        pass
class WrapperGroup(Group):
    def setup(self):
        # Insert test code here ...
        pass
    def my_method(self):
        # Insert test code here ...
        pass
    def teardown(self):
        # Insert test code here ...
        pass
class MySuite(Suite):
    def __init__(self):
        super().__init__()
        self.add_group(ExampleGroup)
        self.add_group_setup(WrapperGroup)
        self.add_script(WrapperGroup, 'my_method')
        self.add_group_teardown(WrapperGroup)
```

## Timelines

The Timelines API allows you to manipulate Calendar timelines. Calendar is a COSMOS Enterprise tool.

### list_timelines

Returns all the timelines in an array of hashes / list of dicts.

Ruby Example:

```ruby
timelines = list_timelines() #=>
# [{"name"=>"Mine", "color"=>"#e67643", "execute"=>true, "shard"=>0, "scope"=>"DEFAULT", "updated_at"=>1737124024123643504}]
```

Python Example:

```python
timelihes = list_timelines() #=>
# [{'name': 'Mine', 'color': '#e67643', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737124024123643504}]
```

### create_timeline

Create a new timeline in Calendar which can hold activities.

Ruby Syntax:

```ruby
create_timeline(name, color: nil)
```

Python Syntax:

```python
create_timeline(name, color=None)
```

| Parameter | Description                                                                                   |
| --------- | --------------------------------------------------------------------------------------------- |
| name      | Name of the timeline                                                                          |
| color     | Color of the timeline. Must be given as a hex value, e.g. #FF0000. Default is a random color. |

Ruby Example:

```ruby
tl = create_timeline("Mine") #=>
# {"name"=>"Mine", "color"=>"#e67643", "execute"=>true, "shard"=>0, "scope"=>"DEFAULT", "updated_at"=>1737124024123643504}
```

Python Example:

```python
tl = create_timeline("Other", color="#FF0000") #=>
# {'name': 'Other', 'color': '#FF0000', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737126348971941923}
```

### get_timeline

Get information about an existing timeline.

Ruby / Python Syntax:

```ruby
get_timeline(name)
```

| Parameter | Description          |
| --------- | -------------------- |
| name      | Name of the timeline |

Ruby Example:

```ruby
tl = get_timeline("Mine") #=>
# {"name"=>"Mine", "color"=>"#e67643", "execute"=>true, "shard"=>0, "scope"=>"DEFAULT", "updated_at"=>1737124024123643504}
```

Python Example:

```python
tl = get_timeline("Other") #=>
# {'name': 'Other', 'color': '#FF0000', 'execute': True, 'shard': 0, 'scope': 'DEFAULT', 'updated_at': 1737126348971941923}
```

### set_timeline_color

Set the displayed color for an existing timeline.

Ruby / Python Syntax:

```ruby
set_timeline_color(name, color)
```

| Parameter | Description                                                        |
| --------- | ------------------------------------------------------------------ |
| name      | Name of the timeline                                               |
| color     | Color of the timeline. Must be given as a hex value, e.g. #FF0000. |

Ruby / Python Example:

```ruby
set_timeline_color("Mine", "#4287f5")
```

### delete_timeline

Delete an existing timeline. Timelines with activities can only be deleted by passing force = true.

Ruby Syntax:

```ruby
delete_timeline(name, force: false)
```

Python Syntax:

```python
delete_timeline(name, force=False)
```

| Parameter | Description                                                            |
| --------- | ---------------------------------------------------------------------- |
| name      | Name of the timeline                                                   |
| force     | Whether to delete the timeline if it has activities. Default is false. |

Ruby Example:

```ruby
delete_timeline("Mine", force: true)
```

Python Example:

```python
delete_timeline("Other", force=True)
```

### create_timeline_activity

Create an activity on an existing timeline. Activities can be one of COMMAND, SCRIPT, or RESERVE. Activities have a start and stop time and commands and scripts take data on the command or script to execute.

Ruby Syntax:

```ruby
create_timeline_activity(name, kind:, start:, stop:, data: {})
```

Python Syntax:

```python
create_timeline_activity(name, kind, start, stop, data={})
```

| Parameter | Description                                                                   |
| --------- | ----------------------------------------------------------------------------- |
| name      | Name of the timeline                                                          |
| kind      | Type of the activity. One of COMMAND, SCRIPT, or RESERVE.                     |
| start     | Start time of the activity. Time / datetime instance.                         |
| stop      | Stop time of the activity. Time / datetime instance.                          |
| data      | Hash / dict of data for COMMAND or SCRIPT type. Default is empty hash / dict. |

Ruby Example:

```ruby
now = Time.now()
start = now + 3600
stop = start + 3600
act = create_timeline_activity("RubyTL", kind: "RESERVE", start: start, stop: stop) #=>
# { "name"=>"RubyTL", "updated_at"=>1737128705034982375, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"reserve", "data"=>{"username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"5f373846-eb6c-43cd-97bd-cca19a8ffb04",
#   "events"=>[{"time"=>1737128705, "event"=>"created"}], "recurring"=>{}}
act = create_timeline_activity("RubyTL", kind: "COMMAND", start: start, stop: stop,
    data: {command: "INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10"}) #=>
# { "name"=>"RubyTL", "updated_at"=>1737128761316084471, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"command", "data"=>{"command"=>"INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"cdb661b4-a65b-44e7-95e2-5e1dba80c782",
#   "events"=>[{"time"=>1737128761, "event"=>"created"}], "recurring"=>{}}
act = create_timeline_activity("RubyTL", kind: "SCRIPT", start: start, stop: stop,
  data: {environment: [{key: "USER", value: "JASON"}], script: "INST/procedures/checks.rb"}) #=>
# { "name"=>"RubyTL", "updated_at"=>1737128791047885970, "start"=>1737135903, "stop"=>1737139503,
#   "kind"=>"script", "data"=>{"environment"=>[{"key"=>"USER", "value"=>"JASON"}], "script"=>"INST/procedures/checks.rb", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"70426e3d-6313-4897-b159-6e5cd94ace1d",
#   "events"=>[{"time"=>1737128791, "event"=>"created"}], "recurring"=>{}}
```

Python Example:

```python
now = datetime.now(timezone.utc)
start = now + timedelta(hours=1)
stop = start + timedelta(hours=1)
act = create_timeline_activity("PythonTL", kind="RESERVE", start=start, stop=stop) #=>
# {'name': 'PythonTL', 'updated_at': 1737129305507111708, 'start': 1737132902, 'stop': 1737136502,
#  'kind': 'reserve', 'data': {'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': '46328378-ed78-4719-ad70-e84951a196fd',
#  'events': [{'time': 1737129305, 'event': 'created'}], 'recurring': {}}
act = create_timeline_activity("PythonTL", kind="COMMAND", start=start, stop=stop,
    data={'command': "INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10"}) #=>
# {'name': 'PythonTL', 'updated_at': 1737129508886643928, 'start': 1737133108, 'stop': 1737136708,
#  'kind': 'command', 'data': {'command': 'INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10', 'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': 'cddbf034-ccdd-4c36-91c2-2653a39b06a5',
#  'events': [{'time': 1737129508, 'event': 'created'}], 'recurring': {}}
start = now + timedelta(hours=2)
stop = start + timedelta(hours=1)
act = create_timeline_activity("PythonTL", kind="SCRIPT", start=start, stop=stop,
  data={'environment': [{'key': "USER", 'value': "JASON"}], 'script': "INST2/procedures/checks.py"}) #=>
# {'name': 'PythonTL', 'updated_at': 1737129509288571345, 'start': 1737136708, 'stop': 1737140308,
#  'kind': 'script', 'data': {'environment': [{'key': 'USER', 'value': 'JASON'}], 'script': 'INST2/procedures/checks.py', 'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': '4f8d791b-b138-4383-b5ec-85c28b2bea20',
#  'events': [{'time': 1737129509, 'event': 'created'}], 'recurring': {}}
```

### get_timeline_activity

Get an existing timeline activity.

Ruby / Python Syntax:

```ruby
get_timeline_activity(name, start, uuid)
```

| Parameter | Description                                           |
| --------- | ----------------------------------------------------- |
| name      | Name of the timeline                                  |
| start     | Start time of the activity. Time / datetime instance. |
| uuid      | UUID of the activity                                  |

Ruby Example:

```ruby
act = get_timeline_activity("RubyTL", 1737132303, "cdb661b4-a65b-44e7-95e2-5e1dba80c782") #=>
# { "name"=>"RubyTL", "updated_at"=>1737128761316084471, "start"=>1737132303, "stop"=>1737135903,
#   "kind"=>"command", "data"=>{"command"=>"INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10", "username"=>"operator"},
#   "scope"=>"DEFAULT", "fulfillment"=>false, "uuid"=>"cdb661b4-a65b-44e7-95e2-5e1dba80c782",
#   "events"=>[{"time"=>1737128761, "event"=>"created"}], "recurring"=>{}}
```

Python Example:

```python
act = get_timeline_activity("PythonTL", 1737133108, "cddbf034-ccdd-4c36-91c2-2653a39b06a5") #=>
# {'name': 'PythonTL', 'updated_at': 1737129508886643928, 'start': 1737133108, 'stop': 1737136708,
#  'kind': 'command', 'data': {'command': 'INST COLLECT with TYPE NORMAL, DURATION 5, TEMP 10', 'username': 'operator'},
#  'scope': 'DEFAULT', 'fulfillment': False, 'uuid': 'cddbf034-ccdd-4c36-91c2-2653a39b06a5',
#  'events': [{'time': 1737129508, 'event': 'created'}], 'recurring': {}}
```

### get_timeline_activities

Get a range of timeline activities between start and stop time. If called without a start / stop time it defaults to 1 week before "now" up to 1 week from "now" (2 weeks total).

Ruby Syntax:

```ruby
get_timeline_activities(name, start: nil, stop: nil, limit: nil)
```

Python Syntax:

```python
get_timeline_activities(name, start=None, stop=None, limit=None)
```

| Parameter | Description                                                                         |
| --------- | ----------------------------------------------------------------------------------- |
| name      | Name of the timeline                                                                |
| start     | Start time of the activities. Time / datetime instance. Defaults to 7 days ago.     |
| stop      | Stop time of the activities. Time / datetime instance. Defaults to 7 days from now. |
| limit     | Maximum number of activities to return. Default is 1 per minute of the time range.  |

Ruby Example:

```ruby
acts = get_timeline_activities("RubyTL", start: Time.now() - 3600, stop: Time.now(), limit: 1000) #=>
# [{ "name"=>"RubyTL", ... }, { "name"=>"RubyTL", ... }]
```

Python Example:

```python
now = datetime.now(timezone.utc)
acts = get_timeline_activities("PythonTL", start=now - timedelta(hours=2), stop=now, limit=1000) #=>
# [{ "name"=>"PythonTL", ... }, { "name"=>"PythonTL", ... }]
```

### delete_timeline_activity

Delete an existing timeline activity.

Ruby / Python Syntax:

```ruby
delete_timeline_activity(name, start, uuid)
```

| Parameter | Description                                           |
| --------- | ----------------------------------------------------- |
| name      | Name of the timeline                                  |
| start     | Start time of the activity. Time / datetime instance. |
| uuid      | UUID of the activity                                  |

Ruby Example:

```ruby
delete_timeline_activity("RubyTL", 1737132303, "cdb661b4-a65b-44e7-95e2-5e1dba80c782")
```

Python Example:

```python
delete_timeline_activity("PythonTL", 1737133108, "cddbf034-ccdd-4c36-91c2-2653a39b06a5")
```

## Metadata

Metadata allows you to mark the regular target / packet data logged in COSMOS with your own fields. This metadata can then be searched and used to filter data when using other COSMOS tools.

### metadata_all

Returns all the metadata that was previously set

Ruby / Python Syntax:

```ruby
metadata_all()
```

| Parameter | Description                                         |
| --------- | --------------------------------------------------- |
| limit     | Amount of metadata items to return. Default is 100. |

Ruby Example:

```ruby
metadata_all(limit: 500)
```

Python Example:

```python
metadata_all(limit='500')
```

### metadata_get

Returns metadata that was previously set

Ruby / Python Syntax:

```ruby
metadata_get(start)
```

| Parameter | Description                                                                       |
| --------- | --------------------------------------------------------------------------------- |
| start     | Named parameter, time at which to retrieve metadata as integer seconds from epoch |

Ruby Example:

```ruby
metadata_get(start: 500)
```

Python Example:

```python
metadata_get(start='500')
```

### metadata_set

Returns metadata that was previously set

Ruby / Python Syntax:

```ruby
metadata_set(<Metadata>, start, color)
```

| Parameter | Description                                                                     |
| --------- | ------------------------------------------------------------------------------- |
| Metadata  | Hash or dict of key value pairs to store as metadata.                           |
| start     | Named parameter, time at which to store metadata. Default is now.               |
| color     | Named parameter, color to display metadata in the calendar. Default is #003784. |

Ruby Example:

```ruby
metadata_set({ 'key' => 'value' })
metadata_set({ 'key' => 'value' }, color: '#ff5252')
```

Python Example:

```python
metadata_set({ 'key': 'value' })
metadata_set({ 'key': 'value' }, color='ff5252')
```

### metadata_update

Updates metadata that was previously set

Ruby / Python Syntax:

```ruby
metadata_update(<Metadata>, start, color)
```

| Parameter | Description                                                                     |
| --------- | ------------------------------------------------------------------------------- |
| Metadata  | Hash or dict of key value pairs to update as metadata.                          |
| start     | Named parameter, time at which to update metadata. Default is latest metadata.  |
| color     | Named parameter, color to display metadata in the calendar. Default is #003784. |

Ruby Example:

```ruby
metadata_update({ 'key' => 'value' })
```

Python Example:

```python
metadata_update({ 'key': 'value' })
```

### metadata_input

Prompts the user to set existing metadata values or create new a new one.

Ruby / Python Example:

```ruby
metadata_input()
```

## Settings

COSMOS has several settings typically accessed through the Admin Settings tab. These APIs allow programmatic access to those same settings.

### list_settings

Return all the current COSMOS setting name. These are the names that should be used in the other APIs.

Ruby Example:

```ruby
puts list_settings() #=> ["pypi_url", "rubygems_url", "source_url", "version"]
```

Python Example:

```python
print(list_settings()) #=> ['pypi_url', 'rubygems_url', 'source_url', 'version']
```

### get_all_settings

Return all the current COSMOS settings along with their values.

Ruby Example:

```ruby
settings = get_all_settings() #=>
# { "version"=>{"name"=>"version", "data"=>"5.11.4-beta0", "updated_at"=>1698074299509456507},
#   "pypi_url"=>{"name"=>"pypi_url", "data"=>"https://pypi.org/simple", "updated_at"=>1698026776574347007},
#   "rubygems_url"=>{"name"=>"rubygems_url", "data"=>"https://rubygems.org", "updated_at"=>1698026776574105465},
#   "source_url"=>{"name"=>"source_url", "data"=>"https://github.com/OpenC3/cosmos", "updated_at"=>1698026776573904132} }
```

Python Example:

```python
settings = get_all_settings() #=>
# { 'version': {'name': 'version', 'data': '5.11.4-beta0', 'updated_at': 1698074299509456507},
#   'pypi_url': {'name': 'pypi_url', 'data': 'https://pypi.org/simple', 'updated_at': 1698026776574347007},
#   'rubygems_url': {'name': 'rubygems_url', 'data': 'https://rubygems.org', 'updated_at': 1698026776574105465},
#   'source_url': {'name': 'source_url', 'data': 'https://github.com/OpenC3/cosmos', 'updated_at': 1698026776573904132} }
```

### get_setting, get_settings

Return the data from the given COSMOS setting. Returns nil (Ruby) or None (Python) if the setting does not exist.

Ruby / Python Syntax:

```ruby
get_setting(<Setting Name>)
get_settings(<Setting Name1>, <Setting Name2>, ...)
```

| Parameter    | Description                   |
| ------------ | ----------------------------- |
| Setting Name | Name of the setting to return |

Ruby Example:

```ruby
setting = get_setting('version') #=> "5.11.4-beta0"
setting = get_settings('version', 'rubygems_url') #=> ["5.11.4-beta0", "https://rubygems.org"]
```

Python Example:

```python
setting = get_setting('version') #=> '5.11.4-beta0'
setting = get_setting('version', 'rubygems_url') #=> ['5.11.4-beta0', 'https://rubygems.org']
```

### set_setting

Sets the given setting value.

:::note Admin Passwork Required
This API is only accessible externally (not within Script Runner) and requires the admin password.
:::

Ruby / Python Syntax:

```ruby
set_setting(<Setting Name>, <Setting Value>)
```

| Parameter     | Description                   |
| ------------- | ----------------------------- |
| Setting Name  | Name of the setting to change |
| Setting Value | Setting value to set          |

Ruby Example:

```ruby
set_setting('rubygems_url', 'https://mygemserver')
```

Python Example:

```python
set_setting('pypi_url', 'https://mypypiserver')
```

## Configuration

Many COSMOS tools have the ability to load and save a configuration. These APIs allow you to programmatically load and save the configuration.

### config_tool_names

List all the configuration tool names which are used as the first parameter in the other APIs.

Ruby Example:

```ruby
names = config_tool_names() #=> ["telemetry_grapher", "data_viewer"]
```

Python Example:

```python
names = config_tool_names() #=> ['telemetry_grapher', 'data_viewer']
```

### list_configs

List all the saved configuration names under the given tool name.

Ruby / Python Syntax:

```ruby
list_configs(<Tool Name>)
```

| Parameter | Description                                           |
| --------- | ----------------------------------------------------- |
| Tool Name | Name of the tool to retrieve configuration names from |

Ruby Example:

```ruby
configs = list_configs('telemetry_grapher') #=> ['adcs', 'temps']
```

Python Example:

```python
configs = list_configs('telemetry_grapher') #=> ['adcs', 'temps']
```

### load_config

Load a particular tool configuration.

:::note Tool Configuration
Tool configurations are not fully documented and subject to change between releases. Only modify values returned by load_config and do not change any keys.
:::

Ruby / Python Syntax:

```ruby
load_config(<Tool Name>, <Configuration Name>)
```

| Parameter          | Description               |
| ------------------ | ------------------------- |
| Tool Name          | Name of the tool          |
| Configuration Name | Name of the configuration |

Ruby / Python Example:

```ruby
config = load_config('telemetry_grapher', 'adcs') #=>
# [ {
#   "items": [
#     {
#       "targetName": "INST",
#       "packetName": "ADCS",
#       "itemName": "CCSDSVER",
# ...
```

### save_config

Save a particular tool configuration.

Ruby / Python Syntax:

```ruby
save_config(<Tool Name>, <Configuration Name>, local_mode)
```

| Parameter          | Description                                     |
| ------------------ | ----------------------------------------------- |
| Tool Name          | Name of the tool                                |
| Configuration Name | Name of the configuration                       |
| local_mode         | Whether to save the configuration in local mode |

Ruby / Python Example:

```ruby
save_config('telemetry_grapher', 'adcs', config)
```

### delete_config

Delete a particular tool configuration.

Ruby / Python Syntax:

```ruby
delete_config(<Tool Name>, <Configuration Name>, local_mode)
```

| Parameter          | Description                                       |
| ------------------ | ------------------------------------------------- |
| Tool Name          | Name of the tool                                  |
| Configuration Name | Name of the configuration                         |
| local_mode         | Whether to delete the configuration in local mode |

Ruby / Python Example:

```ruby
delete_config('telemetry_grapher', 'adcs')
```
