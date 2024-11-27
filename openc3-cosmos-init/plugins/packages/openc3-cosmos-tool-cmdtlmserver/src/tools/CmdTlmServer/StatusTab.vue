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
      <v-card-title class="d-flex align-center justify-content-space-between">
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
        :items-per-page-options="[10, 20, 50, 100, -1]"
        multi-sort
        data-test="metrics-table"
      >
      </v-data-table>
    </v-card>
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'
import Updater from './Updater'

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
        { title: 'Port', value: 'port' },
        { title: 'Clients', value: 'clients' },
        { title: 'Requests', value: 'requests' },
        { title: 'Avg Request Time', value: 'avgTime' },
        { title: 'Server Threads', value: 'threads' },
      ],
      backgroundTasks: [],
      backgroundHeaders: [
        { title: 'Name', value: 'name' },
        { title: 'State', value: 'state' },
        { title: 'Status', value: 'status' },
        { title: 'Control', value: 'control' },
      ],
      search: '',
      data: [],
      headers: [
        { title: 'Metric', key: 'metric_name' },
        { title: 'Value', key: 'value' },
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
