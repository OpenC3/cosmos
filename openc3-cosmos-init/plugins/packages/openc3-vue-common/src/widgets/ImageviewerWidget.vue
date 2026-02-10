<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <img
    :src="src"
    :alt="valueId"
    :width="parameters[4]"
    :height="parameters[5]"
    :style="computedStyle"
  />
</template>

<script>
import Widget from './Widget'

export default {
  mixins: [Widget],
  emits: ['addItem', 'deleteItem'],
  data: function () {
    return {
      valueId: null,
      imageData: '',
    }
  },
  computed: {
    src: function () {
      if (!this.screenValues[this.valueId]) {
        return ''
      }
      return `data:image/${this.parameters[3]};base64, ${this.screenValues[this.valueId][0]}`
    },
  },
  created: function () {
    // TODO: We're hard coding CONVERTED because the existing 4th parameter is the image format
    // Future breaking change would be to put the type as 4th and format as fifth
    this.valueId = `${this.parameters[0]}__${this.parameters[1]}__${this.parameters[2]}__CONVERTED`
    this.$emit('addItem', this.valueId)
  },
  unmounted: function () {
    this.$emit('deleteItem', this.valueId)
  },
}
</script>
