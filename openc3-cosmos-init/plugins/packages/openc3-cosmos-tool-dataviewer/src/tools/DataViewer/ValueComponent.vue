<!--
# Copyright 2024 OpenC3, Inc.
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
        // const receivedSeconds = (milliseconds / 1000).toFixed(7)
        const receivedDate = new Date(milliseconds).toISOString()
        text = `RxTime: ${receivedDate}  `
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
