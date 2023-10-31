<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <top-bar :menus="menus" :title="title" />
    <v-container dense>
      <v-row>
        <v-col class="pa-1">
          <calendar-toolbar
            v-model="calendarConfiguration"
            :timelines="timelines"
            @action="actionHandler"
            @update="refresh"
          />
        </v-col>
      </v-row>
      <v-row>
        <v-col style="max-width: 300px">
          <mini-calendar v-model="calendarConfiguration" />
          <calendar-selector
            class="pt-3"
            v-model="selectedCalendars"
            :timelines="timelines"
          />
        </v-col>
        <v-col class="pa-1">
          <event-calendar
            v-model="calendarConfiguration"
            ref="eventCalendar"
            :events="calendarEvents"
            :timelines="timelines"
            @update="refresh"
          />
        </v-col>
      </v-row>
    </v-container>
    <environment-dialog v-model="showEnvironmentDialog" />
    <event-list-dialog
      v-if="showEventTableDialog"
      v-model="showEventTableDialog"
      :events="calendarEvents"
      :utc="utc"
      @update="$emit('update')"
    />
  </div>
</template>

<script>
import { parse, addDays, subDays, format } from 'date-fns'
import Api from '@openc3/tool-common/src/services/api'
import Cable from '@openc3/tool-common/src/services/cable.js'
import TopBar from '@openc3/tool-common/src/components/TopBar'

import EventCalendar from '@/tools/Calendar/EventCalendar'
import CalendarToolbar from '@/tools/Calendar/CalendarToolbar'
import CalendarSelector from '@/tools/Calendar/CalendarSelector'
import EnvironmentDialog from '@openc3/tool-common/src/components/EnvironmentDialog'
import EventListDialog from '@openc3/tool-common/src/tools/calendar/Dialogs/EventListDialog'
import MiniCalendar from '@/tools/Calendar/MiniCalendar'
import TimelineMethods from '@openc3/tool-common/src/tools/calendar/Filters/timeFilters.js'
import { getTimelineEvents } from '@/tools/Calendar/Filters/timelineFilters.js'
import { getCalendarEvents } from '@/tools/Calendar/Filters/calendarFilters.js'
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'

