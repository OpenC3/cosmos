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
    <v-toolbar class="my-1">
      <v-menu bottom right>
        <template v-slot:activator="{ on, attrs }">
          <div v-bind="attrs" v-on="on">
            <v-btn data-test="create-event" outlined>
              <v-icon left>mdi-plus-box</v-icon>
              <span>Create</span>
              <v-icon right>mdi-menu-down</v-icon>
            </v-btn>
          </div>
        </template>
        <v-list>
          <v-list-item data-test="create-timeline" @click="createTimeline">
            <v-icon left>mdi-calendar-plus</v-icon>
            <v-list-item-title>Timeline</v-list-item-title>
          </v-list-item>
          <v-divider />
          <v-list-item data-test="note" @click="showNoteCreateDialog = true">
            <v-icon left>mdi-calendar-clock</v-icon>
            <v-list-item-title>Note</v-list-item-title>
          </v-list-item>
          <v-list-item
            data-test="metadata"
            @click="showMetadataCreateDialog = true"
          >
            <v-icon left>mdi-calendar-check</v-icon>
            <v-list-item-title>Metadata</v-list-item-title>
          </v-list-item>
          <v-list-item
            data-test="activity"
            @click="showActivityCreateDialog = true"
          >
            <v-icon left>mdi-calendar-question</v-icon>
            <v-list-item-title>Timeline Activity</v-list-item-title>
          </v-list-item>
        </v-list>
      </v-menu>
      <v-btn outlined class="mx-3" data-test="today" @click="setToday">
        Today
      </v-btn>
      <v-btn fab text small data-test="prev" @click="prev">
        <v-icon small> mdi-chevron-left </v-icon>
      </v-btn>
      <v-btn fab text small data-test="next" @click="next">
        <v-icon small> mdi-chevron-right </v-icon>
      </v-btn>
      <!--- SPACER --->
      <v-spacer />
      <v-toolbar-title>{{ title }}</v-toolbar-title>
      <v-spacer />
      <v-menu bottom right>
        <template v-slot:activator="{ on, attrs }">
          <div v-bind="attrs" v-on="on">
            <v-btn outlined data-test="change-type" width="125">
              <span>{{ typeToLabel[type] }}</span>
              <v-icon right> mdi-menu-down </v-icon>
            </v-btn>
          </div>
        </template>
        <v-list>
          <v-list-item data-test="type-day" @click="updateType('day')">
            <v-list-item-title> Day </v-list-item-title>
          </v-list-item>
          <v-list-item data-test="type-four-day" @click="updateType('4day')">
            <v-list-item-title>4 Days</v-list-item-title>
          </v-list-item>
          <v-list-item data-test="type-week" @click="updateType('week')">
            <v-list-item-title> Week </v-list-item-title>
          </v-list-item>
        </v-list>
      </v-menu>
    </v-toolbar>
    <!--- menus --->
    <timeline-create-dialog
      v-if="showTimelineCreateDialog"
      v-model="showTimelineCreateDialog"
      :timelines="timelines"
    />
    <metadata-create-dialog
      v-if="showMetadataCreateDialog"
      v-model="showMetadataCreateDialog"
    />
    <note-create-dialog
      v-if="showNoteCreateDialog"
      v-model="showNoteCreateDialog"
    />
    <activity-create-dialog
      v-if="showActivityCreateDialog"
      v-model="showActivityCreateDialog"
      :timelines="timelines"
    />
    <upgrade-to-enterprise-dialog
      v-model="showUpgradeToEnterpriseDialog"
      :reason="upgradeReason"
    ></upgrade-to-enterprise-dialog>
  </div>
</template>

<script>
import TimelineCreateDialog from '@/tools/Calendar/Dialogs/TimelineCreateDialog'
import ActivityCreateDialog from '@/tools/Calendar/Dialogs/ActivityCreateDialog'
import MetadataCreateDialog from '@openc3/tool-common/src/tools/calendar/Dialogs/MetadataCreateDialog'
import UpgradeToEnterpriseDialog from '@openc3/tool-common/src/components/UpgradeToEnterpriseDialog'
import NoteCreateDialog from '@/tools/Calendar/Dialogs/NoteCreateDialog'

export default {
  components: {
    TimelineCreateDialog,
    ActivityCreateDialog,
    MetadataCreateDialog,
    NoteCreateDialog,
    UpgradeToEnterpriseDialog,
  },
  props: {
    timelines: {
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
      typeToLabel: {
        week: 'Week',
        '4day': '4 Days',
        day: 'Day',
      },
      showTimelineCreateDialog: false,
      showActivityCreateDialog: false,
      showMetadataCreateDialog: false,
      showNoteCreateDialog: false,
      showUpgradeToEnterpriseDialog: false,
      upgradeReason: '',
    }
  },
  computed: {
    monthNames: function () {
      return [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ]
    },
    title: function () {
      const d = this.value.focus ? new Date(this.value.focus) : new Date()
      const month = this.monthNames[d.getUTCMonth()]
      const year = d.getUTCFullYear()
      return `${month} ${year}`
    },
    focus: function () {
      return this.value.focus
    },
    type: function () {
      return this.value.type
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
  methods: {
    createTimeline: function () {
      if (OpenC3Auth.user().name === 'Anonymous' && this.timelines.length > 0) {
        this.upgradeReason = 'Open Source is limited to 1 timeline.'
        this.showUpgradeToEnterpriseDialog = true
      } else {
        this.showTimelineCreateDialog = true
      }
    },
    updateType: function (type) {
      this.calendarConfiguration = {
        ...this.calendarConfiguration,
        type: type,
      }
      this.type = type
    },
    setToday: function () {
      this.calendarConfiguration = {
        ...this.calendarConfiguration,
        focus: '',
      }
    },
    prev() {
      this.$emit('action', { method: 'prev' })
    },
    next() {
      this.$emit('action', { method: 'next' })
    },
  },
}
</script>
