---
title: Command Sender
description: Send individual commands
sidebar_custom_props:
  myEmoji: 📢
---

## Introduction

Command Sender provides the ability to send any command defined by COSMOS. Commands are selected using the Target and Packet drop down fields which populate the command parameters (if any). Every command sent is added to the Command History, newest first. Clicking a command in the history loads it back into the form so it can be edited and sent again. Related telemetry or screens are displayed next to the command history.

![Command Sender](/img/command_sender/command_sender.png)

## Command Sender Menus

### File Menu Items

- Paste a command to load it into the form (see [Pasting Commands](#pasting-commands))
- Clear the command history

### Mode Menu Items

{/* Image sized to match up with bullets */}

<img
  src={require("@site/static/img/command_sender/mode_menu.png").default}
  alt="Mode Menu"
  style={{ float: "left", "margin-right": 50 + "px", height: 150 + "px" }}
/>

- Ignores parameter range checking
- Displays parameter state values in hex
- Shows ignored parameters
- Disables all parameter conversions
- Disables command [validators](../configuration/command#validator)

The Mode menu always determines how a command is sent, including commands loaded from the history or pasted in.

### Help Menu Items

- Lists the keyboard shortcuts
- Explains how to use Command Sender: sending, hazardous commands, the history and pasting commands

## Sending Commands

Select a command by first selecting the target from the Select Target drop down. Changing the target automatically updates the Select Packet options to only display commands from that target. If the command has parameters a table is generated with all the parameters. If command queues are configured, the Select Queue drop down sends the command to a queue instead of directly to the target.

![INST COLLECT](/img/command_sender/inst_collect.png)

Clicking on a parameter with States (like TYPE in the above example) brings up a drop down to select a state. Selecting a state populates the value field next to it.

![States](/img/command_sender/collect_states.png)

The Send button is the only way to send a command. Sending a command updates the status next to the Send button and adds the command to the Command History. Pressing Send several times updates the status with the number of commands sent.

### Command History

The Command History lists the commands sent from Command Sender, newest first, with the time each was sent. Sending the same command again adds another entry. It keeps the 500 most recent commands: once it is full, each new command removes the oldest. The history is kept in the browser and persists across sessions until it is cleared with the delete button or File → Clear History.

Clicking a command in the history loads it into the form above, selecting the target, packet and queue (None if it was sent without one) and filling in every parameter value. Nothing is sent until you press Send, so you can review or change parameters first. The copy button at the end of each entry copies the command to the clipboard, ready to paste into a script.

![History](/img/command_sender/history.png)

:::note[Obfuscated parameter]
Parameters marked as [obfuscated](../configuration/command.md#obfuscate) are shown as `*****` in the history. When such a command is loaded, these parameters are left empty and Send asks for them, so the defaults are never sent in their place.
:::

### Pasting Commands

To send a command from a procedure or script, click the clipboard button next to Send (or select File → Paste Command) and paste the command. You can also press Ctrl+V (⌘V on macOS) when no field is selected to open the paste box with the command already pasted. The script form with single or double quotes, e.g. `cmd("INST COLLECT with TYPE 'NORMAL', DURATION 5")`, the Ruby form without parentheses, and the bare command text, e.g. `INST COLLECT with TYPE 'NORMAL', DURATION 5`, are all accepted, and a trailing comment is ignored. Press Load (or Enter) to load the command into the form, then press Send to send it.

![Paste Command](/img/command_sender/paste_command.png)

A `queue` keyword selects that queue if it exists; otherwise the queue is left as None and the status says so. Without a `queue` keyword the queue is None, as it would be for the script. Other parts of the command that the Mode menu controls, such as the method (`cmd_no_range_check`, `cmd_raw`, etc.) or a `validate` keyword, are not applied. The status lists anything that was not applied so you can change the Mode menu if needed.

### Keyboard Shortcuts

These work when no field is selected and no dialog is open. None of them send a command, only the Send button does.

| Shortcut                      | Action                                                   |
| ----------------------------- | -------------------------------------------------------- |
| Ctrl+V (⌘V on macOS)          | Open the paste box with the clipboard's command          |
| Alt+↓ (⌥↓ on macOS)           | Load the next older command in the history into the form |
| Alt+↑ (⌥↑ on macOS)           | Load the next newer command in the history into the form |
| Enter (in the paste box)      | Load the pasted command into the form                    |
| Esc (in the hazardous dialog) | Cancel without sending                                   |

### Hazardous Commands

Sending [hazardous](../configuration/command.md#hazardous) commands will prompt the user whether to send the command. Command Sender checks the command as parameters change, outlining the command in yellow and turning the Send button yellow before it is pressed. Any hazardous description is shown next to the Send button.

![INST CLEAR](/img/command_sender/inst_clear.png)

Commands can also have hazardous [states](../configuration/command.md#state) (INST COLLECT with TYPE SPECIAL) which also prompt the user. Ignoring range checks or disabling parameter conversions in the Mode menu makes every command prompt the user, since either can bypass what makes a command safe. In this example, we've also checked all the menu options to show ignored parameters, display state values in hex (see SPECIAL, 0x1), disabled range checking (DURATION 1000), and disabled parameter conversions.

![INST COLLECT Hazardous](/img/command_sender/inst_collect_hazardous.png)

Selecting Send will send the command and update the history with all the parameters shown. Note that when writing Scripts all parameters are optional unless explicitly marked [required](../configuration/command.md#required).
