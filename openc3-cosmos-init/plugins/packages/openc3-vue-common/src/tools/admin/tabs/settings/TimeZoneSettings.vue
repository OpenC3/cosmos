<!--
# Copyright 2024 OpenC3, Inc.
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
    <v-card-title>Time Zone</v-card-title>
    <v-card-subtitle>
      The time zone to display for all COSMOS tools. (Note: All timestamps are
      UTC in the backend).
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
        v-model="timeZone"
        :items="timeZones"
        label="Select time display"
        hide-details
        prepend-icon="mdi-map-clock"
        single-line
        data-test="time-zone"
      />
    </v-card-text>
    <v-card-actions>
      <v-btn
        @click="save"
        color="success"
        variant="text"
        data-test="save-time-zone"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import Settings from './settings.js'

const settingName = 'time_zone'
export default {
  mixins: [Settings],
  data() {
    return {
      timeZones: ['local', 'UTC'],
      timeZone: 'local',
    }
  },
  created() {
    this.loadSetting(settingName)
  },
  methods: {
    save() {
      this.saveSetting(settingName, this.timeZone)
    },
    parseSetting: function (response) {
      if (response) {
        this.timeZone = response
      }
    },
  },
}
</script>
