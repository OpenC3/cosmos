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
    <label-widget
      :parameters="labelName"
      :settings="[...appliedSettings]"
      :line="line"
      :line-number="lineNumber"
      :widget-index="0"
    />
    <value-widget
      v-bind="$attrs"
      :parameters="valueParameters"
      :settings="[...appliedSettings]"
      :screen-values="screenValues"
      :screen-time-zone="screenTimeZone"
      :line="line"
      :line-number="lineNumber"
      :widget-index="1"
    />
  </div>
</template>

<script>
import Widget from './Widget'
import LabelWidget from './LabelWidget.vue'
import ValueWidget from './ValueWidget.vue'

export default {
  components: {
    LabelWidget,
    ValueWidget,
  },
  mixins: [Widget],
  computed: {
    labelName() {
      // LabelWidget uses index 0 from the parameters prop
      // so create an array with the label text in the first position
      return [this.parseItemName(this.parameters[2]).display + ':']
    },
    valueParameters() {
      return [
        this.parameters[0],
        this.parameters[1],
        this.parameters[2],
        this.parameters[3],
        this.parameters[4],
        // Skip 5 which used to be the alignment of all the widgets together (left, split, right)
      ]
    },
  },
}
</script>
