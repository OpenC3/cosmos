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
  <v-text-field
    v-model="value"
    variant="solo"
    density="compact"
    single-line
    hide-no-data
    hide-details
    :style="computedStyle"
  >
  </v-text-field>
</template>

<script>
import Widget from './Widget'

export default {
  mixins: [Widget],
  data() {
    return {
      value: null,
    }
  },
  created() {
    this.setWidth(this.parameters[0], 'ch', 12)
    if (this.parameters[1]) {
      this.value = this.parameters[1]
    }
  },
  methods: {
    text() {
      return this.value
    },
  },
}
</script>
