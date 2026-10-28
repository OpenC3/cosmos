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
        {{ valueText }}
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
      <!-- The graphs' tooltip, beside the crosshair -->
      <div
        v-if="tip"
        class="db-tip position-absolute pointer-events-none text-no-wrap text-caption bg-surface-light rounded-lg border pa-2 elevation-4"
        :style="{
          left: `${tip.left}%`,
          transform: tip.flip
            ? 'translateX(calc(-100% - 12px))'
            : 'translateX(12px)',
        }"
        data-test="stat-hover"
      >
        <div class="num font-weight-bold mb-1">{{ hovered.time }}</div>
        <div class="d-flex align-center justify-space-between ga-3">
          <span class="d-inline-flex align-center ga-2 text-medium-emphasis">
            <span class="db-swatch" :style="{ background: lineColor }" />
            {{ first.label }}
          </span>
          <span>
            <b class="num">{{ hovered.value }}</b> {{ first.units }}
          </span>
        </div>
      </div>
      <sparkline
        class="h-100"
        area
        :hover-time="hover.time"
        :points="series[1] || []"
        :times="series[0]"
        :version="version"
        :window="sparkWindow"
        :limits="showLimitsLines ? first.limits : null"
        :color="lineColor"
        @hover="pointAt"
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

<script setup>
import { computed, ref } from 'vue'
import { panelProps } from './panelBase'
import { useTlmPanel } from './tlmPanel'
import { hoverReach, nearestValue, useTlmSeries } from './tlmSeries'
import { itemOption, option } from './options'
import LimitsBar from '../components/LimitsBar.vue'
import PacketTime from '../components/PacketTime.vue'
import Sparkline from '../components/Sparkline.vue'
import { clock, compactNumber, formatTelemetry } from '../composables/format'

// One value, big. Container queries hide the extras as the panel shrinks:
// number only at the smallest size, then sparkline, then limits bar. The
// sparkline shows the dashboard's time range, backfilled when the dashboard
// opens (useTlmSeries). Hovering it shares the time with the dashboard's
// graphs, and it marks theirs, with the value at that time.
const props = defineProps(panelProps)
const panel = useTlmPanel(props)
const {
  first,
  packetTime,
  showDetails,
  openDetails,
  itemInfo,
  timeZone,
  isNarrow,
} = panel
// Small panels (2 columns or less) shorten numbers so they fit
const valueText = computed(() =>
  isNarrow.value && typeof first.value.number === 'number'
    ? compactNumber(first.value.number)
    : first.value.text,
)
const { hover, now, duration, series, setHover } = useTlmSeries(props, panel, {
  // Only streamed while the graph is shown
  seriesItems: () => (showGraph.value ? props.panel.items.slice(0, 1) : []),
  // The series are the store's arrays, changed in place: bump the version
  // so the sparkline redraws, rather than copying them
  seriesUpdated: () => {
    version.value++
    // Like the graphs: the sparkline scrolled under a still mouse, so the
    // hover is the time under it now
    if (pointer !== null) setHover(windowStart() + pointer * duration.value)
  },
})

const version = ref(0)
// Where the mouse is across the sparkline (0 to 1), null when it's not over
// it. Not reactive: only read when the series update.
let pointer = null

// The sparkline's [start, end]: a new array only when the window moves
// (about once a second), so hovering doesn't redraw its line
const sparkWindow = computed(() => [now.value - duration.value, now.value])

function windowStart() {
  return now.value - duration.value
}
// The sparkline's hover: share the time and remember where the mouse is
function pointAt(time) {
  pointer = time === null ? null : (time - windowStart()) / duration.value
  setHover(time)
}

// Custom COLOR, else the theme's secondary color for items with limits and
// a muted one without
const lineColor = computed(() => {
  const item = props.panel.items[0]
  const custom = item && itemOption(props.panel, item, 'COLOR')
  if (custom) return custom
  return first.value.limits
    ? 'rgb(var(--v-theme-secondary))'
    : 'rgba(var(--v-theme-on-surface), 0.38)'
})
// The value takes its limits color when the panel is compact
const levelColor = computed(() => {
  const level = first.value.level
  return ['critical', 'caution', 'normal'].includes(level)
    ? `var(--color-status-${level})`
    : null
})
const showGraph = computed(() => option(props.panel, 'GRAPH'))
const showLimitsLines = computed(() => option(props.panel, 'LIMITS_LINES'))
const showBar = computed(() => option(props.panel, 'LIMITS_BAR'))
// The value nearest the hovered time, from any graph on the dashboard.
// Past the newest sample it's still the newest value (slow items), but
// before the history starts there's nothing to show.
const hovered = computed(() => {
  const time = hover.time
  if (time === null || time > now.value) return null
  // The arrays change in place; the version says when
  void version.value
  const value = nearestValue(
    series[0],
    series[1],
    time,
    hoverReach(duration.value),
  )
  if (value === null) return null
  const item = props.panel.items[0]
  const formatString = item && itemInfo.get(item).formatString
  let text = Number(value.toPrecision(6)).toString()
  if (isNarrow.value) text = compactNumber(value)
  else if (formatString) text = formatTelemetry(value, formatString)
  return {
    value: text,
    // The hovered time, not the sample's, so it moves smoothly like the
    // graphs' tooltips
    time: clock(time * 1000, timeZone.value),
  }
})
// Where the tooltip goes: percent across the sparkline. Like the graphs',
// it flips sides past 62% across and back under 38%, so it doesn't flicker
// from side to side around one spot.
const tip = computed((previous) => {
  if (!hovered.value) return null
  const left = ((hover.time - windowStart()) / duration.value) * 100
  if (left < 0 || left > 100) return null
  return { left, flip: previous?.flip ? left > 38 : left > 62 }
})
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
  .db-tip,
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
