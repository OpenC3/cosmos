<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-select
    v-model="value"
    hide-details
    density="compact"
    variant="outlined"
    :items="items"
    :style="computedStyle"
  >
  </v-select>
</template>

<script>
import Widget from './Widget'

export default {
  mixins: [Widget],
  data() {
    return {
      items: [],
      value: null,
    }
  },
  created() {
    this.value = this.parameters[0]
    this.items = this.parameters
  },
  methods: {
    text() {
      return this.value
    },
  },
}
</script>