export default {
  components: {
    EventCalendar,
    CalendarToolbar,
    CalendarSelector,
    MiniCalendar,
    TopBar,
    EnvironmentDialog,
    EventListDialog,
  },
  mixins: [TimelineMethods],
  data() {
    return {
      title: 'COSMOS Calendar',
      timelines: [],
      selectedCalendars: [],
      activities: {},
      calendarEvents: [],
      events: { metadata: [], note: [] },
      calendarConfiguration: {
        utc: false,
        focus: '',
        type: '4day',
      },
      channels: ['TimelineEventsChannel', 'CalendarEventsChannel'],
      cable: new Cable(),
      subscriptions: [],
      api: null,
      showEventTableDialog: false,
      showEnvironmentDialog: false,
    }
  },
  computed: {
    menus: function () {
      return [
        {
          label: 'File',
          items: [
            {
              label: 'Global Environment',
              icon: 'mdi-library',
              command: () => {
                this.showEnvironmentDialog = !this.showEnvironmentDialog
              },
            },
            {
              label: 'Refresh Display',
              icon: 'mdi-refresh',
              command: () => {
                this.refresh()
              },
            },
            {
              label: 'Show Table Display',
              icon: 'mdi-timetable',
              command: () => {
                this.showEventTableDialog = !this.showEventTableDialog
              },
            },
            {
              label: 'Toggle UTC Display',
              icon: 'mdi-clock',
              command: () => {
                this.calendarConfiguration.utc = !this.calendarConfiguration.utc
              },
            },
            {
              label: 'Download Event List',
              icon: 'mdi-download',
              command: () => {
                this.downloadEvents()
              },
            },
          ],
        },
      ]
    },
    eventHandlerFunctions: function () {
      return {
        timeline: {
          created: this.createdTimeline,
          refresh: this.refreshTimeline,
          updated: this.updatedTimeline,
          deleted: this.deletedTimeline,
        },
        activity: {
          event: this.eventActivity,
          created: this.createdActivity,
          updated: this.updatedActivity,
          deleted: this.deletedActivity,
        },
        calendar: {
          created: this.createdEvent,
          updated: this.updatedEvent,
          deleted: this.deletedEvent,
        },
      }
    },
  },
  watch: {
    selectedCalendars: {
      immediate: true,
      handler: function () {
        this.updateActivities()
      },
    },
    events: {
      immediate: true,
      handler: function () {
        this.rebuildCalendarEvents()
      },
    },
    activities: {
      immediate: true,
      handler: function () {
        this.rebuildCalendarEvents()
      },
    },
    calendarConfiguration: {
      immediate: true,
      handler: function () {
        this.refresh()
      },
    },
  },
  created: function () {
    // Ensure Offline Access Is Setup For the Current User
    this.api = new OpenC3Api()
    this.api.ensure_offline_access()
    this.subscribe()
    this.getTimelines()
    this.updateMetadata()
    this.updateNotes()
  },
  destroyed: function () {
    this.subscriptions.forEach((subscription) => {
      subscription.unsubscribe()
    })
    this.cable.disconnect()
  },
  methods: {
    downloadEvents: function () {
      const output = JSON.stringify(this.calendarEvents, null, 2)
      const blob = new Blob([output], {
        type: 'application/json',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute(
        'download',
        format(Date.now(), 'yyyy_MM_dd_HH_mm_ss') + '_calendar_events.json',
      )
      link.click()
    },
    actionHandler: function (event) {
      if (event.method === 'next') {
        this.$refs.eventCalendar.next()
      } else if (event.method === 'prev') {
        this.$refs.eventCalendar.prev()
      }
    },
    rebuildCalendarEvents: function () {
      const timelineEvents = getTimelineEvents(
        this.selectedCalendars,
        this.activities,
      )
      const calendarEvents = getCalendarEvents(
        this.selectedCalendars,
        this.events,
      )
      this.calendarEvents = timelineEvents.concat(calendarEvents)
    },
    refresh: function () {
      this.updateActivities()
      this.updateMetadata()
      this.updateNotes()
    },
    getTimelines: function () {
      Api.get('/openc3-api/timeline').then((response) => {
        const timelineResponse = response.data
        timelineResponse.forEach((timeline) => {
          timeline.messages = 0
          timeline.type = 'timeline'
        })
        this.timelines = timelineResponse
      })
    },
    updateActivities: function (name = null) {
      // this.activities = {
      //   "timelineName": [activity1, activity2, etc],
      //   "anotherTimeline": etc
      // }
      const noLongerNeeded = Object.keys(this.activities).filter(
        (timeline) => !this.selectedCalendars.includes(timeline),
      )
      for (const timeline of noLongerNeeded) {
        delete this.activities[timeline.name]
      }
      if (noLongerNeeded) {
        this.activities = { ...this.activities } // New object reference to force reactivity
      }
      let timelinesToUpdate
      if (name) {
        const inputTimeline = this.timelines.find(
          (timeline) => timeline.name === name,
        )
        timelinesToUpdate = inputTimeline && [inputTimeline]
      } else {
        timelinesToUpdate = this.selectedCalendars.filter(
          (calendar) => calendar.type === 'timeline',
        )
      }
      let start = null
      let stop = null
      if (this.calendarConfiguration.focus) {
        let date = parse(
          this.calendarConfiguration.focus,
          'yyyy-MM-dd',
          new Date(),
        )
        // We only ever display 1 week so get plus / minus 7 days
        start = subDays(date, 7)
        stop = addDays(date, 7)
      }
      for (const timeline of timelinesToUpdate) {
        timeline.messages = 0
        let url = `/openc3-api/timeline/${timeline.name}/activities`
        if (start && stop) {
          url += `?start=${format(start, 'yyyy-MM-dd')}&stop=${format(
            stop,
            'yyyy-MM-dd',
          )}`
        }
        Api.get(url).then((response) => {
          this.activities[timeline.name] = response.data
          this.activities = { ...this.activities } // New object reference to force reactivity
        })
      }
    },
    updateMetadata: function () {
      // this.events = {
      //   "metadata": [event1, event2, etc],
      //   "note": etc
      // }
      Api.get(`/openc3-api/metadata`).then((response) => {
        this.events = {
          ...this.events,
          metadata: response.data,
        }
      })
    },
    updateNotes: function () {
      // this.events = {
      //   "note": [event1, event2, etc],
      //   "metadata": etc
      // }
      Api.get(`/openc3-api/notes`).then((response) => {
        this.events = {
          ...this.events,
          note: response.data,
        }
      })
    },
    subscribe: function () {
      this.channels.forEach((channel) => {
        this.cable
          .createSubscription(channel, window.openc3Scope, {
            received: (data) => this.received(data),
          })
          .then((subscription) => {
            this.subscriptions.push(subscription)
          })
      })
    },
    received: function (parsed) {
      this.cable.recordPing()
      parsed.forEach((event) => {
        event.data = JSON.parse(event.data)
        this.eventHandlerFunctions[event.type][event.kind](event)
      })
    },
    refreshTimeline: function (event) {
      this.updateActivities(event.timeline)
    },
    createdTimeline: function (event) {
      event.data.messages = 0
      event.data.type = 'timeline'
      this.timelines.push(event.data)
      this.activities[event.timeline] = []
    },
    updatedTimeline: function (event) {
      const timelineIndex = this.timelines.findIndex(
        (timeline) => timeline.name === event.timeline,
      )
      this.timelines[timelineIndex] = event.data
      this.timelines = this.timelines.slice()
      this.activities = { ...this.activities }
    },
    deletedTimeline: function (event) {
      const timelineIndex = this.timelines.findIndex(
        (timeline) => timeline.name === event.timeline,
      )
      this.timelines.splice(timelineIndex, timelineIndex >= 0 ? 1 : 0)
      const checkedIndex = this.selectedCalendars.findIndex(
        (timeline) => timeline.name === event.timeline,
      )
      this.selectedCalendars.splice(checkedIndex, checkedIndex >= 0 ? 1 : 0)
    },
    createdActivity: function (event) {
      this.incrementTimelineMessages(event.timeline)
      if (this.activities.hasOwnProperty(event.timeline)) {
        this.activities[event.timeline].push(event.data)
        this.activities = { ...this.activities }
      }
    },
    eventActivity: function (event) {
      this.incrementTimelineMessages(event.timeline)
      if (this.activities.hasOwnProperty(event.timeline)) {
        const activityIndex = this.activities[event.timeline].findIndex(
          (activity) => activity.start === event.data.start,
        )
        this.activities[event.timeline][activityIndex] = event.data
        this.activities = { ...this.activities }
      }
    },
    updatedActivity: function (event) {
      event.extra = parseInt(event.extra)
      this.incrementTimelineMessages(event.timeline)
      if (this.activities.hasOwnProperty(event.timeline)) {
        const activityIndex = this.activities[event.timeline].findIndex(
          (activity) => activity.start === event.extra,
        )
        this.activities[event.timeline][activityIndex] = event.data
        this.activities = { ...this.activities }
      }
    },
    deletedActivity: function (event) {
      this.incrementTimelineMessages(event.timeline)
      if (this.activities.hasOwnProperty(event.timeline)) {
        const activityIndex = this.activities[event.timeline].findIndex(
          (activity) => activity.start === event.data.start,
        )
        this.activities[event.timeline].splice(
          activityIndex,
          activityIndex >= 0 ? 1 : 0,
        )
        this.activities = { ...this.activities }
      }
    },
    incrementTimelineMessages: function (timelineName) {
      if (!this.selectedCalendars.includes(timelineName)) {
        this.timelines.find((timeline) => timeline.name === timelineName)
          .messages++
      }
    },
    createdEvent: function (event) {
      const eventType = event.data.type
      this.events[eventType].push(event.data)
      this.events = { ...this.events }
    },
    updatedEvent: function (event) {
      event.extra = parseInt(event.extra)
      const eventType = event.data.type
      const eventIndex = this.events[eventType].findIndex(
        (calendarEvent) => calendarEvent.start === event.extra,
      )
      this.events[eventType][eventIndex] = event.data
      this.events = { ...this.events }
    },
    deletedEvent: function (event) {
      const eventType = event.data.type
      const eventIndex = this.events[eventType].findIndex(
        (calendarEvent) => calendarEvent.start === event.data.start,
      )
      this.events[eventType].splice(eventIndex, eventIndex >= 0 ? 1 : 0)
      this.events = { ...this.events }
    },
  },
}
</script>
