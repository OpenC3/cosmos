<!--
# Copyright 2025 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card max-height="80vh" class="d-flex flex-column">
    <v-card-title class="d-flex align-center flex-shrink-0">
      {{ mode }} Properties: {{ shownDetails.name }}
      <v-btn
        :icon="buttonIcon"
        variant="text"
        data-test="pause"
        @click="pause"
      />
      <v-spacer />
      <v-btn icon @click="closeClick">
        <v-icon>mdi-close</v-icon>
      </v-btn>
    </v-card-title>
    <v-card-text class="overflow-y-auto flex-grow-1 pa-0">
      <div class="details-table">
        <v-row>
          <v-col cols="4">
            <v-data-table
              v-if="shownDetails"
              :headers="headers"
              :items="detailsItems"
              :items-per-page="-1"
              hide-default-footer
              density="compact"
              class="details-table"
            >
              <template #item.value="{ item }">
                <span class="text-wrap">{{ item.value }}</span>
              </template>
            </v-data-table>
            <div v-else class="d-flex justify-center align-center pa-4">
              <v-progress-circular indeterminate color="primary" />
            </div>
          </v-col>
          <v-col cols="8">
            <div>{{ upperData.label }}: {{ upperData.time }}</div>
            <raw-buffer v-model="upperData.data" />
            <div>{{ lowerData.label }}: {{ lowerData.time }}</div>
            <raw-buffer v-model="lowerData.data" />
          </v-col>
        </v-row>
      </div>
    </v-card-text>
  </v-card>
</template>

<script>
import Updater from '../Updater'
import RawBuffer from '../RawBuffer.vue'

export default {
  name: 'DetailsTable',
  components: {
    RawBuffer,
  },
  mixins: [Updater],
  props: {
    mode: {
      type: String,
      default: 'Interface',
    },
    details: {
      type: Object,
      default: null,
    },
    readProtocolIndex: {
      type: Number,
      default: null,
    },
    writeProtocolIndex: {
      type: Number,
      default: null,
    },
  },
  emits: ['close'],
  data() {
    return {
      api: null,
      headers: [
        { title: 'Property', key: 'key', width: '30%' },
        { title: 'Value', key: 'value', width: '70%' },
      ],
      paused: false,
      updatedDetails: null,
    }
  },
  computed: {
    shownDetails() {
      if (this.updatedDetails) {
        return this.updatedDetails
      } else {
        return this.details
      }
    },
    upperData() {
      let result = {}
      if (!this.shownDetails) return result
      if (this.readProtocolIndex !== null) {
        let data = this.shownDetails.read_protocols[this.readProtocolIndex]
        result['data'] = data.read_data_input
        result['label'] = 'Read Data Input'
        result['time'] = data.read_data_input_time
      } else if (this.writeProtocolIndex !== null) {
        let data = this.shownDetails.write_protocols[this.writeProtocolIndex]
        result['data'] = data.write_data_input
        result['label'] = 'Write Data Input'
        result['time'] = data.write_data_input_time
      } else {
        let data = this.shownDetails
        result['data'] = data.written_raw_data
        result['label'] = 'Written Raw Data'
        result['time'] = data.written_raw_data_time
      }
      return result
    },
    lowerData() {
      let result = {}
      if (!this.shownDetails) return result

      if (this.readProtocolIndex !== null) {
        let data = this.shownDetails.read_protocols[this.readProtocolIndex]
        result['data'] = data.read_data_output
        result['label'] = 'Read Data Output'
        result['time'] = data.read_data_output_time
      } else if (this.writeProtocolIndex !== null) {
        let data = this.shownDetails.write_protocols[this.writeProtocolIndex]
        result['data'] = data.write_data_output
        result['label'] = 'Write Data Output'
        result['time'] = data.write_data_output_time
      } else {
        let data = this.shownDetails
        result['data'] = data.read_raw_data
        result['label'] = 'Read Raw Data'
        result['time'] = data.read_raw_data_time
      }
      return result
    },
    detailsItems() {
      if (!this.shownDetails) return []
      const excluded = [
        'written_raw_data',
        'read_raw_data',
        'written_raw_data_time',
        'read_raw_data_time',
        'read_protocols',
        'write_protocols',
        'read_data_input',
        'read_data_output',
        'write_data_input',
        'write_data_output',
        'read_data_input_time',
        'read_data_output_time',
        'write_data_input_time',
        'write_data_output_time',
      ]
      let data = null
      if (this.readProtocolIndex !== null) {
        data = this.shownDetails.read_protocols[this.readProtocolIndex]
      } else if (this.writeProtocolIndex !== null) {
        data = this.shownDetails.write_protocols[this.writeProtocolIndex]
      } else {
        data = this.shownDetails
      }
      return Object.entries(data)
        .filter(([key, _]) => {
          return !excluded.includes(key)
        })
        .map(([key, value]) => ({
          key: this.formatKey(key),
          value: this.formatValue(value),
        }))
    },
    buttonIcon: function () {
      if (this.paused) {
        return 'mdi-play'
      } else {
        return 'mdi-pause'
      }
    },
  },
  methods: {
    pause: function () {
      this.paused = !this.paused
    },
    closeClick: function () {
      this.$emit('close')
    },
    update: function () {
      if (this.paused) return
      if (!this.details) return
      this.updateDetails(this.details.name)
    },
    updateDetails(name) {
      if (this.mode == 'Interface') {
        this.api.interface_details(name).then((result) => {
          this.updatedDetails = result
        })
      } else {
        this.api.router_details(name).then((result) => {
          this.updatedDetails = result
        })
      }
    },
    formatKey(key) {
      return key.replace(/_/g, ' ').replace(/\b\w/g, (l) => l.toUpperCase())
    },
    formatValue(value) {
      if (value === null || value === undefined) {
        return ''
      }
      if (typeof value === 'object') {
        return JSON.stringify(value, null, 2)
      }
      return String(value)
    },
  },
}
</script>
