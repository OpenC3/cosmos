<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div
    :class="[
      'stat d-flex flex-column flex-grow-1 min-h-0 overflow-hidden',
      { 'cursor-pointer': !!openDetails },
    ]"
    @click="showDetails()"
  >
    <div class="d-flex align-baseline ga-1 px-4 pt-1">
      <span
        :class="['hero num', { 'text-disabled': first.stale }]"
        data-test="stat-value"
      >
        {{ first.text }}
      </span>
      <span class="text-body-2 text-medium-emphasis">{{ first.units }}</span>
    </div>
    <div v-if="showBar" class="stat-limits px-4 pt-3">
      <limits-bar :limits="first.limits" :value="first.number" />
    </div>
    <!-- Only gets the space left over, so it never covers the rows around it -->
    <div v-if="showGraph" class="stat-spark flex-1-1-0 min-h-0 pt-2">
      <sparkline
        class="h-100"
        :points="points"
        :times="times"
        :window="[now - duration, now]"
        :limits="showLimitsLines ? first.limits : null"
        :color="lineColor"
      />
    </div>
    <div v-else class="flex-grow-1" />
    <packet-time
      v-if="packetTime"
      :time="packetTime"
      class="stat-time px-4 pb-2"
      data-test="stat-packet-time"
    />
  </div>
</template>

<script>
import tlmPanel from './tlmPanel'
import tlmSeries from './tlmSeries'
import { itemOption, option } from './options'
import LimitsBar from '../components/LimitsBar.vue'
import PacketTime from '../components/PacketTime.vue'
import Sparkline from '../components/Sparkline.vue'

// One value, big. Container queries hide the extras as the panel shrinks:
// number only at the smallest size, then sparkline, then limits bar. The
// sparkline shows the dashboard's time range, backfilled when the dashboard
// opens (tlmSeries).
export default {
  components: { LimitsBar, PacketTime, Sparkline },
  mixins: [tlmPanel, tlmSeries],
  data() {
    return { points: [], times: [] }
  },
  computed: {
    // Custom COLOR, else blue for items with limits and grey without
    lineColor() {
      const item = this.panel.items[0]
      const custom = item && itemOption(this.panel, item, 'COLOR')
      if (custom) return custom
      return this.first.limits
        ? 'rgb(var(--v-theme-secondary))'
        : 'rgba(var(--v-theme-on-surface), 0.38)'
    },
    showGraph() {
      return option(this.panel, 'GRAPH')
    },
    // Only streamed while the graph is shown
    seriesItems() {
      return this.showGraph ? this.panel.items.slice(0, 1) : []
    },
    showLimitsLines() {
      return option(this.panel, 'LIMITS_LINES')
    },
    showBar() {
      return option(this.panel, 'LIMITS_BAR')
    },
  },
  methods: {
    // tlmSeries hook: copies, so the sparkline sees the change
    seriesUpdated() {
      this.times = [...this.series[0]]
      this.points = [...(this.series[1] || [])]
    },
  },
}
</script>

<style scoped>
.stat {
  container-type: size;
}
.stat-limits {
  --limits-bar-track: 10px;
}
.hero {
  /* Scales with the panel so narrow tiles show the whole value */
  font-size: clamp(18px, min(13cqw, 30cqh), 34px);
  font-weight: 500;
  letter-spacing: -0.01em;
  line-height: 1.1;
}
@container (max-height: 90px) {
  .stat-spark {
    display: none;
  }
}
/* !important to win over the time's d-flex utility */
@container (max-height: 60px) {
  .stat-time {
    display: none !important;
  }
}
@container (max-height: 160px) {
  .stat-limits {
    display: none;
  }
}
</style>
