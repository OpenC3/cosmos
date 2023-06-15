<!--
# Copyright 2023 OpenC3, Inc.
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
    <v-card-title>
      Events
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
        label="Filter by Type"
        hide-details
        :items="types"
        v-model="filterType"
        class="mr-2"
        data-test="filter-type"
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
          <div class="pt-5" v-on="on" v-bind="attrs">
            <v-btn icon data-test="events-download" @click="downloadEvents">
              <v-icon> mdi-download </v-icon>
            </v-btn>
          </div>
        </template>
        <span> Download Log </span>
      </v-tooltip>
      <v-tooltip top>
        <template v-slot:activator="{ on, attrs }">
          <div class="pt-5" v-on="on" v-bind="attrs">
            <v-btn icon data-test="events-clear" @click="clearEvents">
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
      sort-by="timestamp"
      sort-desc
      dense
      height="45vh"
      data-test="log-messages"
    >
      <template v-slot:item.timestamp="{ item }">
        <time :title="item.timestamp" :datetime="item.timestamp">
          {{ item.timestamp }}
        </time>
      </template>
      <template v-slot:item.log="{ item }">
        <div style="white-space: pre-wrap">{{ item.log }}</div>
      </template>
    </v-data-table>
  </v-card>
</template>

<script>
import { toDate, format } from 'date-fns'
import Cable from '@openc3/tool-common/src/services/cable.js'

export default {
  props: {
    historyCount: {
      type: Number,
      default: 200,
    },
  },
  data() {
    return {
      data: [],
      shownData: [],
      types: ['ALL', 'TRIGGER', 'REACTION', 'GROUP'],
      filterType: 'ALL',
      search: '',
      headers: [
        { text: 'Time', value: 'timestamp' },
        { text: 'Type', value: 'type' },
        { text: 'Source', value: 'source' },
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
    eventGroupHandlerFunctions: function () {
      return {
        created: this.createdGroupFromEvent,
        updated: this.updatedGroupFromEvent,
        deleted: this.deletedGroupFromEvent,
      }
    },
  },
  watch: {
    filterType: function (newVal, oldVal) {
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
      if (this.paused === false) {
        this.shownData = this.data
      }
    },
    createSubscription() {
      if (this.subscription) {
        this.subscription.unsubscribe()
        this.data = []
        this.shownData = this.data
      }
      this.cable
        .createSubscription(
          'AutonomicEventsChannel',
          window.openc3Scope,
          {
            received: (messages) => {
              this.cable.recordPing()
              if (messages.length > this.historyCount) {
                messages.splice(0, messages.length - this.historyCount)
              }
              // Filter messages before they're added to the table
              // This prevents a bunch of invisible 'TRIGGER' messages from pushing
              // off the 'REACTION' or 'GROUP' messages if we filter inside the data-table
              messages = messages.filter((message) => {
                switch (this.filterType) {
                  case 'ALL':
                    return true
                  case 'TRIGGER':
                    if (message.type === 'trigger') {
                      return true
                    }
                    break
                  case 'REACTION':
                    if (message.type === 'reaction') {
                      return true
                    }
                    break
                  case 'GROUP':
                    if (message.type === 'group') {
                      return true
                    }
                    break
                }
                return false
              })

              messages = messages.map((message) => {
                message.data = JSON.parse(message.data)
                return {
                  timestamp: this.formatDate(message.data.updated_at),
                  type: message.type.toUpperCase(),
                  source: message.data.name,
                  log: this.generateMessage(message),
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
            history_count: this.historyCount,
          }
        )
        .then((subscription) => {
          this.subscription = subscription
        })
    },
    generateMessage: function (message) {
      if (message.kind === 'error') {
        return `Error: ${message.data.message}`
      } else {
        switch (message.type) {
          case 'group':
            return `Trigger group ${message.data.name} was ${message.kind}`
          case 'trigger':
            return `Trigger ${message.data.name} in group ${message.data.group} was ${message.kind}`
          case 'reaction':
            if (message.kind === 'run') {
              // Run has extra info to determine what action type it is
              return `Reaction ${message.data.name} of type ${message.data.action} was ${message.kind}`
            } else {
              return `Reaction ${message.data.name} was ${message.kind}`
            }
        }
      }
    },
    formatDate(nanoSecs) {
      return format(
        toDate(parseInt(nanoSecs) / 1_000_000),
        'yyyy-MM-dd HH:mm:ss.SSS'
      )
    },
    downloadEvents: function () {
      const output = JSON.stringify(this.data, null, 2)
      const blob = new Blob([output], {
        type: 'application/json',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute(
        'download',
        format(Date.now(), 'yyyy_MM_dd_HH_mm_ss') + '_autonomic_events.json'
      )
      link.click()
    },
    clearEvents: function () {
      this.$dialog
        .confirm('Are you sure you want to clear the autonomic events logs?', {
          okText: 'Clear',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          this.shownData = []
          this.data = []
        })
    },
  },
}
</script>
