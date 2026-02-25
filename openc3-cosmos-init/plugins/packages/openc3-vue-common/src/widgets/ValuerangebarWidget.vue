<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div ref="container" class="d-flex flex-row" :style="computedStyle">
    <value-widget
      v-bind="$attrs"
      :parameters="valueParameters"
      :settings="[...appliedSettings]"
      :screen-values="screenValues"
      :screen-time-zone="screenTimeZone"
      :widget-index="0"
    />
    <rangebar-widget
      v-bind="$attrs"
      :parameters="rangeBarParameters"
      :settings="[...appliedSettings]"
      :screen-values="screenValues"
      :widget-index="1"
    />
  </div>
</template>

<script>
import ValueWidget from './ValueWidget.vue'
import RangebarWidget from './RangebarWidget.vue'
import Widget from './Widget'

export default {
  components: {
    ValueWidget,
    RangebarWidget,
  },
  mixins: [Widget],
  computed: {
    valueParameters() {
      return [
        this.parameters[0],
        this.parameters[1],
        this.parameters[2],
        // Skip 3,4 which is range min,max
        this.parameters[5],
        this.parameters[6], // num characters
      ]
    },
    rangeBarParameters() {
      return [
        this.parameters[0],
        this.parameters[1],
        this.parameters[2],
        this.parameters[3],
        this.parameters[4],
        this.parameters[5],
        // Skip 6 which is num chars
        this.parameters[7],
        this.parameters[8],
      ]
    },
  },
}
</script>
