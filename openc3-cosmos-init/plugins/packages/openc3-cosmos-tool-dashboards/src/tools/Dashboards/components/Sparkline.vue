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
    <!-- The hovered time: dashed crosshairs like the graphs' (the
         horizontal one only under the mouse), and a dot on the nearest point
         (a zero-length round-capped line stays round when the svg stretches) -->
    <template v-if="marker">
      <line
        :x1="marker.x"
        :x2="marker.x"
        y1="0"
        y2="30"
        class="crosshair"
        stroke-width="1"
        stroke-dasharray="4 4"
        vector-effect="non-scaling-stroke"
      />
      <line
        v-if="pointer"
        x1="0"
        x2="100"
        :y1="pointer.y"
        :y2="pointer.y"
        class="crosshair"
        stroke-width="1"
        stroke-dasharray="4 4"
        vector-effect="non-scaling-stroke"
      />
      <line
        v-if="marker.y !== null"
        :x1="marker.x"
        :x2="marker.x"
        :y1="marker.y"
        :y2="marker.y"
        :stroke="color"
        stroke-width="8"
        stroke-linecap="round"
        vector-effect="non-scaling-stroke"
      />
    </template>
  </svg>
</template>

<script setup>
import { computed, onUnmounted, ref } from 'vue'
import { limitLines } from '../limits'
import { hoverReach, nearestValue } from '../panels/tlmSeries'

const TOP = 3
const BOTTOM = 27
// Long histories are thinned to the low and high of this many slots
const MAX_BUCKETS = 150

// Small line chart. With `limits` it also draws the yellow and red limits as
// dashed lines; the scale always includes the yellow limits so the lines show
// where the value sits relative to them.
const props = defineProps({
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
  // Bump when points / times change in place, to redraw without passing
  // new arrays
  version: { type: Number, default: 0 },
})
// hover: the time under the mouse, in `window` units, or null on leave
const emit = defineEmits(['hover'])

let frame = null
let pending = null
// Where the mouse is while it's over the sparkline: across (0 to 1) and
// its height in the viewBox. Like uPlot's cursor, the crosshair stays with
// the mouse as the window scrolls, rather than with a time.
const pointer = ref(null)

// One pass over the points, widened to include the yellow limits
const range = computed(() => {
  void props.version
  let min = Infinity
  let max = -Infinity
  for (const v of props.points) {
    if (typeof v !== 'number') continue
    if (v < min) min = v
    if (v > max) max = v
  }
  if (props.limits) {
    min = Math.min(min, props.limits.yellow_low)
    max = Math.max(max, props.limits.yellow_high)
  }
  if (min === Infinity) return null
  return { min, span: max - min || 1 }
})
// [x from 0 to 100, value] to draw. Thinned slots keep their low and
// high, so spikes still show.
const samples = computed(() => {
  void props.version
  const points = props.points
  const n = points.length
  const [start, end] = props.window || []
  const x =
    props.times && end > start
      ? (i) => ((props.times[i] - start) / (end - start)) * 100
      : (i) => (n > 1 ? (i / (n - 1)) * 100 : 0)
  const step = Math.max(1, Math.ceil(n / MAX_BUCKETS))
  const result = []
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
    for (const i of kept) result.push([x(i), points[i]])
  }
  return result
})
const path = computed(() => {
  if (samples.value.length < 2 || !range.value) return ''
  return (
    'M' +
    samples.value
      .map(([x, v]) => `${x.toFixed(1)} ${y(v).toFixed(1)}`)
      .join('L')
  )
})
// The line closed down to the bottom edge
const areaPath = computed(() => {
  const first = samples.value[0][0].toFixed(1)
  const last = samples.value.at(-1)[0].toFixed(1)
  return `${path.value}L${last} 30L${first} 30Z`
})
// The crosshair sits exactly at the hovered time, like the graphs'; the
// dot is on the nearest real point (not a thinned one, which jumps
// between a slot's low and high)
const marker = computed(() => {
  void props.version
  const [start, end] = props.window || []
  if (!(end > start)) return null
  const time = pointer.value
    ? start + pointer.value.fraction * (end - start)
    : props.hoverTime
  if (time === null) return null
  const x = ((time - start) / (end - start)) * 100
  if (x < 0 || x > 100) return null
  const value = nearestValue(
    props.times,
    props.points,
    time,
    hoverReach(end - start),
  )
  return {
    x: x.toFixed(2),
    y: value !== null && range.value ? y(value).toFixed(2) : null,
  }
})
const lines = computed(() => {
  if (!range.value) return []
  const { min, span } = range.value
  return limitLines(props.limits)
    .filter(({ value }) => value >= min && value <= min + span)
    .map(({ key, level, value }) => ({
      key,
      y: y(value),
      color: `var(--color-status-${level})`,
    }))
})

onUnmounted(() => {
  cancelAnimationFrame(frame)
})

// Once per frame at most, so a fast mouse doesn't redraw every graph on
// the dashboard for each move event. The crosshair moves in the same
// frame as the shared hover, so it and the panel's tooltip move together.
function move(event) {
  const [start, end] = props.window || []
  if (!(end > start)) return
  const box = event.currentTarget.getBoundingClientRect()
  const fraction = (event.clientX - box.left) / box.width
  pending = {
    fraction,
    y: ((event.clientY - box.top) / box.height) * 30,
    time: start + fraction * (end - start),
  }
  frame ??= requestAnimationFrame(() => {
    frame = null
    pointer.value = { fraction: pending.fraction, y: pending.y }
    emit('hover', pending.time)
  })
}

function leave() {
  cancelAnimationFrame(frame)
  frame = null
  pointer.value = null
  emit('hover', null)
}

// The value of the point nearest `time`; the newest past the end
function y(value) {
  const { min, span } = range.value
  return BOTTOM - ((value - min) / span) * (BOTTOM - TOP)
}
</script>

<style scoped>
/* uPlot's cursor color, so sparklines and graphs match */
.crosshair {
  stroke: #607d8b;
}
</style>
