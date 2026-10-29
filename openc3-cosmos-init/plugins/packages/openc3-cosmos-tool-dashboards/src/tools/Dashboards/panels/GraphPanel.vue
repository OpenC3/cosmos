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
  <div class="d-flex flex-column flex-grow-1 min-h-0">
    <div
      class="d-flex flex-wrap align-center px-4 pt-1 text-caption text-medium-emphasis"
      style="gap: 4px 16px"
    >
      <span
        v-for="(entry, index) in legend"
        :key="entry.key"
        class="d-inline-flex align-center ga-2"
      >
        <span class="db-swatch" :style="{ background: colors[index] }" />
        {{ entry.label }}
        <b class="num text-high-emphasis" data-test="graph-legend-value">{{
          entry.last
        }}</b>
        {{ entry.units }}
      </span>
      <span v-if="thresholdLimits" class="d-inline-flex align-center ga-2">
        <span class="swatch-dashed d-inline-block" />
        {{ thresholdLabel }} limits
      </span>
    </div>
    <div
      ref="plotBox"
      class="flex-grow-1 min-h-0 position-relative mx-2 mb-2 mt-2"
      data-test="graph-plot"
    >
      <div
        v-if="tip"
        class="db-tip position-absolute pointer-events-none text-caption bg-surface-light rounded-lg border pa-2 elevation-4"
        :style="{
          left: `${tip.left}px`,
          transform: tip.flip
            ? 'translateX(calc(-100% - 12px))'
            : 'translateX(12px)',
        }"
      >
        <div class="num font-weight-bold mb-1">{{ tip.time }}</div>
        <div
          v-for="row in tip.rows"
          :key="row.label"
          class="d-flex align-center justify-space-between ga-3"
        >
          <span class="d-inline-flex align-center ga-2 text-medium-emphasis">
            <span class="db-swatch" :style="{ background: row.color }" />
            {{ row.label }}
          </span>
          <span>
            <b class="num">{{ row.value }}</b> {{ row.units }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import {
  computed,
  onMounted,
  onUnmounted,
  ref,
  useTemplateRef,
  watch,
} from 'vue'
import { useTheme } from 'vuetify'
import uPlot from 'uplot'
import 'uplot/dist/uPlot.min.css'
import { panelProps, usePanel } from './panelBase'
import { useTlmSeries } from './tlmSeries'
import { itemLabels, pollType } from './tlmPanel'
import { option } from './options'
import { seriesColor } from './colors'
import { itemKey } from '../composables/tlmPoller'
import { clock, formatTelemetry } from '../composables/format'
import { limitLines } from '../limits'
import { equal } from '../composables/equal'

function withAlpha(color, alpha) {
  const hex = color.trim().replace('#', '')
  if (/^[0-9a-f]{6}$/i.test(hex)) {
    const n = Number.parseInt(hex, 16)
    return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`
  }
  return color
}

// Live time series of up to 6 items (useTlmSeries backfills and streams
// them). THRESHOLDS <TGT> <PKT> <ITEM> picks the item whose limits
// are drawn as bands (defaults to the first graphed item with limits).
// Hovering shares the time with the dashboard's other graphs and
// sparklines (useTlmSeries setHover), and follows theirs.
const props = defineProps(panelProps)
const panel = usePanel(props, {
  pollKeys: () => pollKeys.value,
  panelLevel: () => panel.worstOf(pollKeys.value),
})
const { itemInfo, timeZone } = panel
const { hover, now, duration, series, latest, setHover } = useTlmSeries(
  props,
  panel,
  {
    // A new plot when the series start over, new data about once a second
    seriesReset: () => {
      lastValues.value = [...latest]
      createPlot()
    },
    seriesUpdated: () => {
      // Only touch the legend when a newest value changed
      if (latest.some((value, i) => value !== lastValues.value[i])) {
        lastValues.value = [...latest]
      }
      plot?.setData(series)
      // The plot scrolled, so put a followed cursor back on its time
      if (hover.time !== null) followHover()
    },
  },
)
const theme = useTheme()
const plotEl = useTemplateRef('plotBox')

const lastValues = ref([])
const tip = ref(null)

// uPlot and its drawing state; none of it is rendered by Vue
let plot = null
let plotColors = null
let palette = null
let hovering = false
let following = false
let hoverFrame = null
let pendingHover = null
let resizeObserver = null

const colors = computed(() =>
  props.panel.items.map((item, index) => seriesColor(props.panel, item, index)),
)
const labels = computed(() => itemLabels(props.panel.items))
const infos = computed(() =>
  props.panel.items.map((item) => itemInfo.get(item)),
)
// The poller supplies each item's limits state, so the panel's status
// matches what other panels show for the same item
const pollKeys = computed(() =>
  props.panel.items.map((item) => itemKey(item, 'CONVERTED')),
)
const thresholdItem = computed(() => {
  const chosen = option(props.panel, 'THRESHOLDS')
  if (chosen) return chosen
  return props.panel.items.find((item) => itemInfo.limits(item))
})
const thresholdLimits = computed(() => {
  const item = thresholdItem.value
  return item ? itemInfo.limits(item) : null
})
const thresholdLabel = computed(() => thresholdItem.value?.itemName)
const legend = computed(() =>
  props.panel.items.map((item, index) => ({
    key: `DECOM__TLM__${itemKey(item, pollType(item))}`,
    label: labels.value[index],
    last: format(index, lastValues.value[index]),
    units: infos.value[index].units,
  })),
)

// Watched because uPlot fixes series colors when the plot is built, so it
// is rebuilt, unless restart() already did for the same change
watch(colors, (value) => {
  if (!equal(value, plotColors)) createPlot()
})
// Watched to move uPlot's cursor and tooltip to another panel's hover
// time, or hide them; the hover is shared state with no event to hook
watch(
  () => hover.time,
  () => followHover(),
)
// Watched because axis, grid and threshold colors are baked into the
// canvas, so a light or dark theme switch needs them read again once the
// page restyles
watch(
  () => theme.global.name.value,
  () => {
    palette = null
    createPlot()
  },
  { flush: 'post' },
)

onMounted(() => {
  resizeObserver = new ResizeObserver(() => resize())
  resizeObserver.observe(plotEl.value)
})
onUnmounted(() => {
  cancelAnimationFrame(hoverFrame)
  resizeObserver?.disconnect()
  plot?.destroy()
})

// Canvas drawing needs concrete colors, so read them from the theme
function resolveColors() {
  const style = getComputedStyle(plotEl.value)
  // Vuetify theme variables are bare "r,g,b" triples
  const onSurface =
    style.getPropertyValue('--v-theme-on-surface').trim() || '255,255,255'
  const themed = (alpha) => `rgba(${onSurface}, ${alpha})`
  palette = {
    axis: themed(0.55),
    grid: themed(0.08),
    critical:
      style.getPropertyValue('--color-status-critical').trim() || '#ff3838',
    caution:
      style.getPropertyValue('--color-status-caution').trim() || '#fce83a',
    label: themed(0.7),
  }
}
function followHover() {
  const u = plot
  if (!u || hovering) return
  const time = hover.time
  const left = time === null ? -10 : u.valToPos(time, 'x')
  const inside = left >= 0 && left <= u.over.clientWidth
  following = true
  u.setCursor({
    left: inside ? left : -10,
    top: inside ? u.over.clientHeight / 2 : -10,
  })
  following = false
}
function resize() {
  const el = plotEl.value
  if (!el || !plot) return
  plot.setSize({
    width: el.clientWidth,
    height: Math.max(60, el.clientHeight),
  })
}
function createPlot() {
  const el = plotEl.value
  // The theme is read once the panel is in the page
  if (!palette && el) resolveColors()
  plotColors = [...colors.value]
  plot?.destroy()
  plot = null
  tip.value = null
  if (!el) return
  const font = "11px 'IBM Plex Sans', system-ui, sans-serif"
  const axis = {
    stroke: palette.axis,
    font,
    grid: { stroke: palette.grid, width: 1 },
    ticks: { show: false },
  }
  plot = new uPlot(
    {
      width: el.clientWidth,
      height: Math.max(60, el.clientHeight),
      legend: { show: false },
      cursor: {
        drag: { x: false, y: false },
        points: { size: 8 },
        // Each series' own nearest point, since items from different
        // packets rarely share a timestamp
        dataIdx: (u, seriesIdx, closestIdx) =>
          nearestIdx(u, seriesIdx, closestIdx),
      },
      scales: {
        x: {
          time: false,
          range: () => [now.value - duration.value, now.value],
        },
      },
      axes: [
        {
          ...axis,
          space: 70,
          values: (u, splits) => splits.map((s) => axisLabel(s)),
        },
        { ...axis, size: 48 },
      ],
      series: [
        {},
        ...props.panel.items.map((item, index) => ({
          label: labels.value[index],
          stroke: colors.value[index],
          width: 2,
          spanGaps: true,
          points: { show: false },
        })),
      ],
      hooks: {
        drawAxes: [(u) => drawBands(u)],
        draw: [(u) => drawThresholds(u)],
        setCursor: [(u) => updateTip(u)],
      },
    },
    series,
    el,
  )
  // Only the plot under the mouse shares its hover. uPlot also moves the
  // cursor when data arrives, which mustn't count as hovering.
  hovering = false
  plot.over.addEventListener('mouseenter', () => {
    hovering = true
  })
  plot.over.addEventListener('mouseleave', () => {
    hovering = false
    cancelAnimationFrame(hoverFrame)
    hoverFrame = null
    setHover(null)
  })
}
// Nearest index with a value for a series, within a few seconds of the
// cursor (further off, the series shows nothing there)
function nearestIdx(u, seriesIdx, closestIdx) {
  const ys = u.data[seriesIdx]
  if (seriesIdx === 0 || ys[closestIdx] != null) return closestIdx
  const xs = u.data[0]
  const x = xs[closestIdx]
  const reach = Math.max(5, duration.value / 40)
  let best = closestIdx
  let bestGap = Infinity
  for (let i = closestIdx - 1; i >= 0 && x - xs[i] <= reach; i--) {
    if (ys[i] != null) {
      best = i
      bestGap = x - xs[i]
      break
    }
  }
  for (let i = closestIdx + 1; i < xs.length; i++) {
    const gap = xs[i] - x
    if (gap > reach || gap >= bestGap) break
    if (ys[i] != null) return i
  }
  return best
}
// Once per frame at most, so a fast mouse doesn't redraw every graph on
// the dashboard for each move event
function publishHover(time) {
  pendingHover = time
  hoverFrame ??= requestAnimationFrame(() => {
    hoverFrame = null
    if (hovering) setHover(pendingHover)
  })
}
// Shaded limits bands behind the series
function drawBands(u) {
  const l = thresholdLimits.value
  if (!l) return
  const { ctx, bbox } = u
  const y = (value) => u.valToPos(value, 'y', true)
  const band = (from, to, color, alpha) => {
    const top = Math.max(bbox.top, Math.min(y(from), y(to)))
    const bottom = Math.min(bbox.top + bbox.height, Math.max(y(from), y(to)))
    if (bottom <= top) return
    ctx.fillStyle = withAlpha(color, alpha)
    ctx.fillRect(bbox.left, top, bbox.width, bottom - top)
  }
  const max = u.scales.y.max
  const min = u.scales.y.min
  ctx.save()
  if (max > l.red_high) band(l.red_high, max, palette.critical, 0.09)
  if (max > l.yellow_high)
    band(l.yellow_high, Math.min(max, l.red_high), palette.caution, 0.06)
  if (min < l.yellow_low)
    band(Math.max(min, l.red_low), l.yellow_low, palette.caution, 0.06)
  if (min < l.red_low) band(min, l.red_low, palette.critical, 0.09)
  ctx.restore()
}
// Dashed threshold lines with labels on top of the series
function drawThresholds(u) {
  const { ctx, bbox } = u
  const ratio = window.devicePixelRatio || 1
  ctx.save()
  ctx.setLineDash([4 * ratio, 4 * ratio])
  ctx.lineWidth = ratio
  ctx.font = `600 ${10 * ratio}px 'IBM Plex Sans', system-ui, sans-serif`
  ctx.textAlign = 'right'
  for (const { level, name, value } of limitLines(thresholdLimits.value)) {
    if (value < u.scales.y.min || value > u.scales.y.max) continue
    const pos = Math.round(u.valToPos(value, 'y', true)) + 0.5
    ctx.strokeStyle = palette[level]
    ctx.beginPath()
    ctx.moveTo(bbox.left, pos)
    ctx.lineTo(bbox.left + bbox.width, pos)
    ctx.stroke()
    ctx.fillStyle = palette.label
    ctx.fillText(
      `${name} ${value}`,
      bbox.left + bbox.width - 4 * ratio,
      pos - 4 * ratio,
    )
  }
  ctx.restore()
}
// Clock time at the tick, hh:mm:ss, or hh:mm for ranges over an hour.
// The axis leaves off " UTC"; the tooltip still says it.
function axisLabel(seconds) {
  const time = clock(seconds * 1000, timeZone.value).replace(' UTC', '')
  return duration.value > 3600 ? time.slice(0, 5) : time
}
function updateTip(u) {
  const { left, idx, idxs } = u.cursor
  const off =
    idx === null || idx === undefined || left === undefined || left < 0
  const time = off ? null : u.posToVal(left, 'x')
  // The mouse is on this plot: tell the others
  if (hovering && !following) publishHover(time)
  if (off) {
    tip.value = null
    return
  }
  // Flips sides past 62% across and back under 38%, so it doesn't
  // flicker from side to side around one spot
  const width = u.over.clientWidth
  const flip = tip.value?.flip ? left > width * 0.38 : left > width * 0.62
  tip.value = {
    left: left + u.over.offsetLeft,
    flip,
    // The cursor's time, not the nearest sample's, so it moves smoothly
    time: clock(time * 1000, timeZone.value),
    rows: props.panel.items.map((item, index) => {
      const rowIdx = idxs?.[index + 1] ?? idx
      const value = series[index + 1][rowIdx]
      return {
        label: labels.value[index],
        color: colors.value[index],
        value: format(index, value),
        units: infos.value[index].units,
      }
    }),
  }
}
// With the item's format string, else a compact number
function format(index, value) {
  if (typeof value !== 'number') return '--'
  const formatString = infos.value[index]?.formatString
  if (formatString) return formatTelemetry(value, formatString)
  return Math.abs(value) >= 1000
    ? value.toFixed(0)
    : value.toPrecision(4).replace(/\.?0+$/, '')
}
</script>

<style scoped>
.swatch-dashed {
  width: 14px;
  border-top: 1px dashed var(--color-status-caution);
}
</style>
