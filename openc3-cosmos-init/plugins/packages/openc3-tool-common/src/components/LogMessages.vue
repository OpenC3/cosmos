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
  <v-card>
    <v-card-title>
      <v-tooltip top>
        <template v-slot:activator="{ on, attrs }">
          <div class="pt-4" v-on="on" v-bind="attrs">
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
      <span class="pt-4"> Log Messages </span>
      <v-tooltip top>
        <template v-slot:activator="{ on, attrs }">
          <div class="pt-4" v-on="on" v-bind="attrs">
            <v-btn icon data-test="pause" @click="pause">
              <v-icon> {{ buttonIcon }} </v-icon>
            </v-btn>
          </div>
        </template>
        <span> {{ buttonLabel }} </span>
      </v-tooltip>
      <v-spacer />
      <v-select
        label="Filter by Log Level"
        hide-details
        :items="logLevels"
        v-model="logLevel"
        class="mr-2"
        data-test="log-messages-level"
      />
      <v-spacer />
      <v-text-field
        v-model="search"
        append-icon="mdi-magnify"
        label="Search"
        single-line
        hide-details
        data-test="search-log-messages"
      />
      <v-tooltip top>
        <template v-slot:activator="{ on, attrs }">
          <div v-on="on" v-bind="attrs">
            <v-btn
              icon
              class="pt-4 mx-2"
              data-test="clear-log"
              @click="clearLog"
            >
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
        <span :style="'display: inline-flex; color:' + getColor(item.severity)"
          ><astro-status-indicator
            :status="getStatus(item.severity)"
            class="mr-1"
            style="margin-top: 3px"
          />{{ item.severity }}</span
        >
      </template>
      <template v-slot:item.log="{ item }">
        <div style="white-space: pre-wrap">{{ item.log }}</div>
      </template>
    </v-data-table>
  </v-card>
</template>

<script>
import { parseISO, format } from 'date-fns'
import Cable from '../services/cable.js'
import {
  AstroStatusColors,
  UnknownToAstroStatus,
} from '@openc3/tool-common/src/components/icons'

export default {
  props: {
    history_count: {
      type: Number,
      default: 200,
    },
  },
  data() {
    return {
      AstroStatusColors,
      data: [],
      shownData: [],
      logLevels: ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'],
      logLevel: 'INFO',
      search: '',
      headers: [
        { text: 'Time', value: 'timestamp', width: 200 },
        { text: 'Log Level', value: 'level' },
        { text: 'Source', value: 'microservice_name' },
        { text: 'Message', value: 'log' },
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
              if (messages.length > this.history_count) {
                messages.splice(0, messages.length - this.history_count)
              }
              // Filter messages before they're added to the table
              // This prevents a bunch of invisible 'INFO' messages from pushing
              // off the 'WARN' or 'ERROR' messages if we filter inside the data-table
              messages = messages.filter((message) => {
                switch (this.logLevel) {
                  case 'DEBUG':
                    return true
                  case 'INFO':
                    if (message.severity !== 'DEBUG') {
                      return true
                    }
                    break
                  case 'WARN':
                    if (
                      message.severity !== 'DEBUG' &&
                      message.severity !== 'INFO'
                    ) {
                      return true
                    }
                    break
                  case 'ERROR':
                    if (
                      message.severity !== 'DEBUG' &&
                      message.severity !== 'INFO' &&
                      message.severity !== 'WARN'
                    ) {
                      return true
                    }
                    break
                  case 'FATAL':
                    if (
                      message.severity !== 'DEBUG' &&
                      message.severity !== 'INFO' &&
                      message.severity !== 'WARN' &&
                      message.severity !== 'ERROR'
                    ) {
                      return true
                    }
                    break
                }
                return false
              })
              messages.map((message) => {
                message.timestamp = this.formatDate(message['@timestamp'])
                if (message.log.raw && message.log.json_class === 'String') {
                  // This is binary data, display in hex.
                  let result = '0x'
                  for (let i = 0; i < message.log.raw.length; i++) {
                    var nibble = message.log.raw[i].toString(16).toUpperCase()
                    if (nibble.length < 2) {
                      nibble = '0' + nibble
                    }
                    result += nibble
                  }
                  message.log = result
                } else {
                  message.log = message.log.replaceAll('\\n', '\n')
                }
              })
              this.data = messages.reverse().concat(this.data)
              if (this.data.length > this.history_count) {
                this.data.length = this.history_count
              }
              if (!this.paused) {
                this.shownData = this.data
              }
            },
          },
          {
            history_count: this.history_count,
          },
        )
        .then((subscription) => {
          this.subscription = subscription
        })
    },
    formatDate(timestamp) {
      // timestamp: 2021-01-20T21:08:49.784Z
      return format(parseISO(timestamp), 'yyyy-MM-dd HH:mm:ss.SSS')
    },
    getColor(severity) {
      return AstroStatusColors[UnknownToAstroStatus[severity]]
    },
    getStatus(severity) {
      return UnknownToAstroStatus[severity]
    },
    downloadLog() {
      const output = this.shownData
        .map(
          (entry) =>
            // Other fields are available like container_name, msg_id ... probably not useful
            `${entry.timestamp} | ${entry.severity} | ${entry.microservice_name} | ${entry.log}`,
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
        format(Date.now(), 'yyyy_MM_dd_HH_mm_ss') + '_message_log.txt',
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
          // Cancelling the dialog forces catch and sets err to true
        })
    },
  },
}
</script>
