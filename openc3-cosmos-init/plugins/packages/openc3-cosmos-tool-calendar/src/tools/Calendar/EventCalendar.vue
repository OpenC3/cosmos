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
    <v-sheet height="800" class="mt-1">
      <v-calendar
        v-model="focus"
        ref="mainCalendar"
        color="primary"
        :events="modEvents"
        :event-color="getEventColor"
        :type="type"
        event-overlap-mode="column"
        @click:event="showEvent"
        @click:more="viewDay"
        @click:date="viewDay"
        @contextmenu:time="showContextMenu"
      >
        <template v-slot:event="{ event }">
          <span class="v-event-summary"
            ><strong>{{ event.name }}</strong>
            {{ event.start | time(calendarConfiguration.utc) | hourMin }}
            <v-icon
              v-if="event.activity"
              :color="eventStatusColor(event)"
              class="event-status"
              >{{ eventStatusIcon(event) }}</v-icon
            >
          </span>
        </template>
      </v-calendar>
      <v-menu
        class="centered"
        v-model="selectedOpen"
        :close-on-content-click="false"
        :activator="selectedElement"
        attach=".v-calendar-daily"
      >
        <event-dialog
          v-model="selectedOpen"
          :event="selectedEvent"
          :utc="utc"
          @update="$emit('update')"
          @close="close"
        />
      </v-menu>
    </v-sheet>
    <!-- MENUS -->
    <v-menu
      v-model="contextMenuShown"
      :position-x="x"
      :position-y="y"
      absolute
      offset-y
    >
      <v-list>
        <v-list-item @click.stop="showActivityCreateDialog = true">
          <v-list-item-title>Create Activity</v-list-item-title>
        </v-list-item>
        <v-list-item @click.stop="showMetadataCreateDialog = true">
          <v-list-item-title>Create Metadata</v-list-item-title>
        </v-list-item>
        <v-list-item @click.stop="showNoteCreateDialog = true">
          <v-list-item-title>Create Note</v-list-item-title>
        </v-list-item>
      </v-list>
    </v-menu>
    <activity-create-dialog
      v-if="showActivityCreateDialog"
      v-model="showActivityCreateDialog"
      :timelines="timelines"
      :date="selectedDate"
      :time="selectedTime"
      @update="$emit('update')"
    />
    <metadata-create-dialog
      v-if="showMetadataCreateDialog"
      v-model="showMetadataCreateDialog"
      :date="selectedDate"
      :time="selectedTime"
      @update="$emit('update')"
    />
    <note-create-dialog
      v-if="showNoteCreateDialog"
      v-model="showNoteCreateDialog"
      :date="selectedDate"
      :time="selectedTime"
      @update="$emit('update')"
    />
  </div>
</template>

<script>
import EventDialog from '@/tools/Calendar/Dialogs/EventDialog'
import TimeFilters from '@openc3/tool-common/src/tools/calendar/Filters/timeFilters.js'
import ActivityCreateDialog from '@/tools/Calendar/Dialogs/ActivityCreateDialog'
import MetadataCreateDialog from '@openc3/tool-common/src/tools/calendar/Dialogs/MetadataCreateDialog'
import NoteCreateDialog from '@/tools/Calendar/Dialogs/NoteCreateDialog'

