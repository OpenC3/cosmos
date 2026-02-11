<!--
# Copyright 2024 OpenC3, Inc.
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
  <div :style="computedStyle" />
</template>

<script>
import Widget from './Widget'

export default {
  mixins: [Widget],
  created() {
    // Populate the applied settings as if they were in the screen definition
    if (this.parameters[0] !== undefined) {
      this.appliedSettings.push(['WIDTH', this.parameters[0]])
    }
    if (this.parameters[1] !== undefined) {
      this.appliedSettings.push(['HEIGHT', this.parameters[1]])
    }
  },
}
</script>
