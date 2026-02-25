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
  <line
    :x1="parameters[0]"
    :y1="parameters[1]"
    :x2="parameters[2]"
    :y2="parameters[3]"
    :style="calcStyle"
  />
</template>

<script>
import Widget from './Widget'
export default {
  mixins: [Widget],
  computed: {
    calcStyle() {
      let color = 'black'
      if (this.parameters[4]) {
        color = this.parameters[4]
      }
      let width = 1
      if (this.parameters[5]) {
        width = this.parameters[5]
      }
      return 'stroke:' + color + ';stroke-width:' + width
    },
  },
}
</script>
