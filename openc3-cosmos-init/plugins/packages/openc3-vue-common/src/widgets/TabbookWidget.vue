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
  <div>
    <v-tabs v-model="curTab" :style="computedStyle">
      <v-tab v-for="(tab, index) in widgets" :key="index">
        <rux-status
          v-if="tabColors[index]"
          class="tab-status"
          :status="astroStatus(tabColors[index])"
          :data-test="`tab-status-${index}`"
        />
        {{ tab.parameters[0] }}
        <!-- Empty span covering the whole tab so the limits color class
             only colors the border, not the tab text -->
        <span
          v-if="tabColors[index]"
          :class="['tab-limits', `openc3-${tabColors[index]}`]"
          :data-test="`tab-limits-${index}`"
          :data-limits-color="tabColors[index]"
        />
      </v-tab>
    </v-tabs>
    <v-window v-model="curTab">
      <v-window-item
        v-for="(tab, tabIndex) in widgets"
        :key="tabIndex"
        :eager="eager"
      >
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
                v-bind="{ ...tabListeners[tabIndex], ...props }"
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
            v-bind="tabListeners[tabIndex]"
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
import { limitsColor, astroStatus } from './LimitsColor'

// Higher is worse. BLUE is a normal state so it counts as GREEN.
const SEVERITY = { green: 1, blue: 1, yellow: 2, red: 3 }

export default {
  mixins: [Layout],
  // A TABBOOK nested in a LIMITS_STATE TABBOOK must render all its tabs too,
  // or items on its hidden tabs never reach the outer tab's outline
  inject: {
    parentLimitsEager: { from: 'tabbookLimitsEager', default: false },
  },
  provide: function () {
    return { tabbookLimitsEager: this.eager }
  },
  emits: ['min-max-screen'],
  data: function () {
    // Read here rather than in created because provide runs before created
    const limitsEnabled = this.settings.some(
      (setting) =>
        String(setting[0]).toUpperCase() === 'LIMITS_STATE' &&
        String(setting[1]).toUpperCase() === 'TRUE',
    )
    return {
      curTab: null,
      limitsEnabled: limitsEnabled,
      eager: limitsEnabled || this.parentLimitsEager,
      // One object per tab mapping valueId to the number of widgets on that
      // tab displaying it, so removing one widget doesn't drop an item that
      // another widget on the tab still shows
      tabItems: [],
    }
  },
  computed: {
    // With LIMITS_STATE we intercept the addItem / deleteItem events from
    // each tab's widgets to learn which items are on which tab, then pass
    // them on to the screen as usual
    tabListeners: function () {
      const listeners = this.listeners
      return this.widgets.map((tab, tabIndex) => {
        if (!this.limitsEnabled) {
          return listeners
        }
        return {
          ...listeners,
          onAddItem: (valueId) => {
            this.trackItem(tabIndex, valueId, 1)
            listeners.onAddItem?.(valueId)
          },
          onDeleteItem: (valueId) => {
            this.trackItem(tabIndex, valueId, -1)
            listeners.onDeleteItem?.(valueId)
          },
        }
      })
    },
    // The worst limits color of the items on each tab, or null if none of
    // them are in a limits state
    tabColors: function () {
      return this.widgets.map((tab, tabIndex) => {
        if (!this.limitsEnabled) {
          return null
        }
        let worst = null
        for (const valueId of Object.keys(this.tabItems[tabIndex] || {})) {
          const color = limitsColor(this.screenValues[valueId]?.[1])
          if (SEVERITY[color] > (SEVERITY[worst] || 0)) {
            worst = color
          }
        }
        return worst === 'blue' ? 'green' : worst
      })
    },
  },
  watch: {
    curTab: function () {
      this.$emit('min-max-screen')
    },
  },
  created: function () {
    this.tabItems = this.widgets.map(() => ({}))
  },
  methods: {
    astroStatus: astroStatus,
    trackItem: function (tabIndex, valueId, delta) {
      this.tabItems[tabIndex] ??= {}
      const items = this.tabItems[tabIndex]
      const count = (items[valueId] || 0) + delta
      if (count > 0) {
        items[valueId] = count
      } else {
        delete items[valueId]
      }
    },
  },
}
</script>

<style scoped>
.tab-status {
  margin-right: 6px;
}
/* Absolutely positioned against the v-tab button so it outlines the
   whole tab rather than just the text */
.tab-limits {
  position: absolute;
  inset: 0;
  border: 2px solid currentColor;
  pointer-events: none;
}
</style>
