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
  <div ref="wrap" class="w-100">
    <div
      v-if="editing && breakpoint !== 'desktop'"
      class="d-flex align-center ga-2 text-caption text-medium-emphasis mb-3"
      data-test="dashboard-breakpoint-note"
    >
      <v-icon icon="mdi-information-outline" size="16" />
      {{ notes[breakpoint] }} Widen the window to arrange panels.
    </div>
    <!-- Pulsing bars at the edges of the visible area when a panel scrolled
         out of view is in caution or critical; click to go to it -->
    <div v-if="attention.above" class="attention-anchor top">
      <button
        type="button"
        :class="['attention', `a-${attention.above.level}`]"
        :aria-label="`${levelLabel(attention.above.level)} panel above, scroll to it`"
        :title="`${attention.above.title}: ${levelLabel(attention.above.level)}`"
        data-test="attention-above"
        @click="scrollToPanel(attention.above.uid)"
      />
    </div>
    <transition-group
      ref="grid"
      tag="div"
      name="panel"
      :style="gridVars"
      :class="[
        'dashboard-grid',
        { 'show-grid': canArrange, 'fit-content': breakpoint !== 'desktop' },
      ]"
    >
      <div
        v-for="panel in panels"
        :key="panel.uid"
        :ref="(el) => observeCell(panel.uid, el)"
        :data-uid="panel.uid"
        :class="[
          'grid-cell',
          { 'panel-dragging': drag && drag.uid === panel.uid },
        ]"
        :style="cellStyle(rectOf(panel))"
      >
        <panel-frame
          :panel="panel"
          :level="levelOf(panel.uid)"
          :editing="canArrange"
          :dragging="!!drag && drag.uid === panel.uid"
          @configure="$emit('configure', panel)"
          @duplicate="$emit('duplicate', panel)"
          @delete="$emit('delete', panel)"
          @move-start="(event) => startDrag(panel, 'move', event)"
          @resize-start="(event) => startDrag(panel, 'resize', event)"
          @nudge="(change) => nudge(panel, change)"
        >
          <component
            :is="types[panel.type].component"
            v-if="rendered(panel)"
            :panel="panel"
          />
          <!-- Virtualized: far off screen, so nothing is rendered or
               streamed until it scrolls near -->
          <div
            v-else
            class="placeholder flex-grow-1 ma-3 rounded"
            data-test="panel-placeholder"
          />
        </panel-frame>
      </div>
      <slot name="after" :next-row="nextRow" />
    </transition-group>
    <div v-if="attention.below" class="attention-anchor bottom">
      <button
        type="button"
        :class="['attention', `a-${attention.below.level}`]"
        :aria-label="`${levelLabel(attention.below.level)} panel below, scroll to it`"
        :title="`${attention.below.title}: ${levelLabel(attention.below.level)}`"
        data-test="attention-below"
        @click="scrollToPanel(attention.below.uid)"
      />
    </div>
  </div>
</template>

<script setup>
import {
  computed,
  inject,
  onMounted,
  onUnmounted,
  provide,
  reactive,
  ref,
  useTemplateRef,
  watch,
} from 'vue'
import PanelFrame from './components/PanelFrame.vue'
import { PANEL_TYPES as types, panelTitle } from './panels/registry'
import { LEVEL_LABELS, stateToLevel, worstLevel } from './status'
import { itemKey } from './composables/tlmPoller'
import { pollType } from './panels/tlmPanel'
import {
  BREAKPOINT_NOTES as notes,
  GRID_GAP,
  ROW_HEIGHT,
  bottomRow,
  breakpointFor,
  cellSize,
  clampRect,
  deriveLayout,
  resolveLayout,
} from './layout'

// Renders panels on the dashboard's 12 or 24 column grid. Measures its own width to pick the
// desktop, tablet or phone layout. In edit mode on the desktop layout panels
// can be dragged, resized and nudged; changes are reported with `layout` as
// { uid: rect }. The parent reads `health` ({ level, critical, caution,
// worstUid } over every panel, for the dashboard's health chip) through the
// template ref.
const props = defineProps({
  panels: { type: Array, required: true },
  editing: { type: Boolean, default: false },
  // The dashboard's COLUMNS
  columns: { type: Number, default: 12 },
})
const emit = defineEmits(['configure', 'duplicate', 'delete', 'layout'])

