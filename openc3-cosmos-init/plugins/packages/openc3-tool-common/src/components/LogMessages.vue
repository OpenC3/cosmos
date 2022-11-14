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
  <v-card>
    <v-card-title>
      Log Messages
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
        label="Filter by Severity"
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
      height="45vh"
      data-test="log-messages"
    >
      <template v-slot:item.timestamp="{ item }">
        <time :title="item.timestamp" :datetime="item.timestamp">
          {{ item.timestamp }}
        </time>
      </template>
      <template v-slot:item.severity="{ item }">
        <span :class="getColorClass(item.severity)">{{ item.severity }}</span>
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

export default {
  props: {
    history_count: {
      type: Number,
      default: 200,
    },
  },
  data() {
    return {
      data: [],
      shownData: [],
      logLevels: ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'],
      logLevel: 'INFO',
      search: '',
      headers: [
        { text: 'Time', value: 'timestamp', width: 200 },
        { text: 'Severity', value: 'severity' },
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
            received: (data) => {
              let messages = JSON.parse(data)
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
                message.log = message.log.replaceAll('\\n', '\n')
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
          }
        )
        .then((subscription) => {
          this.subscription = subscription
        })
    },
    formatDate(timestamp) {
      // timestamp: 2021-01-20T21:08:49.784+00:00
      return format(parseISO(timestamp), 'yyyy-MM-dd HH:mm:ss.SSS')
    },
    getColorClass(severity) {
      if (severity === 'INFO') {
        return 'openc3-green'
      } else if (severity === 'WARN') {
        return 'openc3-yellow'
      } else if (severity === 'ERROR' || severity === 'FATAL') {
        return 'openc3-red'
      }
      if (this.$vuetify.theme.dark) {
        return 'openc3-white'
      } else {
        return 'openc3-black'
      }
    },
  },
}
</script>
