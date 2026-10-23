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
      'stat d-flex flex-column flex-grow-1 min-h-0 overflow-hidden position-relative',
      { 'cursor-pointer': !!openDetails },
    ]"
    :style="{ '--stat-color': levelColor }"
    :data-hovered="hovered ? '' : undefined"
    @click="showDetails()"
  >
    <div class="stat-value d-flex align-baseline ga-1 pt-1">
      <span
        :class="['hero num', { 'text-disabled': first.stale }]"
        data-test="stat-value"
      >
        {{ first.text }}
      </span>
      <!-- Compact panels have no room for the hover label, so the hovered
           value takes the live value's place (container query) -->
      <span v-if="hovered" class="hero hero-hover num">
        {{ hovered.value }}
      </span>
      <span class="text-body-2 text-medium-emphasis">{{ first.units }}</span>
    </div>
    <div v-if="showBar" class="stat-limits px-4 pt-3">
      <limits-bar :limits="first.limits" :value="first.number" />
    </div>
    <!-- Only gets the space left over, so it never covers the rows around
         it; behind the value when the panel is too short (container query) -->
    <div v-if="showGraph" class="stat-spark flex-1-1-0 min-h-0">
      <div
        v-if="hovered"
        class="hover-label position-absolute pointer-events-none rounded text-caption num"
        data-test="stat-hover"
      >
        <b>{{ hovered.value }}</b> {{ first.units }} · {{ hovered.time }}
      </div>
      <sparkline
        class="h-100"
        area
        :hover-time="hover.time"
        :points="points"
        :times="times"
        :window="[now - duration, now]"
        :limits="showLimitsLines ? first.limits : null"
        :color="lineColor"
        @hover="setHover"
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
import { clock, formatTelemetry } from '../composables/format'

// One value, big. Container queries hide the extras as the panel shrinks:
// number only at the smallest size, then sparkline, then limits bar. The
// sparkline shows the dashboard's time range, backfilled when the dashboard
// opens (tlmSeries). Hovering it shares the time with the dashboard's graphs,
// and it marks theirs, with the value at that time.
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
    // The value takes its limits color when the panel is compact
    levelColor() {
      const level = this.first.level
      return ['critical', 'caution', 'normal'].includes(level)
        ? `var(--color-status-${level})`
        : null
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
    // The value nearest the hovered time, from any graph on the dashboard.
    // Past the newest sample it's still the newest value (slow items), but
    // before the history starts there's nothing to show.
    hovered() {
      const time = this.hover.time
      const times = this.times
      if (time === null || !times.length || time < times[0]) return null
      if (time > this.now) return null
      let low = 0
      let high = times.length - 1
      while (high - low > 1) {
        const mid = (low + high) >> 1
        if (times[mid] < time) low = mid
        else high = mid
      }
      const index =
        time >= times.at(-1)
          ? times.length - 1
          : time - times[low] <= times[high] - time
            ? low
            : high
      const value = this.points[index]
      if (typeof value !== 'number') return null
      const item = this.panel.items[0]
      const formatString = item && this.itemInfo.get(item).formatString
      return {
        value: formatString
          ? formatTelemetry(value, formatString)
          : Number(value.toPrecision(6)).toString(),
        // The hovered time, not the sample's, so it moves smoothly like the
        // graphs' tooltips
        time: clock(time * 1000, this.timeZone),
      }
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
/* Padding in CSS rather than utilities so the queries below can change it */
.stat-value {
  position: relative;
  z-index: 1;
  padding-inline: 16px;
}
.stat-spark {
  position: relative;
  padding-top: 8px;
}
.stat-spark :deep(.spark-area),
.hero-hover {
  display: none;
}
.hover-label {
  top: 6px;
  right: 12px;
  z-index: 1;
  padding: 0 6px;
  background: rgba(var(--v-theme-surface), 0.85);
}
/* Too short for the graph under the value (3 rows or less): like Grafana's
   stat panel, the value big in its limits color over an area graph along
   the bottom, edge to edge */
@container (max-height: 120px) {
  .stat-spark {
    position: absolute;
    inset: auto 0 0;
    height: 65%;
    padding-top: 0;
    pointer-events: none;
  }
  .stat-spark :deep(.spark-area) {
    display: inline;
  }
  .hover-label,
  .stat[data-hovered] .hero:not(.hero-hover) {
    display: none;
  }
  .hero-hover {
    display: inline;
  }
  .stat-value {
    justify-content: center;
    margin-block: auto;
  }
  .hero {
    color: var(--stat-color, inherit);
    font-size: clamp(18px, min(22cqw, 60cqh), 64px);
    font-weight: 600;
  }
  .stat-time {
    position: relative;
    z-index: 1;
  }
}
/* One column wide */
@container (max-width: 120px) {
  .stat-value {
    padding-inline: 8px;
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
