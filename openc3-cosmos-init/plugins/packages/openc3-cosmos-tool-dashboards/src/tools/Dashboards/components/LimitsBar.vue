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
  <span v-if="zones.length" class="limits-bar" aria-hidden="true">
    <span class="track">
      <span
        v-for="(zone, index) in zones"
        :key="index"
        :class="['zone', `z-${zone.level}`]"
        :style="{ left: `${zone.left}%`, width: `${zone.width}%` }"
      />
    </span>
    <span
      v-if="marker !== null"
      class="marker"
      :style="{ left: `${marker}%` }"
    />
  </span>
</template>

<script>
// Thin limits bar from the style system: red, yellow, green (and blue for
// operational limits) zones with a
// marker at the current value. The scale extends 10% of the yellow range past
// the red limits on each side, like the COSMOS LimitsBar widget.
export default {
  props: {
    limits: { type: Object, default: null },
    value: { type: Number, default: null },
  },
  computed: {
    scale() {
      const l = this.limits
      if (!l || l.red_low === undefined || l.red_high === undefined) return null
      const pad = Math.max((l.red_high - l.red_low) * 0.1, Number.EPSILON)
      return { min: l.red_low - pad, max: l.red_high + pad }
    },
    zones() {
      if (!this.scale) return []
      const l = this.limits
      const stops = [
        ['critical', this.scale.min, l.red_low],
        ['caution', l.red_low, l.yellow_low],
        ['normal', l.yellow_low, l.yellow_high],
        ['caution', l.yellow_high, l.red_high],
        ['critical', l.red_high, this.scale.max],
      ]
      // Operational limits: the inner green_low..green_high range is BLUE
      if (l.green_low !== undefined && l.green_high !== undefined) {
        stops.push(['standby', l.green_low, l.green_high])
      }
      return stops.map(([level, from, to]) => ({
        level,
        left: this.percent(from),
        width: this.percent(to) - this.percent(from),
      }))
    },
    marker() {
      if (!this.scale || typeof this.value !== 'number') return null
      return Math.min(100, Math.max(0, this.percent(this.value)))
    },
  },
  methods: {
    percent(value) {
      return (
        ((value - this.scale.min) / (this.scale.max - this.scale.min)) * 100
      )
    },
  },
}
</script>

<style scoped>
.limits-bar {
  position: relative;
  display: block;
  height: 12px;
}
.track {
  position: absolute;
  inset: 3px 0;
  border-radius: 3px;
  overflow: hidden;
  background: rgba(var(--v-border-color), var(--v-border-opacity));
}
.zone {
  position: absolute;
  top: 0;
  bottom: 0;
}
.z-critical {
  background: color-mix(in srgb, var(--color-status-critical) 55%, transparent);
}
.z-caution {
  background: color-mix(in srgb, var(--color-status-caution) 45%, transparent);
}
.z-standby {
  background: color-mix(in srgb, var(--color-status-standby) 35%, transparent);
}
.z-normal {
  background: color-mix(in srgb, var(--color-status-normal) 22%, transparent);
}
.marker {
  position: absolute;
  top: 0;
  width: 2px;
  height: 12px;
  border-radius: 1px;
  background: rgb(var(--v-theme-on-surface));
  transform: translateX(-1px);
  transition: left 0.4s;
}
</style>
