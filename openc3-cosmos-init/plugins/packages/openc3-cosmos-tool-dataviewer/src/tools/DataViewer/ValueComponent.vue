<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <data-viewer-history-component
    ref="history"
    :config="currentConfig"
    :packets="currentPackets"
    :calculate-packet-text="calculatePacketText"
    @config="(config) => (currentConfig = config)"
  />
</template>

<script>
import {
  DataViewerComponent,
  DataViewerHistoryComponent,
} from '@openc3/vue-common/components'

export default {
  components: {
    DataViewerHistoryComponent,
  },
  mixins: [DataViewerComponent],
  watch: {
    // Hook the HistoryComponent's receive method to our latestData being updated
    latestData: function (data) {
      this.$refs['history'].receive(data)
    },
  },
  created: function () {
    const defaultConfig = {
      history: 300, // 5min at 1Hz
      showTimestamp: true, // Packet time
      showReceivedTime: true,
      packetsToShow: 10, // override the default of 1
      newestAtTop: true,
    }
    this.currentConfig = {
      ...defaultConfig, // In case anything isn't defined in this.currentConfig
      ...this.currentConfig,
    }
  },
  methods: {
    timeText: function (name, nanoseconds) {
      if (nanoseconds === undefined || nanoseconds === null) return ''
      const date = new Date(nanoseconds / 1000000).toISOString()
      return `${name}: ${date}  `
    },
    calculatePacketText: function (packet) {
      let text = ''
      // showTimestamp is the packet time. Data Viewer asks the stream for both
      // __packet_time and __received_time (nanoseconds) in every entry.
      if (this.currentConfig.showTimestamp) {
        text += this.timeText('Packet Time', packet.__packet_time)
      }
      if (this.currentConfig.showReceivedTime) {
        text += this.timeText('Received Time', packet.__received_time)
      }
      text += Object.keys(packet)
        .map((item) => {
          if (item.includes('DECOM__TLM')) {
            let name = item.split('__')[4]
            return `${name}: ${packet[item]}`
          } else {
            return undefined
          }
        })
        .filter((item) => item !== undefined)
        .join('  ')
      return text
    },
  },
}
</script>
