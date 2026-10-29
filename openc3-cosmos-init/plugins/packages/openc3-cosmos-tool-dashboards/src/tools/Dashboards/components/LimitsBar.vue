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
  <span
    v-if="zones.length"
    class="limits-bar position-relative d-block"
    aria-hidden="true"
  >
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

<script setup>
import { computed } from 'vue'
import { limitZones, paddedScale } from '../limits'

// Thin limits bar from the style system: red, yellow, green (and blue for
// operational limits) zones with a
// marker at the current value. The scale extends 10% of the yellow range past
// the red limits on each side, like the COSMOS LimitsBar widget. Parents set
// --limits-bar-track to change the track thickness.
const props = defineProps({
  limits: { type: Object, default: null },
  value: { type: Number, default: null },
})

const scale = computed(() => paddedScale(props.limits))
const zones = computed(() => {
  if (!scale.value) return []
  const { min, max } = scale.value
  return limitZones(props.limits, min, max).map(({ level, from, to }) => ({
    level,
    left: percent(from),
    width: percent(to) - percent(from),
  }))
})
const marker = computed(() => {
  if (!scale.value || typeof props.value !== 'number') return null
  return Math.min(100, Math.max(0, percent(props.value)))
})

function percent(value) {
  return ((value - scale.value.min) / (scale.value.max - scale.value.min)) * 100
}
</script>

<style scoped>
.limits-bar {
  height: calc(var(--limits-bar-track, 6px) + 6px);
}
.track {
  position: absolute;
  inset: 3px 0;
  border-radius: 3px;
  overflow: hidden;
  background: var(--track-color);
}
/* Zone colors (--zone) come from dashboards.scss */
.zone {
  position: absolute;
  top: 0;
  bottom: 0;
  background: var(--zone);
}
.marker {
  position: absolute;
  top: 0;
  bottom: 0;
  width: 2px;
  border-radius: 1px;
  background: rgb(var(--v-theme-on-surface));
  transform: translateX(-1px);
  transition: left 0.4s;
}
</style>
