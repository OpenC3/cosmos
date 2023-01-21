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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <!-- Use a container here so we can do cols="auto" to resize v-select -->
    <v-card flat>
      <v-container class="ma-0 pa-4">
        <v-row no-gutters>
          <v-col cols="auto">
            <v-select
              label="Limits Set"
              :items="limitsSets"
              v-model="currentLimitsSet"
              data-test="limits-set"
            />
          </v-col>
        </v-row>
      </v-container>
    </v-card>
    <v-card>
      <v-card-title>
        {{ data.length }} Metrics
        <v-spacer />
        <v-text-field
          v-model="search"
          append-icon="mdi-magnify"
          label="Search"
          single-line
          hide-details
        />
      </v-card-title>
      <v-data-table
        :headers="headers"
        :items="data"
        :search="search"
        :items-per-page="10"
        :footer-props="{ itemsPerPageOptions: [10, 20, 50, 100, 1000] }"
        calculate-widths
        multi-sort
        data-test="metrics-table"
      >
      </v-data-table>
    </v-card>
  </div>
</template>

<script>
import Updater from './Updater'
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'

export default {
  mixins: [Updater],
  props: {
    tabId: Number,
    curTab: Number,
  },
  data() {
    return {
      api: new OpenC3Api(),
      apiStatus: [],
      apiHeaders: [
        { text: 'Port', value: 'port' },
        { text: 'Clients', value: 'clients' },
        { text: 'Requests', value: 'requests' },
        { text: 'Avg Request Time', value: 'avgTime' },
        { text: 'Server Threads', value: 'threads' },
      ],
      backgroundTasks: [],
      backgroundHeaders: [
        { text: 'Name', value: 'name' },
        { text: 'State', value: 'state' },
        { text: 'Status', value: 'status' },
        { text: 'Control', value: 'control' },
      ],
      limitsSets: [],
      currentLimitsSet: '',
      currentSetRefreshInterval: null,
      search: '',
      data: [],
      headers: [
        { text: 'Metric', value: 'metric_name' },
        { text: 'Value', value: 'value' },
      ],
    }
  },
  watch: {
    currentLimitsSet: function (newVal, oldVal) {
      !!oldVal && this.limitsChange(newVal)
    },
  },
  created() {
    this.api.get_limits_sets().then((sets) => {
      this.limitsSets = sets
    })
    this.getCurrentLimitsSet()
    this.currentSetRefreshInterval = setInterval(
      this.getCurrentLimitsSet,
      60 * 1000
    )
    this.update()
  },
  destroyed: function () {
    clearInterval(this.currentSetRefreshInterval)
  },
  methods: {
    getCurrentLimitsSet: function () {
      this.api.get_limits_set().then((result) => {
        this.currentLimitsSet = result
      })
    },
    limitsChange(value) {
      this.api.set_limits_set(value)
    },
    taskControl(name, state) {
      if (state == 'Start') {
        this.api.start_background_task(name)
      } else if (state == 'Stop') {
        this.api.stop_background_task(name)
      }
    },
    update() {
      if (this.tabId != this.curTab) return
      this.api.get_metrics().then((metrics) => {
        this.data = []
        for (const [key, value] of Object.entries(metrics)) {
          this.data.push({ metric_name: key, value: value })
        }
      })
    },
  },
}
</script>

<style scoped>
.container,
.theme--dark.v-card,
.theme--dark.v-sheet {
  background-color: var(--v-tertiary-darken2);
}
</style>