export default {
  components: {
    EventDialog,
    ActivityCreateDialog,
    MetadataCreateDialog,
    NoteCreateDialog,
  },
  mixins: [TimeFilters],
  props: {
    timelines: {
      type: Array,
      required: true,
    },
    events: {
      type: Array,
      required: true,
    },
    value: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      x: 0,
      y: 0,
      selectedEvent: null,
      selectedElement: null,
      selectedOpen: false,
      showCreateDialog: false,
      showEventDialog: false,
      showUpdateDialog: false,
      contextMenuShown: false,
      showActivityCreateDialog: false,
      showMetadataCreateDialog: false,
      showNoteCreateDialog: false,
      selectedDate: null,
      selectedTime: null,
    }
  },
  watch: {
    events: function () {
      if (this.ready) {
        this.$refs.mainCalendar.checkChange()
      }
    },
  },
  computed: {
    // Matches states in ActivityEventTimeline
    states: function () {
      return {
        completed: {
          icon: 'mdi-check-circle',
          color: 'success',
        },
        failed: {
          icon: 'mdi-alert-circle',
          color: 'error',
        },
        updated: {
          icon: 'mdi-star-four-points-circle',
          color: 'success',
        },
        queued: {
          icon: 'mdi-check-underline-circle',
          color: 'success',
        },
        created: {
          icon: 'mdi-checkbox-blank-circle',
          color: 'success',
        },
      }
    },
    modEvents: function () {
      this.events.forEach((event) => {
        let start = Date.parse(event.start)
        let end = Date.parse(event.end)
        if (start === end) {
          // This allows the calendar to size events so they don't totally overlap
          event.end.setSeconds(event.end.getSeconds() + 900)
        }
      })
      return this.events
    },
    cal: function () {
      return this.$refs.mainCalendar
    },
    nowY: function () {
      return this.ready ? this.cal.timeToY(this.cal.times.now) + 'px' : '-10px'
    },
    utc: {
      get() {
        return this.value.utc
      },
      set(value) {
        this.$emit('input', { ...this.value, utc: value }) // input is the default event when using v-model
      },
    },
    focus: {
      get() {
        return this.value.focus
      },
      set(value) {
        this.$emit('input', { ...this.value, focus: value }) // input is the default event when using v-model
      },
    },
    type: {
      get() {
        return this.value.type
      },
      set(value) {
        this.$emit('input', { ...this.value, type: value }) // input is the default event when using v-model
      },
    },
    calendarConfiguration: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
  },
  mounted() {
    this.ready = true
    this.scrollToTime()
    this.updateTime()
    this.cal.checkChange()
  },
  methods: {
    showContextMenu(event, mouseEvent) {
      mouseEvent.preventDefault()
      this.contextMenuShown = false
      this.x = mouseEvent.clientX
      this.y = mouseEvent.clientY
      this.selectedDate = event.date
      // event.time is HH:mm, add seconds so parse in CreateDialog.js works
      this.selectedTime = `${event.time}:00`
      this.$nextTick(() => {
        this.contextMenuShown = true
      })
    },
    prev: function () {
      this.cal.prev()
    },
    next: function () {
      this.cal.next()
    },
    close: function () {
      this.selectedOpen = false
      this.selectedEvent = null
    },
    generateDateTime: function (activity) {
      if (!activity) return ''
      const date = new Date(activity.start * 1000)
      if (this.displayTimeInUtc) {
        return date.toUTCString()
      } else {
        return date.toLocaleString() // TODO: support other locales besides en-US
      }
    },
    getEventColor: function (event) {
      return event.color
    },
    getCurrentTime: function () {
      return this.ready
        ? this.cal.times.now.hour * 60 + this.cal.times.now.minute
        : 0
    },
    scrollToTime: function () {
      const time = this.getCurrentTime()
      const first = Math.max(0, time - (time % 30) - 30)
      this.cal.scrollToTime(first)
    },
    updateTime: function () {
      setInterval(() => this.cal.updateTimes(), 60 * 1000)
    },
    showEvent: function ({ nativeEvent, event }) {
      const open = () => {
        this.selectedEvent = event
        this.selectedElement = nativeEvent.target
        requestAnimationFrame(() =>
          requestAnimationFrame(() => (this.selectedOpen = true)),
        )
      }
      if (this.selectedOpen) {
        this.selectedOpen = false
        requestAnimationFrame(() => requestAnimationFrame(() => open()))
      } else {
        open()
      }
      nativeEvent.stopPropagation()
    },
    eventDialog: function () {
      this.showEventDialog = !this.showEventDialog
    },
    updateDialog: function () {
      this.showUpdateDialog = !this.showUpdateDialog
    },
    viewDay: function ({ date }) {
      this.calendarConfiguration = {
        ...this.calendarConfiguration,
        type: 'day',
        focus: date,
      }
    },
    eventStatusColor: function (event) {
      return this.states[
        event.activity.events[event.activity.events.length - 1].event
      ].color
    },
    eventStatusIcon: function (event) {
      return this.states[
        event.activity.events[event.activity.events.length - 1].event
      ].icon
    },
  },
}
</script>

<style scoped>
.theme--dark .v-card__title,
.theme--dark .v-card__subtitle {
  background-color: var(--v-secondary-darken3);
}
.event-status {
  position: absolute;
  right: 1px;
  top: 1px;
  border-radius: 50%;
  font-size: 15px;
  background-color: white;
}
.v-current-time {
  height: 2px;
  background-color: #ea4335;
  position: absolute;
  left: -1px;
  right: 0;
  pointer-events: none;

  &.first::before {
    content: '';
    position: absolute;
    background-color: #ea4335;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    margin-top: -5px;
    margin-left: -6.5px;
  }
}
</style>
