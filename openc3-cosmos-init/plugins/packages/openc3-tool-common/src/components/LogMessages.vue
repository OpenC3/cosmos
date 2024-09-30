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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card>
    <v-card-title>
      <v-tooltip top>
        <template v-slot:activator="{ on, attrs }">
          <div v-on="on" v-bind="attrs">
            <v-btn
              icon
              class="mx-2"
              data-test="download-log"
              @click="downloadLog"
            >
              <v-icon> mdi-download </v-icon>
            </v-btn>
          </div>
        </template>
        <span> Download Log </span>
      </v-tooltip>
      <span> Log Messages </span>
      <v-tooltip top>
        <template v-slot:activator="{ on, attrs }">
          <div v-on="on" v-bind="attrs">
            <v-btn icon data-test="pause" @click="pause">
              <v-icon> {{ buttonIcon }} </v-icon>
            </v-btn>
          </div>
        </template>
        <span> {{ buttonLabel }} </span>
      </v-tooltip>
      <v-spacer />
      <v-select
        label="Filter by log level"
        hide-details
        outlined
        dense
        :items="logLevels"
        v-model="logLevel"
        class="mr-2"
        style="max-width: 150px"
        data-test="log-messages-level"
      />
      <v-spacer />
      <v-text-field
        v-model="search"
        label="Search"
        prepend-inner-icon="mdi-magnify"
        clearable
        outlined
        dense
        single-line
        hide-details
        style="max-width: 300px"
        class="search"
        data-test="search-log-messages"
      />
      <v-tooltip top>
        <template v-slot:activator="{ on, attrs }">
          <div v-on="on" v-bind="attrs">
            <v-btn icon class="mx-2" data-test="clear-log" @click="clearLog">
              <v-icon> mdi-delete </v-icon>
            </v-btn>
          </div>
        </template>
        <span> Clear Log </span>
      </v-tooltip>
    </v-card-title>
    <v-data-table
      :headers="headers"
      :items="shownData"
      :search="search"
      calculate-widths
      disable-pagination
      hide-default-footer
      multi-sort
      dense
      height="70vh"
      data-test="log-messages"
    >
      <template v-slot:item.timestamp="{ item }">
        <time :title="item.timestamp" :datetime="item.timestamp">
          {{ item.timestamp }}
        </time>
      </template>
      <template v-slot:item.level="{ item }">
        <span :style="'display: inline-flex; color:' + getColor(item.level)">
          <rux-status class="mr-1" :status="getStatus(item.level)"></rux-status>
          {{ item.level }}</span
        >
      </template>
      <template v-slot:item.message="{ item }">
        <div style="white-space: pre-wrap">{{ item.message }}</div>
      </template>
    </v-data-table>
  </v-card>
</template>

<script>
import { format } from 'date-fns'
import Cable from '../services/cable.js'
import {
  AstroStatusColors,
  UnknownToAstroStatus,
} from '@openc3/tool-common/src/components/icons'
import TimeFilters from '@openc3/tool-common/src/tools/base/util/timeFilters.js'

export default {
  props: {
    historyCount: {
      type: Number,
      default: 200,
    },
    timeZone: {
      type: String,
      default: 'local',
    },
  },
  mixins: [TimeFilters],
  data() {
    return {
      AstroStatusColors,
      data: [],
      shownData: [],
      logLevels: ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'],
      logLevel: 'INFO',
      search: '',
      headers: [
        { text: 'Time', value: 'timestamp', width: 220 },
        { text: 'Level', value: 'level' },
        { text: 'Source', value: 'microservice_name' },
        { text: 'Message', value: 'message' },
      ],
      cable: new Cable(),
      subscription: null,
      paused: false,
    }
  },
  computed: {
    buttonLabel: function () {
      if (this.paused) {
        return 'Resume'
      } else {
        return 'Pause'
      }
    },
    buttonIcon: function () {
      if (this.paused) {
        return 'mdi-play'
      } else {
        return 'mdi-pause'
      }
    },
  },
  watch: {
    logLevel: function (newVal, oldVal) {
      this.createSubscription()
    },
  },
  created() {
    this.createSubscription()
  },
  destroyed() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    this.cable.disconnect()
  },
  methods: {
    pause: function () {
      this.paused = !this.paused
    },
    createSubscription() {
      if (this.subscription) {
        this.subscription.unsubscribe()
        this.data = []
        this.shownData = this.data
      }
      this.cable
        .createSubscription(
          'MessagesChannel',
          window.openc3Scope,
          {
            received: (messages) => {
              this.cable.recordPing()
              if (messages.length > this.historyCount) {
                messages.splice(0, messages.length - this.historyCount)
              }
              // Filter messages before they're added to the table
              // This prevents a bunch of invisible 'INFO' messages from pushing
              // off the 'WARN' or 'ERROR' messages if we filter inside the data-table
              messages = messages.filter((message) => {
                switch (this.logLevel) {
                  case 'DEBUG':
                    return true
                  case 'INFO':
                    if (message.level !== 'DEBUG') {
                      return true
                    }
                    break
                  case 'WARN':
                    if (message.level !== 'DEBUG' && message.level !== 'INFO') {
                      return true
                    }
                    break
                  case 'ERROR':
                    if (
                      message.level !== 'DEBUG' &&
                      message.level !== 'INFO' &&
                      message.level !== 'WARN'
                    ) {
                      return true
                    }
                    break
                  case 'FATAL':
                    if (
                      message.level !== 'DEBUG' &&
                      message.level !== 'INFO' &&
                      message.level !== 'WARN' &&
                      message.level !== 'ERROR'
                    ) {
                      return true
                    }
                    break
                }
                return false
              })
              messages.map((message) => {
                message.timestamp = this.formatTimestamp(
                  message['@timestamp'],
                  this.timeZone
                )
                if (
                  message.message.raw &&
                  message.message.json_class === 'String'
                ) {
                  // This is binary data, display in hex.
                  let result = '0x'
                  for (let i = 0; i < message.message.raw.length; i++) {
                    var nibble = message.message.raw[i]
                      .toString(16)
                      .toUpperCase()
                    if (nibble.length < 2) {
                      nibble = '0' + nibble
                    }
                    result += nibble
                  }
                  message.message = result
                } else {
                  message.message = message.message.replaceAll('\\n', '\n')
                }
              })
              this.data = messages.reverse().concat(this.data)
              if (this.data.length > this.historyCount) {
                this.data.length = this.historyCount
              }
              if (!this.paused) {
                this.shownData = this.data
              }
            },
          },
          {
            // Channel parameter is history_count with underscore
            history_count: this.historyCount,
          }
        )
        .then((subscription) => {
          this.subscription = subscription
        })
    },
    getColor(level) {
      return AstroStatusColors[UnknownToAstroStatus[level]]
    },
    getStatus(level) {
      return UnknownToAstroStatus[level]
    },
    downloadLog() {
      const output = this.shownData
        .map(
          (entry) =>
            // Other fields are available like container_name, msg_id ... probably not useful
            `${entry.timestamp} | ${entry.level} | ${entry.microservice_name} | ${entry.message}`
        )
        .join('\n')
      const blob = new Blob([output], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute(
        'download',
        format(Date.now(), 'yyyy_MM_dd_HH_mm_ss') + '_message_log.txt'
      )
      link.click()
    },
    clearLog: function () {
      this.$dialog
        .confirm('Are you sure you want to clear the log?', {
          okText: 'Clear',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          this.data = []
          this.shownData = []
        })
        .catch(function (err) {
          // Canceling the dialog forces catch and sets err to true
        })
    },
  },
}
</script>
