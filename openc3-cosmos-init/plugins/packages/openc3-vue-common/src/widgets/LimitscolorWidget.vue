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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div ref="container" class="d-flex flex-row" :style="myComputedStyle">
    <div
      :class="`led align-self-center ${this.limitsColor}`"
      :style="cssProps"
    ></div>
    <label-widget
      v-if="displayLabel"
      :parameters="labelName"
      :settings="appliedSettings"
      :style="computedStyle"
      :widget-index="1"
    />
  </div>
</template>

<script>
import VWidget from './VWidget'
export default {
  mixins: [VWidget],
  data() {
    return {
      radius: 15,
      fullLabelDisplay: false,
      displayLabel: true,
    }
  },
  created() {
    if (this.parameters[4]) {
      this.radius = parseInt(this.parameters[4])
    }
    if (this.parameters[5]) {
      if (this.parameters[5].toLowerCase() === 'true') {
        this.fullLabelDisplay = true
      } else if (this.parameters[5].toLowerCase() === 'nil') {
        this.displayLabel = false
      } else if (this.parameters[5].toLowerCase() === 'none') {
        this.displayLabel = false
      }
    }
  },
  computed: {
    labelName() {
      // LabelWidget uses index 0 from the parameters prop
      // so create an array with the label text in the first position
      if (this.fullLabelDisplay) {
        return [
          this.parameters[0] +
            ' ' +
            this.parameters[1] +
            ' ' +
            this.parameters[2],
        ]
      } else {
        return [this.parameters[2]]
      }
    },
    cssProps() {
      return {
        '--height': this.radius + 'px',
        '--width': this.radius + 'px',
      }
    },
    myComputedStyle() {
      // Remove the flex property from the computedStyle object
      // because if they choose not to display the label
      // the flex property makes it difficult to line up a custom LABEL widget
      delete this.computedStyle.flex
      return this.computedStyle
    },
  },
  methods: {
    getType() {
      let type = 'CONVERTED'
      if (this.parameters[3]) {
        type = this.parameters[3]
      }
      return type
    },
  },
}
</script>

<style scoped>
.led {
  height: var(--height);
  width: var(--width);
  background-color: var(--color);
  border-radius: 50%;
}
/* The background-colors match the values in LimitsbarWidget.vue */
.red {
  background-color: rgb(255, 45, 45);
}
.yellow {
  background-color: rgb(255, 220, 0);
}
.green {
  background-color: rgb(0, 200, 0);
}
.blue {
  background-color: rgb(0, 153, 255);
}
</style>
