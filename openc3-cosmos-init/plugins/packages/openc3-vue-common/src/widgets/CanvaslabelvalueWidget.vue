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
  <text
    :x="parameters[3]"
    :y="parameters[4]"
    :font-size="fontSize"
    :fill="fillColor"
  >
    {{ _value }}
  </text>
</template>

<script>
import Widget from './Widget'
export default {
  mixins: [Widget],
  emits: ['addItem', 'deleteItem'],
  data() {
    return {
      valueId: null,
    }
  },
  computed: {
    _value() {
      if (!this.screenValues[this.valueId]) {
        return ''
      }
      return this.screenValues[this.valueId][0]
    },
    fontSize() {
      if (this.parameters[5]) {
        return this.parameters[5] + 'px'
      }
      return '14px'
    },
    fillColor() {
      if (this.parameters[6]) {
        return this.parameters[6]
      }
      return 'black'
    },
  },
  created() {
    let type = 'CONVERTED'
    if (this.parameters[7]) {
      type = this.parameters[7]
    }
    this.valueId = `${this.parameters[0]}__${this.parameters[1]}__${this.parameters[2]}__${type}`
    this.$emit('addItem', this.valueId)
  },
  unmounted() {
    this.$emit('deleteItem', this.valueId)
  },
}
</script>
