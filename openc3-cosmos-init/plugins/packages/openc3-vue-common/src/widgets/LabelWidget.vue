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
  <div data-test="label" class="pa-1 label" :style="[cssProps, computedStyle]">
    {{ labelText }}
  </div>
</template>

<script>
import Widget from './Widget'

export default {
  mixins: [Widget],
  data() {
    return {
      fontFamily: null,
      fontSize: null,
      fontWeight: 'normal',
      fontStyle: 'normal',
    }
  },
  computed: {
    labelText() {
      return this.parameters[0]
    },
    cssProps() {
      let size = null
      if (this.fontSize) {
        size = this.fontSize + 'px'
      }
      return {
        '--font-family': this.fontFamily,
        '--font-size': size,
        '--font-weight': this.fontWeight,
        '--font-style': this.fontStyle,
      }
    },
  },
  created() {
    this.verifyNumParams(
      'LABEL',
      1,
      5,
      'LABEL <Text> <Font Family> <Font Size> <Font Weight> <Font Style>',
    )
    if (this.parameters[1]) {
      this.fontFamily = this.parameters[1]
    }
    if (this.parameters[2]) {
      this.fontSize = this.parameters[2]
    }
    if (this.parameters[3]) {
      this.fontWeight = this.parameters[3]
    }
    if (this.parameters[4]) {
      this.fontStyle = this.parameters[4]
    }
  },
}
</script>

<style scoped>
.label {
  font-family: var(--font-family);
  font-size: var(--font-size);
  font-weight: var(--font-weight);
  font-style: var(--font-style);
}
</style>
