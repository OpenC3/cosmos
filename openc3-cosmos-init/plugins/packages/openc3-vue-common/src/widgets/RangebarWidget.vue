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
  <div class="rangebar" :style="[cssProps, computedStyle]">
    <div class="rangebar__container">
      <div class="rangebar__line" />
      <div class="rangebar__arrow" />
    </div>
  </div>
</template>

<script>
import Widget from './Widget'

export default {
  mixins: [Widget],
  data() {
    return {
      width: 160, // px
      height: 22, // px
    }
  },
  computed: {
    cssProps() {
      return {
        '--height': this.height + 'px',
        '--width': this.width + 'px',
        '--container-height': this.height - 5 + 'px',
        '--position': this.calcPosition() + '%',
      }
    },
    min() {
      return parseInt(this.parameters[3])
    },
    max() {
      return parseInt(this.parameters[4])
    },
    range() {
      return this.max - this.min
    },
  },
  created() {
    const type = this.parameters[5] ? this.parameters[5] : 'CONVERTED'
    this.valueId = `${this.parameters[0]}__${this.parameters[1]}__${this.parameters[2]}__${type}`
    this.$emit('addItem', this.valueId)

    this.width = this.setWidth(this.parameters[6], 'px', this.width)
    this.height = this.setHeight(this.parameters[7], 'px', this.height)
  },
  unmounted() {
    this.$emit('deleteItem', this.valueId)
  },
  methods: {
    calcPosition() {
      let value = this.screenValues[this.valueId][0]
      if (!value) {
        return 0
      }
      if (value.raw) {
        if (value.raw === '-Infinity') {
          return 0
        } else {
          // NaN and Infinity
          return 100
        }
      }
      const result = ((value - this.min) / this.range) * 100
      if (result > 100) {
        return 100
      } else if (result < 0) {
        return 0
      } else {
        return result
      }
    },
  },
}
</script>

<style lang="scss" scoped>
.rangebar {
  cursor: default;
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 5px;
  padding-top: 15px;
  width: var(--width);
  margin-bottom: 5px;
}
.rangebar__container {
  position: relative;
  flex: 1;
  height: var(--container-height);
  border: 1px solid black;
  background-color: white;
}
.rangebar__line {
  position: absolute;
  left: var(--position);
  width: 1px;
  height: var(--container-height);
  background-color: rgb(128, 128, 128);
}
$arrow-size: 5px;
.rangebar__arrow {
  position: absolute;
  top: -$arrow-size;
  left: var(--position);
  width: 0;
  height: 0;
  transform: translateX(-$arrow-size); // Transform so it sits over the line
  border-left: $arrow-size solid transparent;
  border-right: $arrow-size solid transparent;
  border-top: $arrow-size solid rgb(128, 128, 128);
}
</style>
