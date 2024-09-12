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
    <v-card>
      <v-card-title>
        {{ data.length }} Metrics
        <v-spacer />
        <v-text-field
          v-model="search"
          label="Search"
          prepend-inner-icon="mdi-magnify"
          clearable
          variant="outlined"
          density="compact"
          single-line
          hide-details
          class="search"
        />
      </v-card-title>
      <v-data-table
        :headers="headers"
        :items="data"
        :search="search"
        :items-per-page="10"
        :footer-props="{
          itemsPerPageOptions: [10, 20, 50, 100, 1000],
          showFirstLastPage: true,
        }"
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
      search: '',
      data: [],
      headers: [
        { text: 'Metric', value: 'metric_name' },
        { text: 'Value', value: 'value' },
      ],
    }
  },
  methods: {
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
