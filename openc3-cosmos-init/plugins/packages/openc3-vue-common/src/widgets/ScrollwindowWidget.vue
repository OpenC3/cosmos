<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div ref="container" :style="computedStyle" class="overflow-y-auto">
    <template v-for="(widget, index) in widgets" :key="index">
      <v-tooltip
        v-if="getTooltipText(widget)"
        :open-delay="getTooltipDelay(widget)"
        location="top"
        :activator-props="getTooltipActivatorProps(widget)"
      >
        <template #activator="{ props }">
          <component
            :is="widget.type"
            v-bind="{ ...listeners, ...props }"
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
        </template>
        <span>{{ getTooltipText(widget) }}</span>
      </v-tooltip>
      <component
        :is="widget.type"
        v-else
        v-bind="listeners"
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
    </template>
  </div>
</template>

<script>
import Layout from './Layout'

export default {
  mixins: [Layout],
  created: function () {
    this.setHeight(this.parameters[0], 'px', 200)
    if (this.parameters[1]) {
      let margin = this.parameters[1]
      this.widgets.forEach((widget) => {
        // Don't push MARGIN on a widget that's already defined it
        const found = widget.settings.find(
          (setting) =>
            setting[0] === 'MARGIN' ||
            (setting[0].startsWith('RAW') &&
              setting[1].toUpperCase().includes('MARGIN')),
        )
        if (found === undefined) {
          widget.settings.push(['MARGIN', margin])
        }
      })
    }
  },
}
</script>
