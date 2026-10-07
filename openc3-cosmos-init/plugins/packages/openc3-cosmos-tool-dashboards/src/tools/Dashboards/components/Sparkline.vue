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

// Small line chart. With `limits` it also draws the yellow and red limits as
// dashed lines; the scale always includes the yellow limits so the lines show
// where the value sits relative to them.
export default {
  props: {
    // Array of numbers, oldest first
    points: { type: Array, default: () => [] },
    color: { type: String, default: 'rgb(var(--v-theme-secondary))' },
    // { red_low, yellow_low, yellow_high, red_high } or null
    limits: { type: Object, default: null },
  },
  computed: {
    values() {
      return this.points.filter((v) => typeof v === 'number')
    },
    // One pass over the points, widened to include the yellow limits
    range() {
      let min = Infinity
      let max = -Infinity
      for (const v of this.values) {
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
    path() {
      const values = this.values
      if (values.length < 2 || !this.range) return ''
      return (
        'M' +
        values
          .map((v, i) => {
            const x = (i / (values.length - 1)) * 100
            return `${x.toFixed(1)} ${this.y(v).toFixed(1)}`
          })
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
