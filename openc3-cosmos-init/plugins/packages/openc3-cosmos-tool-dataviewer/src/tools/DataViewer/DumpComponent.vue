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
  <data-viewer-history-component
    ref="history"
    :config="currentConfig"
    :packets="currentPackets"
    :calculate-packet-text="calculatePacketText"
    @config="(config) => (currentConfig = config)"
  />
</template>

<script>
import _ from 'lodash'
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
  methods: {
    timeLines: function (name, nanoseconds) {
      if (nanoseconds === undefined || nanoseconds === null) return []
      const milliseconds = nanoseconds / 1000000
      const seconds = (milliseconds / 1000).toFixed(7)
      const date = new Date(milliseconds).toISOString()
      return [`* ${name} seconds: ${seconds}\n`, `* ${name} time: ${date}\n`]
    },
    calculatePacketText: function (packet) {
      let text = ''
      // showTimestamp is the packet time. Data Viewer asks the stream for both
      // __packet_time and __received_time (nanoseconds) in every entry.
      let timeLines = []
      if (this.currentConfig.showTimestamp) {
        timeLines.push(...this.timeLines('Packet', packet.__packet_time))
      }
      if (this.currentConfig.showReceivedTime) {
        timeLines.push(...this.timeLines('Received', packet.__received_time))
      }
      if (timeLines.length > 0) {
        const border = '********************************************\n'
        text = `${border}${timeLines.join('')}${border}`
      }
      if ('buffer' in packet) {
        // Split its buffer into lines of the selected length
        text += _.chunk([...packet.buffer], this.currentConfig.bytesPerLine)
          .map((lineBytes, index) => {
            // Map each line into ASCII or hex values
            let mappedBytes = lineBytes.map((byte) =>
              byte.charCodeAt(0).toString(16).padStart(2, '0'),
            )
            let lineLength = this.currentConfig.bytesPerLine * 3 - 1
            let line = mappedBytes.join(' ').padEnd(lineLength, ' ')
            if (this.currentConfig.showAscii) {
              line += '    '
              mappedBytes = lineBytes.map((byte) =>
                byte.replaceAll(/\n/g, '\\n').replaceAll(/\r/g, '\\r'),
              )
              line += mappedBytes.join('')
            }
            // Prepend the line address if needed
            if (this.currentConfig.showLineAddress) {
              const address = (index * this.currentConfig.bytesPerLine)
                .toString(16)
                .padStart(8, '0')
              line = `${address}: ${line}`
            }
            return line
          })
          .join('\n') // end of one line
      } else {
        text += Object.keys(packet)
          .filter((item) => item.slice(0, 2) != '__')
          .map((item) => `${item}: ${packet[item]}`)
          .join('\n')
      }
      return text
    },
  },
}
</script>
