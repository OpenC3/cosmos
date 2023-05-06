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
  <history-component
    ref="history"
    :config="currentConfig"
    :packets="currentPackets"
    :calculatePacketText="calculatePacketText"
    @config="(config) => (currentConfig = config)"
  ></history-component>
</template>

<script>
import HistoryComponent from '@openc3/tool-common/src/components/dataviewer/HistoryComponent'
import Component from '@openc3/tool-common/src/components/dataviewer/Component'

export default {
  mixins: [Component],
  components: {
    HistoryComponent,
  },
  watch: {
    // Hook the HistoryComponent's receive method to our latestData being updated
    latestData: function (data) {
      this.$refs['history'].receive(data)
    },
  },
  methods: {
    calculatePacketText: function (packet) {
      let text = ''
      if (this.currentConfig.showTimestamp) {
        const milliseconds = packet.__time / 1000000
        const receivedSeconds = (milliseconds / 1000).toFixed(7)
        const receivedDate = new Date(milliseconds).toISOString()
        let timestamp = '********************************************\n'
        timestamp += `* Received seconds: ${receivedSeconds}\n`
        timestamp += `* Received time: ${receivedDate}\n`
        timestamp += '********************************************\n'
        text = `${timestamp}${text}`
      }
      if ('buffer' in packet) {
        // Split its buffer into lines of the selected length
        text += _.chunk([...packet.buffer], this.currentConfig.bytesPerLine)
          .map((lineBytes, index) => {
            // Map each line into ASCII or hex values
            let mappedBytes = lineBytes.map((byte) =>
              byte.charCodeAt(0).toString(16).padStart(2, '0')
            )
            let lineLength = this.currentConfig.bytesPerLine * 3 - 1
            let line = mappedBytes.join(' ').padEnd(lineLength, ' ')
            if (this.currentConfig.showAscii) {
              line += '    '
              mappedBytes = lineBytes.map((byte) =>
                byte.replaceAll(/\n/g, '\\n').replaceAll(/\r/g, '\\r')
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
