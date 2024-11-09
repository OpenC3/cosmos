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
  <line
    :x1="parameters[3]"
    :y1="parameters[4]"
    :x2="parameters[5]"
    :y2="parameters[6]"
    :style="calcStyle"
  />
</template>

<script>
import Widget from './Widget'
export default {
  mixins: [Widget],
  data() {
    return {
      valueId: 0,
      valueMap: {},
    }
  },
  computed: {
    calcStyle() {
      let color = 'black'
      if (this.screenValues[this.valueId]) {
        color = this.valueMap[this.screenValues[this.valueId][0]]
      }
      let width = 1
      if (this.parameters[7]) {
        width = this.parameters[7]
      }
      return 'stroke:' + color + ';stroke-width:' + width
    },
  },
  created() {
    // Look through the settings for our color value mappings
    this.appliedSettings.forEach((setting) => {
      if (setting[0] === 'VALUE_EQ') {
        this.valueMap[setting[1]] = setting[2]
      }
    })

    let type = 'CONVERTED'
    if (this.parameters[8]) {
      type = this.parameters[8]
    }
    this.valueId = `${this.parameters[0]}__${this.parameters[1]}__${this.parameters[2]}__${type}`
    this.$emit('addItem', this.valueId)
  },
  unmounted() {
    this.$emit('deleteItem', this.valueId)
  },
}
</script>
