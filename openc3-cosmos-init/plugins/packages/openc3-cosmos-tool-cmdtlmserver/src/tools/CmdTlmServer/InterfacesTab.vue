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
    <v-card-title class="d-flex align-center justify-content-space-between">
      {{ data.length }} Interfaces
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
      :custom-sort="sortTable"
      :items-per-page="10"
      :items-per-page-options="[10, 20, -1]"
      multi-sort
      data-test="interfaces-table"
    >
      <template #item.connect="{ item }">
        <v-tooltip
          :open-delay="600"
          location="top"
          :disabled="
            !item.disable_disconnect || item.connected === 'DISCONNECTED'
          "
          text="This interface set DISABLE_DISCONNECT in plugin.txt"
        >
          <template #activator="{ props }">
            <div v-bind="props">
              <v-btn
                block
                color="primary"
                :disabled="
                  buttonsDisabled ||
                  (item.disable_disconnect && item.connected === 'CONNECTED')
                "
                @click="connectDisconnect(item)"
              >
                {{ item.connect }}
              </v-btn>
            </div>
          </template>
        </v-tooltip>
      </template>
      <template #item.connected="{ item }">
        <span :class="item.connectedClass">
          {{ item.connected }}
        </span>
      </template>
    </v-data-table>
  </v-card>
</template>

<script>
import Updater from './Updater'

export default {
  mixins: [Updater],
  props: {
    tabId: Number,
    curTab: Number,
  },
  data() {
    return {
      search: '',
      data: [],
      buttonsDisabled: false,
      headers: [
        { title: 'Name', key: 'name' },
        {
          title: 'Action',
          key: 'connect',
          sortable: false,
          filterable: false,
        },
        { title: 'Connected', key: 'connected' },
        { title: 'Tx bytes', key: 'tx_bytes' },
        { title: 'Rx bytes', key: 'rx_bytes' },
        { title: 'Cmd pkts', key: 'cmd_pkts' },
        { title: 'Tlm pkts', key: 'tlm_pkts' },
      ],
    }
  },
  methods: {
    // Custom sort algorithm to allow the connected column to be sorted by CONNECTED first
    sortTable(items, index, isDesc) {
      items.sort((a, b) => {
        for (let i = 0; i < index.length; i++) {
          let column = index[i]
          let desc = isDesc[i]

          if (column === 'connected') {
            // Items are the same so continue to let subsequent column sorts apply
            if (a[column] === b[column]) {
              continue
            }
            if (!desc) {
              if (a[column] === 'CONNECTED') {
                return -1
              } else {
                return 1
              }
            } else {
              if (a[column] === 'CONNECTED') {
                return 1
              } else {
                return -1
              }
            }
          } else if (column === 'name') {
            // Items are the same so continue to let subsequent column sorts apply
            if (a[column] === b[column]) {
              continue
            }
            if (!desc) {
              // Strings so use localeCompare to sort
              return a[column].localeCompare(b[column])
            } else {
              return b[column].localeCompare(a[column])
            }
          } else {
            // Items are the same so continue to let subsequent column sorts apply
            if (a[column] === b[column]) {
              continue
            }
            if (!desc) {
              // The rest of the columns are numbers so just subtract to sort
              return a[column] - b[column]
            } else {
              return b[column] - a[column]
            }
          }
        }
      })
      return items
    },
    connectDisconnect(item) {
      this.buttonsDisabled = true
      if (item.connected === 'DISCONNECTED') {
        this.api.connect_interface(item.name)
      } else {
        this.api.disconnect_interface(item.name)
      }
    },
    update() {
      if (this.tabId != this.curTab) return
      this.api.get_all_interface_info().then((info) => {
        this.data = [] // Clear the old data
        for (let int of info) {
          let connect = null
          let connectedClass = null
          if (int[1] == 'DISCONNECTED') {
            connect = 'Connect'
            connectedClass = 'openc3-white'
          } else if (int[1] == 'CONNECTED') {
            connect = 'Disconnect'
            connectedClass = 'openc3-green'
          } else {
            connect = 'Cancel'
            connectedClass = 'openc3-red'
          }
          this.data.push({
            name: int[0],
            connect: connect,
            connectedClass: connectedClass,
            connected: int[1],
            clients: int[2],
            tx_q_size: int[3],
            rx_q_size: int[4],
            tx_bytes: int[5],
            rx_bytes: int[6],
            cmd_pkts: int[7],
            tlm_pkts: int[8],
            disable_disconnect: int[9], // Add the disable_disconnect property from the backend
          })
        }
        this.buttonsDisabled = false
      })
    },
  },
}
</script>
