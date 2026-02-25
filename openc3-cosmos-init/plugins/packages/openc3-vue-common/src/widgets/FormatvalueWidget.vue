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
  <div ref="container" class="d-flex flex-row" :style="computedStyle">
    <value-widget
      v-bind="$attrs"
      :parameters="getParameters"
      :settings="appliedSettings"
      :screen-values="screenValues"
      :screen-time-zone="screenTimeZone"
      :format-string="parameters[3]"
    />
  </div>
</template>

<script>
// When we apply a fixed character width we need to pad a bit since the
// width applies to the enclosing div and not the underlying input
const INPUT_PADDING = 4
import Widget from './Widget'
import ValueWidget from './ValueWidget.vue'

export default {
  components: {
    ValueWidget,
  },
  mixins: [Widget],
  computed: {
    getParameters() {
      return [
        this.parameters[0],
        this.parameters[1],
        this.parameters[2],
        this.parameters[4],
      ]
    },
  },
  created() {
    this.setWidth(
      Number.parseInt(this.parameters[5]) + INPUT_PADDING,
      'ch',
      12 + INPUT_PADDING,
    )
  },
}
</script>
