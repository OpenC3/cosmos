<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card class="card-height">
    <v-card-title class="d-flex align-center">
      Limits Events
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
    <!-- Virtual so a flood of limits events only renders the visible rows -->
    <v-data-table-virtual
      :headers="headers"
      :items="data"
      :search="search"
      multi-sort
      fixed-header
      density="compact"
      :height="calcTableHeight()"
      hover
      data-test="limits-events"
    >
      <template #item.time_nsec="{ item }">
        <span>{{ formatNanoseconds(item.time_nsec, timeZone) }}</span>
      </template>
      <template #item.level="{ item }">
        <rux-status :status="getStatus(item.message)"></rux-status>
      </template>
      <template #item.message="{ item }">
        <span :class="getColorClass(item.message)">{{ item.message }}</span>
      </template>
    </v-data-table-virtual>
  </v-card>
</template>

<script>
import { markRaw } from 'vue'
import { Cable } from '@openc3/js-common/services'
import { TimeFilters } from '@openc3/vue-common/util'

// Received events are added to the table at most this often (ms). A flood
// arrives as many small cable messages, and re-rendering for each one can't
// keep up.
const FLUSH_INTERVAL = 100

export default {
  mixins: [TimeFilters],
  props: {
    historyCount: {
      type: Number,
      default: 1000,
    },
    timeZone: {
      type: String,
      default: 'local',
    },
  },
  data() {
    return {
      data: [],
      cable: new Cable(),
      search: '',
      headers: [
        { title: 'Time', value: 'time_nsec', width: 250 },
        { title: 'Level', value: 'level', sortable: false },
        { title: 'Message', value: 'message' },
      ],
    }
  },
  created() {
    // Events received since the last flush, not reactive
    this.pending = []
    this.flushTimeout = null
    this.cable
      .createSubscription(
        'LimitsEventsChannel',
        window.openc3Scope,
        {
          received: (parsed) => {
            this.cable.recordPing()
            this.handleMessages(parsed)
          },
        },
        {
          // Channel parameter is history_count with underscore
          history_count: this.historyCount,
        },
      )
      .then((limitsSubscription) => {
        this.limitsSubscription = limitsSubscription
      })
  },
  unmounted() {
    clearTimeout(this.flushTimeout)
    if (this.limitsSubscription) {
      this.limitsSubscription.unsubscribe()
    }
    this.cable.disconnect()
  },
  methods: {
    handleMessages(messages) {
      for (let i = 0; i < messages.length; i++) {
        // Events are never modified so skip making each one deeply reactive
        this.pending.push(markRaw(JSON.parse(messages[i]['event'])))
      }
      if (this.pending.length > this.historyCount) {
        this.pending.splice(0, this.pending.length - this.historyCount)
      }
      this.flushTimeout ??= setTimeout(this.flush, FLUSH_INTERVAL)
    },
    flush() {
      this.flushTimeout = null
      // Newest first, and replace the array once so the table renders once
      const events = this.pending.reverse()
      this.pending = []
      this.data = events.concat(this.data).slice(0, this.historyCount)
    },
    getStatus(message) {
      if (message.includes('GREEN')) {
        return 'normal'
      } else if (message.includes('YELLOW')) {
        return 'caution'
      } else if (message.includes('RED')) {
        return 'critical'
      } else if (message.includes('BLUE')) {
        return 'standby'
      } else {
        return 'off'
      }
    },
    getColorClass(message) {
      if (message.includes('GREEN')) {
        return 'openc3-green'
      } else if (message.includes('YELLOW')) {
        return 'openc3-yellow'
      } else if (message.includes('RED')) {
        return 'openc3-red'
      } else if (message.includes('BLUE')) {
        return 'openc3-blue'
      }
      return 'openc3-white'
    },
    calcTableHeight() {
      // TODO: 250 is a magic number but seems to work well
      return window.innerHeight - 250
    },
  },
}
</script>

<style lang="scss" scoped>
.card-height {
  // TODO: 150 is a magic number but seems to work well
  // Can this be calculated by the size of the table search box?
  height: calc(100vh - 150px);
}
</style>
