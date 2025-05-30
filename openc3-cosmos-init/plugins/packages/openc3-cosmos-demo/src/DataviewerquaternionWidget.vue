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
        text += 'This only works on DECOM packets with Q1, Q2, Q3, Q4 fields.'
      } else {
        let a = packet['Q1']
        let b = packet['Q2']
        let c = packet['Q3']
        let d = packet['Q4']
        if (
          a === undefined ||
          b === undefined ||
          c === undefined ||
          d === undefined
        ) {
          text += "Couldn't find Q1, Q1, Q3, Q4 in the packet fields."
        } else {
          text += `Q1: ${a}\n`
          text += `Q2: ${b}\n`
          text += `Q3: ${c}\n`
          text += `Q4: ${d}\n`
          // You'd probably want to do the magnitude as a TLM item conversion
          let magnitude = Math.sqrt(
            Math.pow(a, 2) + Math.pow(b, 2) + Math.pow(c, 2) + Math.pow(d, 2),
          )
          a = a.toString().padStart(9)
          b = b.toString().padStart(9)
          let negB = (-b).toString().padStart(9)
          c = c.toString().padStart(9)
          let negC = (-c).toString().padStart(9)
          d = d.toString().padStart(9)
          let negD = (-d).toString().padStart(9)
          text += `Matrix:\n`
          text += `[${a} ${negB} ${negC} ${negD}]\n`
          text += `[${b} ${a} ${negD} ${c}]\n`
          text += `[${c} ${d} ${a} ${negB}]\n`
          text += `[${d} ${negC} ${b} ${a}]\n`
          text += `Magnitude: ${magnitude}`
        }
      }
      return text
    },
  },
}
</script>
