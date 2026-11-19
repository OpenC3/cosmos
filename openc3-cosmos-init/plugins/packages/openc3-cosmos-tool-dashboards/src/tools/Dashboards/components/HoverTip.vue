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
  <!-- On top of the page rather than inside the panel, so the panel's
       edges never clip it. Into the Vuetify app, not body, so the theme's
       colors still apply. -->
  <teleport :to="target">
    <div
      v-if="visible"
      ref="tip"
      :class="[
        'hover-tip pointer-events-none text-caption text-no-wrap bg-surface-light rounded-lg border pa-2 elevation-4',
      ]"
      :style="position()"
      v-bind="$attrs"
    >
      <slot />
    </div>
  </teleport>
</template>

<script setup>
import {
  computed,
  inject,
  onMounted,
  onUnmounted,
  ref,
  unref,
  useTemplateRef,
  watch,
} from 'vue'

// A graph's hover tooltip. `anchor` is the plot's element and `x` where the
// cursor is across it, in pixels (or percent with `percent`).
//   beside  next to the cursor at the top of the plot, flipping to the left
//           of it with `flip` (the graphs' multi line tooltip)
//   above   centered over the cursor just above the plot, so it doesn't
//           cover the line (sparklines)
// Kept inside the window either way.
const props = defineProps({
  anchor: { type: Object, default: null },
  x: { type: Number, required: true },
  percent: { type: Boolean, default: false },
  flip: { type: Boolean, default: false },
  placement: { type: String, default: 'beside' },
})
defineOptions({ inheritAttrs: false })

const GAP = 8
const MARGIN = 4
const target = document.querySelector('.v-application')
  ? '.v-application'
  : 'body'
const tipEl = useTemplateRef('tip')
// Drawn over the whole page, so with a panel full screen only its own
// tooltip shows, not those of the panels hidden behind it
const panelUid = inject('panelUid', null)
const fullscreenUid = inject('fullscreenUid', null)
const visible = computed(() => {
  const full = unref(fullscreenUid)
  return full === null || full === undefined || full === unref(panelUid)
})
// The tip's size, for keeping it in the window and placing it above
const size = ref({ width: 0, height: 0 })
let observer = null

onMounted(() => {
  observer = new ResizeObserver(() => {
    if (tipEl.value) {
      size.value = {
        width: tipEl.value.offsetWidth,
        height: tipEl.value.offsetHeight,
      }
    }
  })
  if (tipEl.value) observer.observe(tipEl.value)
  // It comes back when full screen ends
  watch(tipEl, (el, old) => {
    if (old) observer.unobserve(old)
    if (el) observer.observe(el)
  })
})
onUnmounted(() => observer?.disconnect())

// Called on every render (each mouse move), so it follows the plot as the
// page scrolls or the panel resizes
function position() {
  const rect = props.anchor?.getBoundingClientRect?.()
  if (!rect) return { display: 'none' }
  const { width, height } = size.value
  const cursor =
    rect.left + (props.percent ? (props.x / 100) * rect.width : props.x)
  let left
  let top
  if (props.placement === 'above') {
    left = cursor - width / 2
    top = rect.top - height - GAP / 2
    // No room above (top of the window): just inside the plot instead
    if (top < MARGIN) top = rect.top + MARGIN
  } else {
    left = props.flip ? cursor - width - GAP : cursor + GAP
    top = rect.top + MARGIN
  }
  left = Math.min(Math.max(left, MARGIN), window.innerWidth - width - MARGIN)
  return { left: `${left}px`, top: `${top}px` }
}
</script>

<style scoped>
.hover-tip {
  position: fixed;
  /* Over the panels and the pinned health banner, under dialogs */
  z-index: 1500;
  font-family: 'IBM Plex Sans', system-ui, sans-serif;
  font-variant-numeric: tabular-nums;
}
</style>
