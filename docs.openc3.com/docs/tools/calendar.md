---
title: Calendar (Enterprise)
description: Calendar visualization of metadata, notes, and timelines
sidebar_custom_props:
  myEmoji: 🗓️
---

## Introduction

Calendar visualizes metadata, notes, and timeline information in one easy to understand place. Timelines allow for the simple execution of commands and scripts based on future dates and times.

![Calendar](/img/calendar/blank_calendar.png)

### Adding Timelines

Adding a Timeline to COSMOS is as simple as clicking Create -> Timeline and giving it a unique name. Timelines can be created for organizational purposes or for overlapping activities as no activities can overlap on a given timeline. However, each additional timeline consists of several threads so only create timelines as necessary.

![Timeline](/img/calendar/timeline.png)

## Types of Events

### Metadata

Metadata allows you to record arbitrary data into the COSMOS system. For example, you could ask the user for inputs which fall outside the available target telemetry including operators, environmental factors, procedural steps, etc. This allows for searching metadata based on these fields and correlating the related telemetry data.

You can create a new metadata item from either the Create menu or by right-clicking on the calendar in the given time slot you want the metadata item to appear. Note that metadata entries only have a start time, they do not have an end time.

![CreateMetadata1](/img/calendar/create_metadata1.png)

You then add key / value pairs for all the metadata items you want to create.

![CreateMetadata2](/img/calendar/create_metadata2.png)

### Note

Notes require both a start and end time.

![CreateNote1](/img/calendar/create_note1.png)

You then record the note to create the note event on the calendar.

![CreateNote2](/img/calendar/create_note2.png)

### Activity

Scheduled on a timeline, activities take both a start and end time.

![CreateActivity1](/img/calendar/create_activity1.png)

Activities can run single commands, run a script, or simply "Reserve" space on the calendar for reference or other bookkeeping.

![CreateActivity2](/img/calendar/create_activity2.png)

When calendar activities are scheduled they appear with a status icon, compliant with the AstroUX standards. As calendar activities are executed, there are lifecycle hooks set to track and display the latest status update from the executed script or command. Green circle will signify nominal (created, started, completed states), yellow square signifies warnings (script stopped, paused, hit breakpoint, completed with errors, disabled), and red triangle signifies error states (error, failed, crashed). Clicking into a Calendar Activity will show the details of the status updates.

![Calendar](/img/calendar/calendar.png)

### Gantt View

Calendar events can be viewed as a Gantt chart view via the "Gantt" button. Gantt view shows a day's worth of activity, and users can click the next day / previous day buttons to view other day's events.

![Gantt View](/img/calendar/gantt_view.png)

### List View

Calendar events can be viewed as a List view via the "List" button. List view shows a day's worth of activity, and users can click the next day / previous day buttons to view other day's events.

![List View](/img/calendar/list_view.png)

### Settings

By clicking File -> Options, the options can be modified. The configurations include:
- Calendar view can be modified to be Sunday - Saturday view or Monday - Sunday
- The default view modified to Calendar, Gantt, or List
- The progress icon indicating the script is currently running can be modified

![Options](/img/calendar/options.png)

## Timeline Implementation Details

When a user creates a timeline, a new timeline microservice starts. The timeline microservice is the main thread of execution for the timeline. This starts a scheduler manager thread. The scheduler manager thread contains a thread pool that hosts more than one thread to run the activity. The scheduler manager will evaluate the schedule and based on the start time of the activity it will add the activity to the queue.

The main thread will block on the web socket to listen to request changes to the timeline, these could be adding, removing, or updating activities. The main thread will make the changes to the in memory schedule if these changes are within the hour of the current time. When the web socket gets an update it has an action lookup table. These actions are "created", "updated", "deleted", etc... Some actions require updating the schedule from the database to ensure the schedule and the database are always in sync.

The schedule thread checks every second to make sure if a task can be run. If the start time is equal or less then the last 15 seconds it will then check the previously queued jobs list in the schedule. If the activity has not been queued and is not fulfilled the activity will be queued, this adds an event to the activity but is not saved to the database.

The workers block on the queue until an activity is placed on the queue. Once a job is pulled from the queue they check the type and run the activity. The thread will mark the activity fulfillment true and update the database record with the complete. If the worker gets an error while trying to run the task the activity will NOT be fulfilled and record the error in the database.

![Timeline Lifecycle](/img/calendar/timeline_lifecycle.png)