const poller = inject('poller', null)
const wrapEl = useTemplateRef('wrap')
const gridRef = useTemplateRef('grid')

// uid => each panel's status. Mounted panels put their level computed here
// (usePanel), and leave its last value when they unmount.
const levels = reactive({})
provide('panelLevels', levels)
const width = ref(1200)
// Active pointer drag: { uid, mode, startX, startY, origin, cell }
const drag = ref(null)
// Positions shown while dragging, reported on drop
const preview = ref(null)
// uid => 'above' or 'below' for panels scrolled out of view
const offscreen = reactive({})
// uid => whether the panel is within a screen or so of the view; until
// the observer reports, a guess from its row (see rendered())
const near = reactive({})
// uid => grid cell element, for the visibility observer and scrolling
const cells = new Map()
let resizeObserver = null
let nearby = null
let visibility = null

const breakpoint = computed(() => breakpointFor(width.value))
// Grid geometry for the stylesheet, from the same values the layout math
// uses
const gridVars = computed(() => ({
  '--grid-columns': props.columns,
  '--grid-row': `${ROW_HEIGHT}px`,
  '--grid-gap': `${GRID_GAP}px`,
}))
const canArrange = computed(
  () => props.editing && breakpoint.value === 'desktop',
)
const layout = computed(() =>
  deriveLayout(props.panels, breakpoint.value, props.columns),
)
const nextRow = computed(() => bottomRow(Object.values(layout.value)))
// uid => poll keys for each virtualized (unmounted) panel with items
const probes = computed(() => {
  const result = {}
  for (const panel of props.panels) {
    if (rendered(panel) || !panel.items?.length) continue
    result[panel.uid] = panel.items.map((item) => itemKey(item, pollType(item)))
  }
  return result
})
const probeKeys = computed(() => Object.values(probes.value).flat())
// Current panels' levels, top to bottom (levels can hold deleted panels)
const ranked = computed(() =>
  props.panels
    .map((panel) => ({
      uid: panel.uid,
      title: panelTitle(panel),
      level: levelOf(panel.uid) ?? null,
      rect: layout.value[panel.uid],
    }))
    .sort((a, b) => a.rect.y - b.rect.y || a.rect.x - b.rect.x),
)
const health = computed(() => {
  const count = (level) =>
    ranked.value.filter((panel) => panel.level === level).length
  const level = worstLevel(ranked.value.map((panel) => panel.level))
  return {
    level,
    critical: count('critical'),
    caution: count('caution'),
    worstUid: ranked.value.find((panel) => panel.level === level)?.uid,
  }
})
// The worst caution / critical panel out of view above and below: the
// nearest one at that level, so a click goes to the closest
const attention = computed(() => {
  const pick = (side, panels) => {
    const bad = panels.filter(
      (panel) =>
        offscreen[panel.uid] === side &&
        ['critical', 'caution'].includes(panel.level),
    )
    const level = worstLevel(bad.map((panel) => panel.level))
    return bad.find((panel) => panel.level === level) ?? null
  }
  return {
    above: pick('above', [...ranked.value].reverse()),
    below: pick('below', ranked.value),
  }
})

// Where each panel is drawn right now, while dragging too, so panels can
// re-render for their new size before the drop (usePanel `rect`)
provide(
  'gridRects',
  computed(() => preview.value || layout.value),
)

// Unmounted panels' items keep being polled for their limits state, so
// the frame ring, health chip and attention bars stay right. A watcher
// because the keys change with scrolling, editing and the panels, and the
// poller registrations are outside Vue.
watch(
  probeKeys,
  (keys, previous = []) => {
    poller?.unregister(previous)
    poller?.register(keys)
  },
  { immediate: true },
)

