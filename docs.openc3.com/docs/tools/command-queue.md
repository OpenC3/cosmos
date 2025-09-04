---
title: Command Queue (Enterprise)
description: See all the command queues and interact with commands
sidebar_custom_props:
  myEmoji: 📥
---

## Introduction

Command Queue provides the ability to see the status of all queues created by the [Command Queue](/docs/guides/scripting-api#command-queues) API methods.

![Command Queue](/img/command_queue/command_queue.png)

### Manipulating Queues

You can create a new Command Queue by clicking + and delete one by clicking the trash. Different queues can be selected using the Queue selection. You can change the queue state by clicking the Hold / Release / Disable button group. Note that the current mode is indicated by which button is highlighted.

The queue starts out in Hold mode by default which means that commands are added to the queue in FIFO order and are not executed. When the queue is placed into Release mode, a backend microservice starts to execute the commands as fast as possible while still doing any [validation](/docs/configuration/command#validator) that is defined. When the queue is put into Disable mode, all commands sent to the queue will fail and an exception is raised in an executing script.

You add commands to the queue by specifying the queue as a keyword argument to the normal `cmd` [APIs](/docs/guides/scripting-api#commands).

<Tabs groupId="script-language">
<TabItem value="ruby" label="Ruby Example">

```ruby
cmd("INST ABORT", queue: "TEST")
```

</TabItem>

<TabItem value="python" label="Python Example">

```python
cmd("INST ABORT", queue="TEST")
```

</TabItem>
</Tabs>

You can manually add commands to the queue by clicking the `Add Command` button which brings up a command editor dialog similar
to Command Sender that allows you to select a command and fill out any parameters.

![Add Command](/img/command_queue/add_command.png)

## Commands Table

The commands table is sorted by the Index and lists the Time, User (or process), the Command, and Actions.

The Index is the command index when the command was added to the queue. This will normally increment by 1 althought commands can be deleted or executed out of order which will not reorder the queue. If the queue is emptied the index starts over at 1.

The Time is the time the command was last modified. This is originally the time the command was added to the queue but updates as commands are edited.

The User is the person to add the command to the queue or the last to edit it.

The Command is the command as sent via [`cmd_no_hazarous_check`](/docs/guides/scripting-api#cmd_no_hazardous_check) in a COSMOS script.

The Actions column allows you to remove and execute a command (play button), edit a command (pencil button), or delete a command from the queue (trash button).

You can download the list of commands as a CSV file by clicking the Download button next to the Search box.
