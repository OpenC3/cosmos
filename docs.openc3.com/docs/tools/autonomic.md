---
title: Autonomic
---

## Introduction

Autonomic allows for the simple execution of commands and scripts based on user-defined rules.

### Overview

Autonomic operates with some basic building blocks: Trigger Groups, Triggers, and Reactions. Triggers are simply logical blocks which evaluate true or false. Reactions can be linked to one or many Triggers and specify an action to perform. Together they allow for an action to be taken based on anything going on in your system.

![Autonomic](/img/v5/autonomic/autonomic.png)

### TriggerGroups

Triggers are organized into groups, these groups are to ensure that we can scale as the number of triggers with the incoming telemetry. Each group consists of several threads so be careful of your compute resources you have as you can overwhelm COSMOS with lots of these.

```json
{
  "name": "system42"
}
```

### Triggers

Triggers are logical components that are evaluated to true or false.

![Triggers](/img/v5/autonomic/triggers.png)

```json
{
  "group": "system42",
  "description": "TBD",
  "left": {
    "type": "item",
    "target": "INST",
    "packet": "ADCS",
    "item": "POSX",
    "raw": true
  },
  "operation": ">",
  "right": {
    "type": "value",
    "value": 0
  }
}
```

### Reactions

Reactions wait for triggers to be evaluated to true and perform actions such as sending a command or running a script.

![Reactions](/img/v5/autonomic/reactions.png)

```json
{
  "description": "INST command",
  "snooze": 300,
  "review": true,
  "triggers": [
    {
      "name": "123456",
      "group": "system42"
    }
  ],
  "actions": [
    {
      "type": "command",
      "command": "INST CLEAR"
    }
  ]
}
```
