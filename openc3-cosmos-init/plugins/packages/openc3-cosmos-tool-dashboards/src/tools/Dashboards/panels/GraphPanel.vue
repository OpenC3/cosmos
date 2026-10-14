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
  <div class="d-flex flex-column flex-grow-1" style="min-height: 0">
    <div
      class="d-flex flex-wrap align-center px-4 pt-1 text-caption text-medium-emphasis"
      style="gap: 4px 16px"
    >
      <span
        v-for="(entry, index) in legend"
        :key="entry.key"
        class="d-inline-flex align-center ga-2"
      >
        <span class="swatch" :style="{ background: colors[index] }" />
        {{ entry.label }}
        <b class="num text-high-emphasis" data-test="graph-legend-value">{{
          entry.last
        }}</b>
        {{ entry.units }}
      </span>
      <span v-if="thresholdLimits" class="d-inline-flex align-center ga-2">
        <span class="swatch-dashed" />
        {{ thresholdLabel }} limits
      </span>
    </div>
    <div
      ref="plot"
      class="plot flex-grow-1 position-relative mx-2 mb-2 mt-2"
      data-test="graph-plot"
    >
      <div
        v-if="tip"
        class="tip text-caption bg-surface-light rounded-lg border pa-2 elevation-4"
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
            <span class="swatch" :style="{ background: row.color }" />
            {{ row.label }}
          </span>
          <span class="d-inline-flex align-center ga-1">
            <status-symbol :level="row.level" />
            <b class="num">{{ row.value }}</b> {{ row.units }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import uPlot from 'uplot'
import 'uplot/dist/uPlot.min.css'
import StatusSymbol from '../components/StatusSymbol.vue'
import panelBase from './panelBase'
import tlmSeries from './tlmSeries'
import { itemLabel } from './tlmPanel'
import { option } from './options'
import { seriesColor } from './colors'
import { itemKey } from '../composables/tlmPoller'
import { clock, formatTelemetry } from '../composables/format'

function withAlpha(color, alpha) {
  const hex = color.trim().replace('#', '')
  if (/^[0-9a-f]{6}$/i.test(hex)) {
    const n = Number.parseInt(hex, 16)
    return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`
  }
  return color
}

function relativeLabel(seconds) {
  if (seconds > -1) return 'now'
  const abs = Math.abs(seconds)
  if (abs < 120) return `−${Math.round(abs)} s`
  if (abs < 7200) return `−${Math.round(abs / 60)} min`
  return `−${Math.round(abs / 3600)} h`
}

// Live time series of up to 6 items (tlmSeries backfills and streams them).
// THRESHOLDS <TGT> <PKT> <ITEM> picks the item whose limits
// are drawn as bands (defaults to the first graphed item with limits).
export default {
  components: { StatusSymbol },
  mixins: [panelBase, tlmSeries],
  data() {
    return {
      lastValues: [],
      tip: null,
    }
  },
  computed: {
    colors() {
      return this.panel.items.map((item, index) =>
        seriesColor(this.panel, item, index),
      )
    },
    labels() {
      return this.panel.items.map((item) => itemLabel(this.panel.items, item))
    },
    infos() {
      return this.panel.items.map((item) => this.itemInfo.get(item))
    },
    // The poller supplies each item's limits state, so the panel's status
    // matches what other panels show for the same item
    pollKeys() {
      return this.panel.items.map((item) => itemKey(item, 'CONVERTED'))
    },
    panelLevel() {
      return this.worstOf(this.pollKeys)
    },
    thresholdItem() {
      const chosen = option(this.panel, 'THRESHOLDS')
      if (chosen) return chosen
      return this.panel.items.find((item) => this.itemInfo.limits(item))
    },
    thresholdLimits() {
      const item = this.thresholdItem
      return item ? this.itemInfo.limits(item) : null
    },
    thresholdLabel() {
      return this.thresholdItem?.itemName
    },
    thresholdIndex() {
      const t = this.thresholdItem
      if (!t) return -1
      return this.panel.items.findIndex(
        (i) =>
          i.targetName === t.targetName &&
          i.packetName === t.packetName &&
          i.itemName === t.itemName,
      )
    },
    legend() {
      return this.panel.items.map((item, index) => ({
        key: this.streamKeys[index],
        label: this.labels[index],
        last: this.format(index, this.lastValues[index]),
        units: this.infos[index].units,
      }))
    },
  },
  watch: {
    // Fetch units, format and limits before the computeds read them
    'panel.items': {
      immediate: true,
      handler(items) {
        for (const item of items) this.itemInfo.get(item)
      },
    },
    // Series colors are fixed when the plot is built, so rebuild it, unless
    // restart() already did for the same change
    colors(colors) {
      if (JSON.stringify(colors) !== JSON.stringify(this.plotColors)) {
        this.createPlot()
      }
    },
  },
  mounted() {
    this.resizeObserver = new ResizeObserver(() => this.resize())
    this.resizeObserver.observe(this.$refs.plot)
  },
  unmounted() {
    this.resizeObserver?.disconnect()
    this.plot?.destroy()
  },
  methods: {
    // Canvas drawing needs concrete colors, so read the theme once
    resolveColors() {
      const style = getComputedStyle(this.$el)
      // Vuetify theme variables are bare "r,g,b" triples
      const onSurface =
        style.getPropertyValue('--v-theme-on-surface').trim() || '255,255,255'
      const theme = (alpha) => `rgba(${onSurface}, ${alpha})`
      this.palette = {
        axis: theme(0.55),
        grid: theme(0.08),
        critical:
          style.getPropertyValue('--color-status-critical').trim() || '#ff3838',
        caution:
          style.getPropertyValue('--color-status-caution').trim() || '#fce83a',
        label: theme(0.7),
      }
    },
    // tlmSeries hooks: a new plot when the series start over, new data
    // about once a second
    seriesReset() {
      this.lastValues = [...this.latest]
      this.createPlot()
    },
    seriesUpdated() {
      // Only touch the legend when a newest value changed
      if (this.latest.some((value, i) => value !== this.lastValues[i])) {
        this.lastValues = [...this.latest]
      }
      this.plot?.setData(this.series)
    },
    resize() {
      const el = this.$refs.plot
      if (!el || !this.plot) return
      this.plot.setSize({
        width: el.clientWidth,
        height: Math.max(60, el.clientHeight),
      })
    },
    createPlot() {
      // The theme is read once the panel is in the page
      if (!this.palette) this.resolveColors()
      this.plotColors = [...this.colors]
      this.plot?.destroy()
      this.tip = null
      const el = this.$refs.plot
      if (!el) return
      const font = "11px 'IBM Plex Sans', system-ui, sans-serif"
      const axis = {
        stroke: this.palette.axis,
        font,
        grid: { stroke: this.palette.grid, width: 1 },
        ticks: { show: false },
      }
      this.plot = new uPlot(
        {
          width: el.clientWidth,
          height: Math.max(60, el.clientHeight),
          legend: { show: false },
          cursor: { drag: { x: false, y: false }, points: { size: 8 } },
          scales: {
            x: {
              time: false,
              range: () => [this.now - this.duration, this.now],
            },
          },
          axes: [
            {
              ...axis,
              space: 70,
              values: (u, splits) =>
                splits.map((s) => relativeLabel(s - this.now)),
            },
            { ...axis, size: 48 },
          ],
          series: [
            {},
            ...this.panel.items.map((item, index) => ({
              label: this.labels[index],
              stroke: this.colors[index],
              width: 2,
              spanGaps: true,
              points: { show: false },
            })),
          ],
          hooks: {
            drawAxes: [(u) => this.drawBands(u)],
            draw: [(u) => this.drawThresholds(u)],
            setCursor: [(u) => this.updateTip(u)],
          },
        },
        this.series,
        el,
      )
    },
    // Shaded limits bands behind the series
    drawBands(u) {
      const l = this.thresholdLimits
      if (!l) return
      const { ctx, bbox } = u
      const y = (value) => u.valToPos(value, 'y', true)
      const band = (from, to, color, alpha) => {
        const top = Math.max(bbox.top, Math.min(y(from), y(to)))
        const bottom = Math.min(
          bbox.top + bbox.height,
          Math.max(y(from), y(to)),
        )
        if (bottom <= top) return
        ctx.fillStyle = withAlpha(color, alpha)
        ctx.fillRect(bbox.left, top, bbox.width, bottom - top)
      }
      const max = u.scales.y.max
      const min = u.scales.y.min
      ctx.save()
      if (max > l.red_high) band(l.red_high, max, this.palette.critical, 0.09)
      if (max > l.yellow_high)
        band(
          l.yellow_high,
          Math.min(max, l.red_high),
          this.palette.caution,
          0.06,
        )
      if (min < l.yellow_low)
        band(Math.max(min, l.red_low), l.yellow_low, this.palette.caution, 0.06)
      if (min < l.red_low) band(min, l.red_low, this.palette.critical, 0.09)
      ctx.restore()
    },
    // Dashed threshold lines with labels on top of the series
    drawThresholds(u) {
      const { ctx, bbox } = u
      const ratio = window.devicePixelRatio || 1
      ctx.save()
      ctx.setLineDash([4 * ratio, 4 * ratio])
      ctx.lineWidth = ratio
      ctx.font = `600 ${10 * ratio}px 'IBM Plex Sans', system-ui, sans-serif`
      ctx.textAlign = 'right'
      const l = this.thresholdLimits
      const lines = l
        ? [
            ['critical', 'RED HIGH', l.red_high],
            ['caution', 'YELLOW HIGH', l.yellow_high],
            ['caution', 'YELLOW LOW', l.yellow_low],
            ['critical', 'RED LOW', l.red_low],
          ]
        : []
      for (const [level, name, value] of lines) {
        if (value < u.scales.y.min || value > u.scales.y.max) continue
        const pos = Math.round(u.valToPos(value, 'y', true)) + 0.5
        ctx.strokeStyle = this.palette[level]
        ctx.beginPath()
        ctx.moveTo(bbox.left, pos)
        ctx.lineTo(bbox.left + bbox.width, pos)
        ctx.stroke()
        ctx.fillStyle = this.palette.label
        ctx.fillText(
          `${name} ${value}`,
          bbox.left + bbox.width - 4 * ratio,
          pos - 4 * ratio,
        )
      }
      ctx.restore()
    },
    updateTip(u) {
      const { left, idx } = u.cursor
      if (idx === null || idx === undefined || left === undefined || left < 0) {
        this.tip = null
        return
      }
      this.tip = {
        left: left + u.over.offsetLeft,
        flip: left > u.over.clientWidth * 0.62,
        time: clock(this.series[0][idx] * 1000, this.timeZone),
        rows: this.panel.items.map((item, index) => {
          const value = this.series[index + 1][idx]
          return {
            label: this.labels[index],
            color: this.colors[index],
            value: this.format(index, value),
            units: this.infos[index].units,
            level: index === this.thresholdIndex ? this.levelOf(value) : null,
          }
        }),
      }
    },
    // Status of a past point for the tooltip; the live status comes from the
    // server's limits state (panelLevel)
    levelOf(value) {
      const l = this.thresholdLimits
      if (!l || typeof value !== 'number') return null
      if (value > l.red_high || value < l.red_low) return 'critical'
      if (value > l.yellow_high || value < l.yellow_low) return 'caution'
      return 'normal'
    },
    // With the item's format string, else a compact number
    format(index, value) {
      if (typeof value !== 'number') return '--'
      const formatString = this.infos[index]?.formatString
      if (formatString) return formatTelemetry(value, formatString)
      return Math.abs(value) >= 1000
        ? value.toFixed(0)
        : value.toPrecision(4).replace(/\.?0+$/, '')
    },
  },
}
</script>

<style scoped>
.plot {
  min-height: 0;
}
.swatch {
  width: 14px;
  height: 2px;
  border-radius: 1px;
  display: inline-block;
}
.swatch-dashed {
  width: 14px;
  border-top: 1px dashed var(--color-status-caution);
  display: inline-block;
}
.tip {
  position: absolute;
  top: 4px;
  min-width: 160px;
  pointer-events: none;
  z-index: 2;
}
</style>
