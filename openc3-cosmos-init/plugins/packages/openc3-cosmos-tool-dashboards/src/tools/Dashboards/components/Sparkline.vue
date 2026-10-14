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
  <svg
    viewBox="0 0 100 30"
    preserveAspectRatio="none"
    aria-hidden="true"
    class="d-block w-100"
  >
    <line
      v-for="line in lines"
      :key="line.key"
      x1="0"
      x2="100"
      :y1="line.y"
      :y2="line.y"
      :stroke="line.color"
      stroke-width="1"
      stroke-dasharray="3 3"
      vector-effect="non-scaling-stroke"
      data-test="sparkline-limit"
    />
    <path
      :d="path"
      fill="none"
      :stroke="color"
      stroke-width="1.5"
      stroke-linejoin="round"
      vector-effect="non-scaling-stroke"
    />
  </svg>
</template>

<script>
const TOP = 3
const BOTTOM = 27
// Long histories are thinned to the low and high of this many slots
const MAX_BUCKETS = 150

// Small line chart. With `limits` it also draws the yellow and red limits as
// dashed lines; the scale always includes the yellow limits so the lines show
// where the value sits relative to them.
export default {
  props: {
    // Array of numbers, oldest first
    points: { type: Array, default: () => [] },
    // With `window` ([start, end]): the time of each point, in the same
    // units, to place them by time rather than evenly
    times: { type: Array, default: null },
    window: { type: Array, default: null },
    color: { type: String, default: 'rgb(var(--v-theme-secondary))' },
    // { red_low, yellow_low, yellow_high, red_high } or null
    limits: { type: Object, default: null },
  },
  computed: {
    // One pass over the points, widened to include the yellow limits
    range() {
      let min = Infinity
      let max = -Infinity
      for (const v of this.points) {
        if (typeof v !== 'number') continue
        if (v < min) min = v
        if (v > max) max = v
      }
      if (this.limits) {
        min = Math.min(min, this.limits.yellow_low)
        max = Math.max(max, this.limits.yellow_high)
      }
      if (min === Infinity) return null
      return { min, span: max - min || 1 }
    },
    // [x from 0 to 100, value] to draw. Thinned slots keep their low and
    // high, so spikes still show.
    samples() {
      const points = this.points
      const n = points.length
      const [start, end] = this.window || []
      const x =
        this.times && end > start
          ? (i) => ((this.times[i] - start) / (end - start)) * 100
          : (i) => (n > 1 ? (i / (n - 1)) * 100 : 0)
      const step = Math.max(1, Math.ceil(n / MAX_BUCKETS))
      const samples = []
      for (let from = 0; from < n; from += step) {
        let low = -1
        let high = -1
        for (let i = from; i < Math.min(n, from + step); i++) {
          if (typeof points[i] !== 'number') continue
          if (low < 0 || points[i] < points[low]) low = i
          if (high < 0 || points[i] > points[high]) high = i
        }
        if (low < 0) continue
        const kept = low === high ? [low] : [low, high].sort((a, b) => a - b)
        for (const i of kept) samples.push([x(i), points[i]])
      }
      return samples
    },
    path() {
      if (this.samples.length < 2 || !this.range) return ''
      return (
        'M' +
        this.samples
          .map(([x, v]) => `${x.toFixed(1)} ${this.y(v).toFixed(1)}`)
          .join('L')
      )
    },
    lines() {
      const l = this.limits
      if (!l || !this.range) return []
      const { min, span } = this.range
      return [
        ['rh', l.red_high, 'var(--color-status-critical)'],
        ['yh', l.yellow_high, 'var(--color-status-caution)'],
        ['yl', l.yellow_low, 'var(--color-status-caution)'],
        ['rl', l.red_low, 'var(--color-status-critical)'],
      ]
        .filter(([, value]) => value >= min && value <= min + span)
        .map(([key, value, color]) => ({ key, y: this.y(value), color }))
    },
  },
  methods: {
    y(value) {
      const { min, span } = this.range
      return BOTTOM - ((value - min) / span) * (BOTTOM - TOP)
    },
  },
}
</script>
