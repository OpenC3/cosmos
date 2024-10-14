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
  mixins: [Widget],
  components: {
    LabelWidget,
    ValueWidget,
  },
  computed: {
    labelName() {
      let label = this.parameters[2]
      // Remove double bracket escaping. This means they actually have an item
      // with a bracket in the name, not an array index.
      if (label.includes('[[')) {
        label = label.replace('[[', '[').replace(']]', ']')
      }
      // LabelWidget uses index 0 from the parameters prop
      // so create an array with the label text in the first position
      return [label + ':']
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
