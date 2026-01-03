<!--
# Copyright 2026 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card>
    <v-card-title>Time Format</v-card-title>
    <v-card-subtitle>
      The time format to use in all COSMOS tools (time pickers, etc). This
      setting controls whether time is displayed in 12-hour (AM/PM) or 24-hour
      format.
    </v-card-subtitle>
    <v-alert v-model="errorLoading" type="error" closable density="compact">
      Error loading previous configuration due to {{ errorText }}
    </v-alert>
    <v-alert v-model="errorSaving" type="error" closable density="compact">
      Error saving due to {{ errorText }}
    </v-alert>
    <v-alert v-model="successSaving" type="success" closable density="compact">
      Saved! (Refresh the page to see changes)
    </v-alert>
    <v-card-text>
      <v-select
        v-model="timeFormat"
        :items="timeFormats"
        label="Select time format"
        hide-details
        prepend-icon="mdi-clock-outline"
        single-line
        data-test="time-format"
      />
    </v-card-text>
    <v-card-actions>
      <v-btn
        color="success"
        variant="text"
        data-test="save-time-format"
        @click="save"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import Settings from './settings.js'

const settingName = 'time_format'
export default {
  mixins: [Settings],
  data() {
    return {
      timeFormats: [
        { title: '12-hour (AM/PM)', value: 'ampm' },
        { title: '24-hour', value: '24hr' },
      ],
      timeFormat: 'ampm',
    }
  },
  created() {
    this.loadSetting(settingName)
  },
  methods: {
    save() {
      this.saveSetting(settingName, this.timeFormat)
    },
    parseSetting: function (response) {
      if (response) {
        this.timeFormat = response
      }
    },
  },
}
</script>
