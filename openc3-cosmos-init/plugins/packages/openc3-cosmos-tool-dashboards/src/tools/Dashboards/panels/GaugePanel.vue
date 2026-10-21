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
      'd-flex flex-column flex-grow-1 min-h-0 overflow-hidden',
      { 'cursor-pointer': !!openDetails },
    ]"
    @click="showDetails()"
  >
    <svg
      viewBox="0 0 200 160"
      preserveAspectRatio="xMidYMid meet"
      class="flex-grow-1 w-100 min-h-0 pt-1 px-3"
      role="img"
      :aria-label="`${first.text} ${first.units}`"
    >
      <path :d="arc(0, 1)" class="track" />
      <path
        v-for="(zone, index) in zones"
        :key="index"
        :d="arc(zone.from, zone.to)"
        :class="['zone', `z-${zone.level}`]"
      />
      <line
        v-if="marker"
        :x1="marker.x1"
        :y1="marker.y1"
        :x2="marker.x2"
        :y2="marker.y2"
        :class="['marker', level ? `m-${level}` : '']"
        data-test="gauge-marker"
      />
      <text
        x="100"
        y="98"
        text-anchor="middle"
        :class="['value num', { stale: first.stale }]"
        data-test="gauge-value"
      >
        {{ first.text }}
      </text>
      <text x="100" y="118" text-anchor="middle" class="units">
        {{ first.units }}
      </text>
      <template v-if="scale">
        <text
          :x="$options.ENDS.min.x"
          :y="$options.ENDS.min.y"
          text-anchor="middle"
          class="end num"
          data-test="gauge-min"
        >
          {{ compact(scale.min) }}
        </text>
        <text
          :x="$options.ENDS.max.x"
          :y="$options.ENDS.max.y"
          text-anchor="middle"
          class="end num"
          data-test="gauge-max"
        >
          {{ compact(scale.max) }}
        </text>
      </template>
    </svg>
    <packet-time
      v-if="packetTime"
      :time="packetTime"
      class="px-4 pb-2"
      data-test="gauge-packet-time"
    />
  </div>
</template>

<script>
import tlmPanel from './tlmPanel'
import { option } from './options'
import PacketTime from '../components/PacketTime.vue'
import { levelOf, limitZones, paddedScale } from '../limits'

const CX = 100
const CY = 100
const RADIUS = 80
// The arc runs clockwise from START degrees (math angle, 0 = right, up is
// positive) through SWEEP degrees, leaving a gap at the bottom
const START = 210
const SWEEP = 240

function angle(fraction) {
  return ((START - fraction * SWEEP) * Math.PI) / 180
}
function point(angle, radius, dx = 0, dy = 0) {
  return {
    x: CX + radius * Math.cos(angle) + dx,
    y: CY - radius * Math.sin(angle) + dy,
  }
}
// Where the min and max labels sit, just below the ends of the arc
const ENDS = {
  min: point(angle(0), RADIUS, 0, 16),
  max: point(angle(1), RADIUS, 0, 16),
}

// One value on a dial with red, yellow, green (and blue for operational
// limits) zones, like the limits bar bent into an arc. Zones come from the
// item's limits, or from the panel's own RED_LOW..RED_HIGH with LIMITS
// CUSTOM. The scale is MIN..MAX when set, otherwise the limits plus 10% of
// their range on each side.
export default {
  components: { PacketTime },
  mixins: [tlmPanel],
  ENDS,
  computed: {
    custom() {
      return option(this.panel, 'LIMITS') === 'CUSTOM'
    },
    // Custom limits in the shape get_item returns, null until all four are set
    limits() {
      if (!this.custom) return this.first.limits || null
      const limits = {
        red_low: option(this.panel, 'RED_LOW'),
        yellow_low: option(this.panel, 'YELLOW_LOW'),
        yellow_high: option(this.panel, 'YELLOW_HIGH'),
        red_high: option(this.panel, 'RED_HIGH'),
      }
      return Object.values(limits).includes(null) ? null : limits
    },
    scale() {
      const padded = paddedScale(this.limits)
      const min = option(this.panel, 'MIN') ?? padded?.min ?? null
      const max = option(this.panel, 'MAX') ?? padded?.max ?? null
      if (min === null || max === null || !(max > min)) return null
      return { min, max }
    },
    zones() {
      if (!this.scale) return []
      const { min, max } = this.scale
      return limitZones(this.limits, min, max)
        .map(({ level, from, to }) => ({
          level,
          from: this.fraction(from),
          to: this.fraction(to),
        }))
        .filter((zone) => zone.to > zone.from)
    },
    marker() {
      if (!this.scale || typeof this.first.number !== 'number') return null
      const at = angle(this.fraction(this.first.number))
      const inner = point(at, RADIUS - 14)
      const outer = point(at, RADIUS + 9)
      return { x1: inner.x, y1: inner.y, x2: outer.x, y2: outer.y }
    },
    // Item limits use the limits state COSMOS reports; custom limits are
    // checked here
    level() {
      if (!this.custom) return this.first.level
      if (this.first.stale) return 'off'
      return levelOf(this.first.number, this.limits)
    },
    panelLevel() {
      return this.level
    },
  },
  methods: {
    // Position of a value along the arc, 0 to 1
    fraction(value) {
      const { min, max } = this.scale
      return Math.min(1, Math.max(0, (value - min) / (max - min)))
    },
    arc(from, to) {
      const start = point(angle(from), RADIUS)
      const end = point(angle(to), RADIUS)
      const large = (to - from) * SWEEP > 180 ? 1 : 0
      return `M${start.x} ${start.y}A${RADIUS} ${RADIUS} 0 ${large} 1 ${end.x} ${end.y}`
    },
    compact(value) {
      return Number(value.toPrecision(4)).toString()
    },
  },
}
</script>

<style scoped>
.track,
.zone {
  fill: none;
  stroke-width: 12;
}
.track {
  stroke: var(--track-color);
}
/* Zone colors (--zone) come from dashboards.scss */
.zone {
  stroke: var(--zone);
}
.marker {
  stroke: rgb(var(--v-theme-on-surface));
  stroke-width: 4;
  stroke-linecap: round;
}
.m-critical {
  stroke: var(--color-status-critical);
}
.m-caution {
  stroke: var(--color-status-caution);
}
.value {
  font-size: 30px;
  font-weight: 500;
  fill: rgb(var(--v-theme-on-surface));
}
.value.stale {
  fill: rgba(var(--v-theme-on-surface), var(--v-disabled-opacity));
}
.units,
.end {
  font-size: 12px;
  fill: rgba(var(--v-theme-on-surface), var(--v-medium-emphasis-opacity));
}
</style>
