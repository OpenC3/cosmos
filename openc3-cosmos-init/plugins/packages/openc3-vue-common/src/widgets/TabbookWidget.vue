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
  <div>
    <v-tabs v-model="curTab" :style="computedStyle">
      <v-tab v-for="(tab, index) in widgets" :key="index">
        {{ tab.parameters[0] }}
      </v-tab>
    </v-tabs>
    <v-window v-model="curTab">
      <v-window-item v-for="(tab, tabIndex) in widgets" :key="tabIndex">
        <template
          v-for="(widget, widgetIndex) in tab.widgets"
          :key="`${tabIndex}-${widgetIndex}`"
        >
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
      </v-window-item>
    </v-window>
  </div>
</template>

<script>
import Layout from './Layout'
export default {
  mixins: [Layout],
  emits: ['min-max-screen'],
  data: function () {
    return {
      curTab: null,
    }
  },
  watch: {
    curTab: function () {
      this.$emit('min-max-screen')
    },
  },
}
</script>