onMounted(() => {
  resizeObserver = new ResizeObserver(([entry]) => {
    width.value = entry.contentRect.width
  })
  resizeObserver.observe(wrapEl.value)
  // Near means within 1.5 screens: those panels render, the rest wait
  nearby = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        near[Number(entry.target.dataset.uid)] = entry.isIntersecting
      }
    },
    { rootMargin: '150% 0px' },
  )
  for (const el of cells.values()) nearby.observe(el)
  // Visible means inside the window minus the app bar and footer (Vuetify
  // publishes their heights to the page as layout variables)
  const style = getComputedStyle(wrapEl.value)
  const top = parseFloat(style.getPropertyValue('--v-layout-top')) || 0
  const bottom = parseFloat(style.getPropertyValue('--v-layout-bottom')) || 0
  visibility = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        const uid = Number(entry.target.dataset.uid)
        if (entry.isIntersecting) {
          delete offscreen[uid]
        } else {
          const edge = entry.rootBounds?.top ?? 0
          offscreen[uid] =
            entry.boundingClientRect.top < edge ? 'above' : 'below'
        }
      }
    },
    { rootMargin: `-${top}px 0px -${bottom}px 0px` },
  )
  for (const el of cells.values()) visibility.observe(el)
})
onUnmounted(() => {
  poller?.unregister(probeKeys.value)
  nearby?.disconnect()
  visibility?.disconnect()
  resizeObserver?.disconnect()
  dragCancel()
})

// Function ref for each grid cell: watch it for scrolling out of view
function observeCell(uid, el) {
  const old = cells.get(uid)
  if (old === el) return
  if (old) {
    visibility?.unobserve(old)
    nearby?.unobserve(old)
  }
  if (el) {
    cells.set(uid, el)
    visibility?.observe(el)
    nearby?.observe(el)
  } else {
    cells.delete(uid)
    delete offscreen[uid]
    delete near[uid]
  }
}
// Whether to render a panel's content. Types opt in to virtualizing with
// `virtual`; editing renders everything so panels can be arranged.
function rendered(panel) {
  if (props.editing || !types[panel.type]?.virtual) return true
  const isNear = near[panel.uid]
  if (isNear !== undefined) return isNear
  // Not reported yet: render what's within about two screens of the top
  const rect = layout.value[panel.uid]
  return rect.y * (ROW_HEIGHT + GRID_GAP) < window.innerHeight * 2
}
// The panel's status: its own report while mounted, else from polling its
// items (a virtualized SCREEN keeps its last report)
function levelOf(uid) {
  const keys = probes.value[uid]
  if (!keys || !poller) return levels[uid]
  return worstLevel(keys.map((key) => stateToLevel(poller.values[key]?.state)))
}
function scrollToPanel(uid) {
  cells.get(uid)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
}
function levelLabel(level) {
  return LEVEL_LABELS[level]
}
function rectOf(panel) {
  return preview.value?.[panel.uid] || layout.value[panel.uid]
}
function cellStyle(rect) {
  return {
    gridColumn: `${rect.x + 1} / span ${rect.w}`,
    gridRow: `${rect.y + 1} / span ${rect.h}`,
    minWidth: 0,
    minHeight: 0,
  }
}

// Pointer drag to move or resize (desktop layout only)
function startDrag(panel, mode, event) {
  if (!canArrange.value || drag.value) return
  const grid = gridRef.value?.$el
  if (!grid) return
  drag.value = {
    uid: panel.uid,
    mode,
    startX: event.clientX,
    startY: event.clientY,
    origin: { x: panel.x, y: panel.y, w: panel.w, h: panel.h },
    cell: cellSize(grid, props.columns),
  }
  window.addEventListener('pointermove', dragMove)
  window.addEventListener('pointerup', dragEnd)
  window.addEventListener('pointercancel', dragCancel)
  window.addEventListener('keydown', dragKey)
}
function dragMove(event) {
  const { uid, mode, startX, startY, origin, cell } = drag.value
  const dx = Math.round((event.clientX - startX) / cell.x)
  const dy = Math.round((event.clientY - startY) / cell.y)
  // Only re-flow when the pointer crosses into another cell
  if (dx === drag.value.dx && dy === drag.value.dy) return
  drag.value.dx = dx
  drag.value.dy = dy
  const rect =
    mode === 'move'
      ? { ...origin, x: origin.x + dx, y: origin.y + dy }
      : { ...origin, w: origin.w + dx, h: origin.h + dy }
  const panels = props.panels.map((panel) =>
    panel.uid === uid
      ? {
          ...panel,
          ...clampRect({ ...rect, type: panel.type }, props.columns),
        }
      : panel,
  )
  preview.value = resolveLayout(
    panels,
    uid,
    mode === 'move' ? origin : null,
    props.columns,
  )
}
function dragEnd() {
  if (preview.value) emit('layout', preview.value)
  dragCancel()
}
function dragCancel() {
  window.removeEventListener('pointermove', dragMove)
  window.removeEventListener('pointerup', dragEnd)
  window.removeEventListener('pointercancel', dragCancel)
  window.removeEventListener('keydown', dragKey)
  drag.value = null
  preview.value = null
}
function dragKey(event) {
  if (event.key === 'Escape') dragCancel()
}
function nudge(panel, { dx, dy, dw, dh }) {
  const origin = { x: panel.x, y: panel.y, w: panel.w, h: panel.h }
  const rect = clampRect(
    {
      type: panel.type,
      x: panel.x + dx,
      y: panel.y + dy,
      w: panel.w + dw,
      h: panel.h + dh,
    },
    props.columns,
  )
  const panels = props.panels.map((p) =>
    p.uid === panel.uid ? { ...p, ...rect } : p,
  )
  emit(
    'layout',
    resolveLayout(panels, panel.uid, dw || dh ? null : origin, props.columns),
  )
}

