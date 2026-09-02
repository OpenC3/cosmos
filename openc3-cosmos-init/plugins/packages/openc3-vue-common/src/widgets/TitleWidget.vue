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
  <div class="text-h5 text-center pa-1 mt-1 label" :style="computedStyle">
    {{ labelText }}
  </div>
</template>

<script>
import Widget from './Widget'

export default {
  mixins: [Widget],
  computed: {
    labelText() {
      return this.parameters[0]
    },
  },
  created() {
    // Breaking change: COSMOS 4 took TITLE <Text> <Font> <Size> <Weight>
    // <Italics> and those were silently ignored here for years. Style with
    // SETTING instead, i.e. SETTING RAW font-family Courier.
    this.verifyNumParams('TITLE', 1, 1, 'TITLE <Text>')
  },
}
</script>
