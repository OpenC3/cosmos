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
  <svg id="canvas" :width="width" :height="height">
    <component
      v-bind="listeners"
      :is="widget.type"
      v-for="(widget, index) in widgets"
      :key="index"
      :target="widget.target"
      :parameters="widget.parameters"
      :settings="widget.settings"
      :screen-values="screenValues"
      :screen-time-zone="screenTimeZone"
      :widgets="widget.widgets"
      :name="widget.name"
      :line="widget.line"
      :line-number="widget.lineNumber"
    />
  </svg>
</template>

<script>
import Layout from './Layout'
export default {
  mixins: [Layout],
  computed: {
    width() {
      return this.parameters[0] + 'px'
    },
    height() {
      return this.parameters[1] + 'px'
    },
  },
}
</script>

<style lang="scss" scoped>
svg {
  background-color: white;
}
</style>
