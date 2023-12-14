---
title: Calendar (Enterprise)
---

## Introduction

Calendar visualizes metadata, narrative, and timeline information in one easy to understand place. Timelines allow for the simple execution of commands and scripts based on future dates and times.

![Calendar](/img/v5/calendar/calendar.png)

Calendar events can also be viewed in a list format which supports pagination for listing both past and future events.

![List View](/img/v5/calendar/list_view.png)

## Types of Events

- Metadata

- Narrative

- Activity

### Metadata

Metadata allows you to record arbitrary data into the COSMOS system. For example, you could ask the user for inputs which fall outside the available target telemetry including user defined IDs, environmental factors, procedural steps, etc. This allows for searching metadata based on these fields and correlating the related telemetry data.

### Narrative

A simple way to record events on the calendar, for example a test window or anything else...

### Activity

Scheduled on a timeline these can run single commands or run a script.

### Adding Timelines

Adding a Timeline to COSMOS.

- Each timeline consists of several threads so be careful of your compute resources you have as you can overwhelm COSMOS with lots of these.
- Note you can not have overlapping activities on a single calendar.

### Timeline Implementation Details

When a user creates a timeline, a new timeline microservice starts. The timeline microservice is the main thread of execution for the timeline. This starts a scheduler manager thread. The scheduler manger thread contains a thread pool that hosts more then one thread to run the activity. The scheduler manger will evaluate the schedule and based on the start time of the activity it will add the activity to the queue.

The main thread will block on the web socket to listen to request changes to the timeline, these could be adding, removing, or updating activities. The main thread will make the changes to the in memory schedule if these changes are within the hour of the current time. When the web socket gets an update it has an action lookup table. These actions are "created", "updated", "deleted", ect... Some actions require updating the schedule from the database to ensure the schedule and the database are always in sync.

The schedule thread checks every second to make sure if a task can be run. If the start time is equal or less then the last 15 seconds it will then check the previously queued jobs list in the schedule. If the activity has not been queued and is not fulfilled the activity will be queued, this adds an event to the activity but is not saved to the database.

The workers block on the queue until an activity is placed on the queue. Once a job is pulled from the queue they check the type and run the activity. The thread will mark the activity fulfillment true and update the database record with the complete. If the worker gets an error while trying to run the task the activity will NOT be fulfilled and record the error in the database.

![Timeline Lifecycle](/img/v5/calendar/timeline_lifecycle.png)
