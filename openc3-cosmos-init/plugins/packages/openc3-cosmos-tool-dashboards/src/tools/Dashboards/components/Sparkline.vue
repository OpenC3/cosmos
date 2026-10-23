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
    @mousemove="move"
    @mouseleave="leave"
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
      v-if="area && path"
      :d="areaPath"
      :fill="color"
      fill-opacity="0.18"
      class="spark-area"
    />
    <path
      :d="path"
      fill="none"
      :stroke="color"
      stroke-width="1.5"
      stroke-linejoin="round"
      vector-effect="non-scaling-stroke"
    />
    <!-- The hovered time: a crosshair, and a dot on the nearest point (a
         zero-length round-capped line stays round when the svg stretches) -->
    <template v-if="marker">
      <line
        :x1="marker.x"
        :x2="marker.x"
        y1="0"
        y2="30"
        class="crosshair"
        stroke-width="1"
        vector-effect="non-scaling-stroke"
      />
      <line
        v-if="marker.y !== null"
        :x1="marker.x"
        :x2="marker.x"
        :y1="marker.y"
        :y2="marker.y"
        :stroke="color"
        stroke-width="7"
        stroke-linecap="round"
        vector-effect="non-scaling-stroke"
      />
    </template>
  </svg>
</template>

<script>
import { limitLines } from '../limits'

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
    // Also fill under the line (Grafana's area graph mode)
    area: { type: Boolean, default: false },
    // A time in `window` to mark, e.g. hovered on another graph
    hoverTime: { type: Number, default: null },
  },
  // hover: the time under the mouse, in `window` units, or null on leave
  emits: ['hover'],
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
    // The line closed down to the bottom edge
    areaPath() {
      const first = this.samples[0][0].toFixed(1)
      const last = this.samples.at(-1)[0].toFixed(1)
      return `${this.path}L${last} 30L${first} 30Z`
    },
    // The crosshair sits exactly at the hovered time, like the graphs'; the
    // dot is on the nearest real point (not a thinned one, which jumps
    // between a slot's low and high)
    marker() {
      const [start, end] = this.window || []
      if (this.hoverTime === null || !(end > start)) return null
      const x = ((this.hoverTime - start) / (end - start)) * 100
      if (x < 0 || x > 100) return null
      const value = this.valueAt(this.hoverTime)
      return {
        x: x.toFixed(2),
        y: value !== null && this.range ? this.y(value).toFixed(2) : null,
      }
    },
    lines() {
      if (!this.range) return []
      const { min, span } = this.range
      return limitLines(this.limits)
        .filter(({ value }) => value >= min && value <= min + span)
        .map(({ key, level, value }) => ({
          key,
          y: this.y(value),
          color: `var(--color-status-${level})`,
        }))
    },
  },
  unmounted() {
    cancelAnimationFrame(this.frame)
  },
  methods: {
    // Once per frame at most, so a fast mouse doesn't redraw every graph on
    // the dashboard for each move event
    move(event) {
      const [start, end] = this.window || []
      if (!(end > start)) return
      const box = event.currentTarget.getBoundingClientRect()
      const fraction = (event.clientX - box.left) / box.width
      this.pending = start + fraction * (end - start)
      this.frame ??= requestAnimationFrame(() => {
        this.frame = null
        this.$emit('hover', this.pending)
      })
    },
    leave() {
      cancelAnimationFrame(this.frame)
      this.frame = null
      this.$emit('hover', null)
    },
    // The value of the point nearest `time`; the newest past the end
    valueAt(time) {
      const times = this.times
      const points = this.points
      if (!times?.length || time < times[0]) return null
      let low = 0
      let high = times.length - 1
      if (time >= times[high]) low = high
      while (high - low > 1) {
        const mid = (low + high) >> 1
        if (times[mid] < time) low = mid
        else high = mid
      }
      const index = time - times[low] <= times[high] - time ? low : high
      return typeof points[index] === 'number' ? points[index] : null
    },
    y(value) {
      const { min, span } = this.range
      return BOTTOM - ((value - min) / span) * (BOTTOM - TOP)
    },
  },
}
</script>

<style scoped>
.crosshair {
  stroke: rgba(var(--v-theme-on-surface), 0.5);
}
</style>
