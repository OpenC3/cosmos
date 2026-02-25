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
  <v-radio
    hide-details
    dense
    :label="label"
    :style="computedStyle"
    :value="value"
  />
</template>

<script>
import Widget from './Widget'

export default {
  mixins: [Widget],
  props: {
    value: {
      type: Number,
      default: null,
    },
  },
  data() {
    return {
      label: 'Radio',
    }
  },
  created() {
    this.label = this.parameters[0]
  },
}
</script>
