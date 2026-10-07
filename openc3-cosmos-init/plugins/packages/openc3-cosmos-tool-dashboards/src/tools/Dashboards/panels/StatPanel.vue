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
      'stat d-flex flex-column flex-grow-1',
      { clickable: !!openDetails },
    ]"
    style="min-height: 0"
    @click="details"
  >
    <div class="d-flex align-baseline ga-1 px-4 pt-1">
      <span
        :class="['hero num', { 'text-disabled': stat.stale }]"
        data-test="stat-value"
      >
        {{ stat.text }}
      </span>
      <span class="text-body-2 text-medium-emphasis">{{ stat.units }}</span>
    </div>
    <div v-if="showBar" class="stat-limits px-4 pt-3">
      <limits-bar :limits="stat.limits" :value="stat.number" />
    </div>
    <!-- Only gets the space left over, so it never covers the rows around it -->
    <div v-if="showGraph" class="stat-spark pt-2">
      <sparkline
        class="h-100"
        :points="points"
        :limits="showLimitsLines ? stat.limits : null"
        :color="lineColor"
      />
    </div>
    <div v-else class="flex-grow-1" />
    <div
      v-if="packetTime"
      class="stat-time d-flex align-center justify-end ga-1 px-4 pb-2 text-caption text-medium-emphasis num"
      :title="`Packet time ${packetTime}`"
      data-test="stat-packet-time"
    >
      <v-icon icon="mdi-clock-outline" size="12" />
      <span class="text-truncate">{{ packetTime }}</span>
    </div>
  </div>
</template>

<script>
import tlmPanel from './tlmPanel'
import { itemOption, option } from './options'
import LimitsBar from '../components/LimitsBar.vue'
import Sparkline from '../components/Sparkline.vue'

// Sparkline samples, one per poll
const HISTORY_SAMPLES = 600

// One value, big. Container queries hide the extras as the panel shrinks:
// number only at the smallest size, then sparkline, then limits bar.
export default {
  components: { LimitsBar, Sparkline },
  mixins: [tlmPanel],
  data() {
    return { points: [] }
  },
  computed: {
    stat() {
      return this.itemStates[0] || { text: '--', units: '' }
    },
    // Custom COLOR, else blue for items with limits and grey without
    lineColor() {
      const item = this.panel.items[0]
      const custom = item && itemOption(this.panel, item, 'COLOR')
      if (custom) return custom
      return this.stat.limits
        ? 'rgb(var(--v-theme-secondary))'
        : 'rgba(var(--v-theme-on-surface), 0.38)'
    },
    showGraph() {
      return option(this.panel, 'GRAPH')
    },
    showLimitsLines() {
      return option(this.panel, 'LIMITS_LINES')
    },
    showBar() {
      return option(this.panel, 'LIMITS_BAR')
    },
  },
  watch: {
    // Live and replayed samples don't belong on the same line
    isPlayback() {
      this.points = []
    },
    playbackTime(time, previous) {
      if (!time || !previous || time < previous) this.points = []
    },
    // Sample once per poll, and only while the graph is shown
    'poller.clock.tick'() {
      if (!this.showGraph || this.stat.number === null) return
      this.points.push(this.stat.number)
      if (this.points.length > HISTORY_SAMPLES) this.points.shift()
    },
  },
  methods: {
    details() {
      if (this.openDetails && this.stat.item) this.openDetails(this.stat.item)
    },
  },
}
</script>

<style scoped>
.stat {
  container-type: size;
  overflow: hidden;
}
.stat-spark {
  flex: 1 1 0;
  min-height: 0;
}
.stat-time {
  flex: none;
}
.clickable {
  cursor: pointer;
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
@container (max-height: 60px) {
  .stat-time {
    display: none;
  }
}
@container (max-height: 160px) {
  .stat-limits {
    display: none;
  }
}
</style>
