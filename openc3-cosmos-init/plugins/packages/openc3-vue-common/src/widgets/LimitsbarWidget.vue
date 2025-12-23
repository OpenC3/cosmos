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
  <LimitsBar
    v-if="limits"
    :red-low="limits[0]"
    :yellow-low="limits[1]"
    :yellow-high="limits[2]"
    :red-high="limits[3]"
    :green-low="limits[4]"
    :green-high="limits[5]"
    :width="width"
    :height="height"
    :computed-style="mergedStyle"
  />
</template>

<script>
import BarColumn from './BarColumn'
import LimitsBar from '../components/LimitsBar.vue'

export default {
  components: {
    LimitsBar,
  },
  mixins: [BarColumn],
  data() {
    return {
      width: 160, // px
      height: 22, // px
    }
  },
  computed: {
    limits() {
      let values = this.limitsSettings[this.selectedLimitsSet]
      if (values) {
        return values
      } else {
        // See errorCaptured in Openc3Screen.vue for how this is parsed
        throw {
          line: this.line,
          lineNumber: this.lineNumber,
          keyword: 'LIMITSBAR',
          parameters: this.parameters,
          message: 'Item has no limits settings',
          usage: 'Only items with limits',
        }
      }
    },
    mergedStyle() {
      // Merge cssProps from BarColumn with computedStyle from Widget
      return { ...this.cssProps, ...this.computedStyle }
    },
  },
  created() {
    this.verifyNumParams(
      'LIMITSBAR',
      3,
      6,
      'LIMITSBAR <TARGET> <PACKET> <ITEM> <TYPE> <WIDTH> <HEIGHT>',
    )
  },
}
</script>
