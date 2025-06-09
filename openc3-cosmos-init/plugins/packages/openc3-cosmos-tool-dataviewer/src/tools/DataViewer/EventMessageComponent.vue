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
      return Object.keys(packet)
        .filter((item) => item.includes('DECOM__TLM'))
        .flatMap((item) => {
          const val = packet[item]
          if (Array.isArray(val)) {
            return val.join('\n')
          }
          return `${val}`
        })
        .join('\n')
    },
  },
}
</script>