defineExpose({ health, scrollToPanel })
</script>

<style scoped>
.dashboard-grid {
  --grid-column-width: calc(
    (100% - (var(--grid-columns) - 1) * var(--grid-gap)) / var(--grid-columns)
  );
  display: grid;
  grid-template-columns: repeat(var(--grid-columns), minmax(0, 1fr));
  grid-auto-rows: var(--grid-row);
  gap: var(--grid-gap);
}
/* Faint column guides while arranging so panels visibly snap to the grid */
.dashboard-grid.show-grid {
  background-image: linear-gradient(
    to right,
    rgba(var(--v-theme-on-surface), 0.04) 0,
    rgba(var(--v-theme-on-surface), 0.04) var(--grid-column-width),
    transparent var(--grid-column-width),
    transparent calc(var(--grid-column-width) + var(--grid-gap))
  );
  background-size: calc(var(--grid-column-width) + var(--grid-gap)) 100%;
  min-height: 200px;
}
.grid-cell {
  position: relative;
}
/* Phone and tablet: rows grow to fit content so nothing is clipped */
.dashboard-grid.fit-content {
  grid-auto-rows: minmax(var(--grid-row), auto);
}
/* Other panels glide out of the way, the dragged one follows the pointer */
.panel-move {
  transition: transform 180ms ease;
}
.panel-dragging {
  z-index: 2;
}
.panel-dragging.panel-move {
  transition: none;
}
/* Zero-height anchors that stick to the top and bottom of the visible area
   (below the app bar, above the footer) while the grid scrolls */
.placeholder {
  background: rgba(var(--v-theme-on-surface), 0.04);
}
.attention-anchor {
  position: sticky;
  z-index: 3;
  height: 0;
}
.attention-anchor.top {
  top: var(--v-layout-top, 0px);
}
.attention-anchor.bottom {
  bottom: var(--v-layout-bottom, 0px);
}
/* A 12px hit area with a 4px glowing bar on the outer edge */
.attention {
  position: absolute;
  left: 0;
  right: 0;
  height: 12px;
  cursor: pointer;
  --attention: var(--color-status-critical);
}
.attention.a-caution {
  --attention: var(--color-status-caution);
}
.top .attention {
  top: 0;
}
.bottom .attention {
  bottom: 0;
}
.attention::after {
  content: '';
  position: absolute;
  left: 0;
  right: 0;
  height: 4px;
  border-radius: 2px;
  background: var(--attention);
  box-shadow: 0 0 12px 2px color-mix(in srgb, var(--attention) 60%, transparent);
  animation: attention-pulse 1.6s ease-in-out infinite;
}
.top .attention::after {
  top: 0;
}
.bottom .attention::after {
  bottom: 0;
}
.attention:focus-visible {
  outline: 2px solid rgb(var(--v-theme-primary));
}
@keyframes attention-pulse {
  0%,
  100% {
    opacity: 0.35;
  }
  50% {
    opacity: 1;
  }
}
@media (prefers-reduced-motion: reduce) {
  .attention::after {
    animation: none;
    opacity: 0.8;
  }
}
</style>
