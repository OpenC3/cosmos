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
  <data-viewer-history-component
    ref="history"
    :config="currentConfig"
    :packets="currentPackets"
    :calculatePacketText="calculatePacketText"
    @config="(config) => (currentConfig = config)"
  />
</template>

<script>
import {
  DataViewerComponent,
  DataViewerHistoryComponent,
} from '@openc3/vue-common/components'

export default {
  mixins: [DataViewerComponent],
  components: {
    DataViewerHistoryComponent,
  },
  watch: {
    // Hook the HistoryComponent's receive method to our latestData being updated
    latestData: function (data) {
      this.$refs['history'].receive(data)
    },
  },
  created: function () {
    const defaultConfig = {
      history: 300, // 5min at 1Hz
      showTimestamp: true,
      packetsToShow: 10, // override the default of 1
      newestAtTop: true,
    }
    this.currentConfig = {
      ...defaultConfig, // In case anything isn't defined in this.currentConfig
      ...this.currentConfig,
    }
  },
  methods: {
    calculatePacketText: function (packet) {
      let text = ''
      if (this.currentConfig.showTimestamp) {
        const milliseconds = packet.__time / 1000000
        const receivedDate = new Date(milliseconds).toISOString()
        text = `Time: ${receivedDate}  `
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
