---
title: Autonomic (Enterprise)
description: Automated execution of commands and scripts
sidebar_custom_props:
  myEmoji: 🛠️
---

## Introduction

Autonomic allows for the automated execution of commands and scripts based on user-defined rules.

### Overview

Autonomic operates with some basic building blocks: Trigger Groups, Triggers, and Reactions. Triggers are simply logical blocks which evaluate true or false. Reactions can be linked to one or many Triggers and specify an action to perform. Together they allow for an action to be taken based on anything going on in your system.

![Autonomic](/img/autonomic/autonomic.png)

### TriggerGroups

Triggers are organized into groups, these groups are both for organization and to ensure that we can scale. It also allows triggers to be evaluated independently and simultaneously and can be useful for overlapping or high priority triggers. However, each trigger group spawns system resources so they should only be created as needed.

![TriggerGroups](/img/autonomic/trigger_groups.png)

### Triggers

Triggers are logical components that are evaluated to true or false. Creating a trigger is like specifying an equation to evaluate. The trigger creation dialog specifies the Trigger Group which owns the trigger and the "left operand". This can be a telemetry item or an existing trigger.

![CreateTrigger1](/img/autonomic/create_trigger1.png)

Once you've chosen the "left operand" you need to choose the operator.

![CreateTrigger2](/img/autonomic/create_trigger2.png)

Finally you choose the "right operand" which in this case is a simple value.

![CreateTrigger3](/img/autonomic/create_trigger3.png)

After the trigger is created it is displayed in Autonomic and waits to be activated by the given logic. Active triggers are highlighted in the list.

![CreateTrigger3](/img/autonomic/enabled_trigger.png)

Triggers can also be manually disabled and enabled by clicking the plug icon.

![CreateTrigger3](/img/autonomic/disable_trigger.png)

Note in the above screenshot the Events which track everything about the trigger.

### Reactions

Reactions wait for triggers to be evaluated to true and perform actions such as sending a command or running a script. Reactions can not exist without a corresponding trigger. The reaction creation dialog specifies whether to treat the trigger as an Edge or Level. It then allows you to select which trigger(s) the reaction will react to. Selecting multiple triggers allows any of the triggers to trigger the reaction (Note: Creating a reaction which responds to Trigger A AND Trigger B is done by creating additional triggers).

![CreateReaction1](/img/autonomic/create_reaction1.png)

After the triggers are specified, the dialog prompts for the actions to take. You can either send a command, run a script, or simply push a notification. Commands and scripts can also optionally push a notification. In this example a script is specified with a notification at the WARN level.

:::warning Spawning Scripts
Be aware of how and when you spawn scripts and whether they are running to completion. Spawning a faulty script can lead to many unfinished scripts consuming resources.
:::

![CreateReaction2](/img/autonomic/create_reaction2.png)

Finally the snooze setting is specified. Snooze is the number of seconds after the reaction runs before the reaction will be allowed to run again. This is especially important in Level triggers where if the trigger remains active the reaction can run continuously.

![CreateReaction3](/img/autonomic/create_reaction3.png)

Once the reaction is created it is listed in the interface.

![InitialReaction](/img/autonomic/initial_reaction.png)

When the reaction runs the "State" changes to the snooze icon and the "Snooze Until" is updated to indicate the reaction is waiting before being allowed to run again.

![SnoozedReaction](/img/autonomic/snoozed_reaction.png)
