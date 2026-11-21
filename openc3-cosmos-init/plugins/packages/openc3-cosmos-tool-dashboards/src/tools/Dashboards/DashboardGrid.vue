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
        :class="['attention cursor-pointer', `st-${attention.above.level}`]"
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
        {
          'show-grid': canArrange,
          'fit-content': breakpoint !== 'desktop',
          'no-move': fullscreenChanging,
        },
      ]"
    >
      <div
        v-for="panel in panels"
        :key="panel.uid"
        :ref="(el) => observeCell(panel.uid, el)"
        :data-uid="panel.uid"
        :class="[
          'grid-cell',
          {
            'panel-dragging': drag && drag.uid === panel.uid,
            'panel-fullscreen': fullscreenUid === panel.uid,
          },
        ]"
        :style="cellStyle(rectOf(panel))"
        @pointerenter="hoveredUid = panel.uid"
        @pointerleave="hoveredUid === panel.uid && (hoveredUid = null)"
      >
        <panel-frame
          :panel="panel"
          :level="levelOf(panel.uid)"
          :editing="canArrange"
          :dragging="!!drag && drag.uid === panel.uid"
          :fullscreen="fullscreenUid === panel.uid"
          @configure="$emit('configure', panel)"
          @duplicate="$emit('duplicate', panel)"
          @delete="$emit('delete', panel)"
          @move-start="(event) => startDrag(panel, 'move', event)"
          @resize-start="(event) => startDrag(panel, 'resize', event)"
          @nudge="(change) => nudge(panel, change)"
          @fullscreen="toggleFullscreen(panel.uid)"
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
        :class="['attention cursor-pointer', `st-${attention.below.level}`]"
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
  nextTick,
  onBeforeUnmount,
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
import { SeriesStore } from './composables/seriesStore'
import {
  BREAKPOINT_NOTES as notes,
  GRID_GAP,
  ROW_HEIGHT,
  bottomRow,
  breakpointFor,
  cellSize,
  clampRect,
  deriveLayout,
  nudgeLayout,
  resolveLayout,
} from './layout'

// Renders panels on the dashboard's 12 or 24 column grid. Measures its own width to pick the
// desktop, tablet or phone layout. In edit mode on the desktop layout panels
// can be dragged, resized and nudged; changes are reported with `layout` as
// { uid: rect }. The parent reads `health` ({ level, critical, caution,
// worstUid, worstTitle } over every panel, for the dashboard's health
// banner) through the template ref.
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
// The panel under the mouse, for the V and E keys
const hoveredUid = ref(null)
// The panel shown full screen (V, or its header button), else null. Any
// panel can be: the grid draws it over the dashboard, so panels need no
// code of their own and keep their state (no remount).
const fullscreenUid = ref(null)
// For HoverTip: other panels' tooltips stay hidden behind a full screen one
provide('fullscreenUid', fullscreenUid)
// While full screen goes on or off: the grid's move animation is off, since
// the panel's place changing isn't a move
const fullscreenChanging = ref(false)
// One store for every graph and sparkline: a single stream, backfill per
// item and 1 s clock (useTlmSeries; LimitsPanel reads its clock)
const seriesStore = poller
  ? new SeriesStore({
      poller,
      cable: inject('cable', null),
      timeRange: inject('timeRange', () => reactive({ seconds: 120 }), true),
      timeline: inject(
        'timeline',
        () => reactive({ on: false, time: null }),
        true,
      ),
    })
  : null
provide('seriesStore', seriesStore)
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
  const worst = ranked.value.find((panel) => panel.level === level)
  return {
    level,
    critical: count('critical'),
    caution: count('caution'),
    worstUid: worst?.uid,
    worstTitle: worst?.title,
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
  computed(() => {
    const rects = preview.value || layout.value
    const uid = fullscreenUid.value
    if (uid === null || !rects[uid]) return rects
    // Full screen is the whole grid wide, so narrow panels stop shortening
    return { ...rects, [uid]: { ...rects[uid], x: 0, w: props.columns } }
  }),
)

// Unmounted panels' items keep being polled for their limits state, so
// the frame ring, health banner and attention bars stay right. A watcher
// because the keys change with scrolling, editing and the panels, and the
// poller registrations are outside Vue.
watch(probeKeys, (keys, previous = []) => poller?.replace(previous, keys), {
  immediate: true,
})

// The full screen panel was deleted (e.g. the dashboard changed)
watch(
  () => props.panels.some((panel) => panel.uid === fullscreenUid.value),
  (exists) => {
    if (!exists) fullscreenUid.value = null
  },
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
  // Visible means inside the window minus the app bar, the pinned health
  // banner and the footer (measured by Dashboards.vue), else Vuetify's
  // layout variables
  const style = getComputedStyle(wrapEl.value)
  const px = (...names) => {
    for (const name of names) {
      const value = Number.parseFloat(style.getPropertyValue(name))
      if (Number.isFinite(value)) return value
    }
    return 0
  }
  const top = px('--sticky-top', '--v-layout-top')
  const bottom = px('--chrome-bottom', '--v-layout-bottom')
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
  window.addEventListener('keydown', panelKey)
})
// Before the panels unmount and release their keys, so they don't send
// removes to a subscription that's closing
onBeforeUnmount(() => seriesStore?.dispose())
onUnmounted(() => {
  poller?.unregister(probeKeys.value)
  nearby?.disconnect()
  visibility?.disconnect()
  resizeObserver?.disconnect()
  window.removeEventListener('keydown', panelKey)
  dragCancel()
})

// Single key shortcuts on the panel with keyboard focus, else the one under
// the mouse: V shows it full screen (V or Esc goes back) and, while
// editing, E configures it. Not while typing or with a dialog open.
function panelKey(event) {
  if (event.ctrlKey || event.metaKey || event.altKey || event.repeat) return
  const key = event.key.toLowerCase()
  if (!['v', 'e', 'escape'].includes(key)) return
  const target = event.target
  if (target?.closest?.('input, textarea, select, [contenteditable]')) return
  if (
    target?.closest?.('.v-overlay') ||
    document.querySelector('.v-dialog.v-overlay--active')
  ) {
    return
  }
  if (fullscreenUid.value !== null && (key === 'v' || key === 'escape')) {
    event.preventDefault()
    void toggleFullscreen(fullscreenUid.value)
    return
  }
  if (key === 'escape') return
  const uid = targetPanel()
  if (uid === null) return
  if (key === 'v' && !props.editing) {
    event.preventDefault()
    void toggleFullscreen(uid)
  } else if (key === 'e' && props.editing) {
    const panel = props.panels.find((p) => p.uid === uid)
    if (!panel) return
    event.preventDefault()
    emit('configure', panel)
  }
}
// Full screen on or off. With view transitions, the panel grows out of its
// place in the grid to fill the window (and shrinks back) while the
// dashboard fades behind it; its content is cropped rather than stretched
// as it grows (dashboards.scss). With reduced motion it switches at once.
async function toggleFullscreen(uid) {
  // One at a time: a second toggle mid-animation would lose its frame's
  // transition name to the first one's cleanup
  if (fullscreenChanging.value) return
  const next = fullscreenUid.value === uid ? null : uid
  // Panels go full screen to view them, not while arranging them
  if (next !== null && props.editing) return
  const frame = cells
    .get(next ?? fullscreenUid.value)
    ?.querySelector('.panel-frame')
  const apply = async () => {
    fullscreenUid.value = next
    await nextTick()
  }
  fullscreenChanging.value = true
  try {
    const reduce = window.matchMedia?.(
      '(prefers-reduced-motion: reduce)',
    ).matches
    if (!document.startViewTransition || reduce || !frame) {
      await apply()
      return
    }
    // Names the same element before and after, so it morphs between them
    frame.style.viewTransitionName = 'db-fullscreen-panel'
    try {
      await document.startViewTransition(apply).finished
    } finally {
      frame.style.viewTransitionName = ''
    }
  } finally {
    fullscreenChanging.value = false
  }
}
function targetPanel() {
  const cell = document.activeElement?.closest?.('.grid-cell')
  if (cell && wrapEl.value?.contains(cell)) return Number(cell.dataset.uid)
  return hoveredUid.value
}

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
  if (panel.uid === fullscreenUid.value) return true
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
// Arrow key moves of one panel work like one long drag: each press is laid
// out from the dashboard as it was before the first press, with the total
// movement so far, so moving back restores whatever was pushed aside (one
// press at a time, panels only ever get pushed further down). The run ends
// when anything else changes the layout (a drag, undo, another panel).
// Each press still saves, so undo steps back one press at a time.
// { uid, snapshot, total: { dx, dy, dw, dh }, layout } or null
let keyRun = null
function nudge(panel, change) {
  const continuing =
    keyRun?.uid === panel.uid && sameLayout(props.panels, keyRun.layout)
  if (!continuing) {
    keyRun = {
      uid: panel.uid,
      snapshot: props.panels.map((p) => ({ ...p })),
      total: { dx: 0, dy: 0, dw: 0, dh: 0 },
      layout: null,
    }
  }
  // Down swaps with the panel below as things are now (see nudgeLayout),
  // then starts a new run from there
  if (change.dy > 0 && !change.dw && !change.dh) {
    const layout = nudgeLayout(props.panels, panel.uid, change, props.columns)
    keyRun = null
    if (layout) emit('layout', layout)
    return
  }
  const total = Object.fromEntries(
    Object.entries(keyRun.total).map(([key, value]) => [
      key,
      value + (change[key] || 0),
    ]),
  )
  const layout = nudgeLayout(keyRun.snapshot, panel.uid, total, props.columns)
  if (!layout) return
  // Clamped at an edge or size limit: don't count the press, or the next
  // ones the other way would first have to undo it
  const rect = layout[panel.uid]
  const current = props.panels.find((p) => p.uid === panel.uid) ?? panel
  if (['x', 'y', 'w', 'h'].every((key) => rect[key] === current[key])) return
  keyRun.total = total
  keyRun.layout = layout
  emit('layout', layout)
}
// Every panel where `layout` put it
function sameLayout(panels, layout) {
  return (
    !!layout &&
    panels.every((p) => {
      const rect = layout[p.uid]
      return (
        rect &&
        rect.x === p.x &&
        rect.y === p.y &&
        rect.w === p.w &&
        rect.h === p.h
      )
    })
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
/* Over the whole dashboard, inside the app bar and footer (measured,
   --chrome-top / --chrome-bottom from Dashboards.vue) and the nav drawer
   (Vuetify's layout variables). Its place in the grid stays empty. */
.grid-cell.panel-fullscreen {
  position: fixed;
  z-index: 5;
  inset: var(--chrome-top, var(--v-layout-top, 0px)) var(--v-layout-right, 0px)
    var(--chrome-bottom, var(--v-layout-bottom, 0px)) var(--v-layout-left, 0px);
  padding: 16px;
  background: rgb(var(--v-theme-background));
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
/* The dragged panel, and full screen going on or off (see
   toggleFullscreen), aren't moves */
.panel-dragging.panel-move,
.no-move > .panel-move {
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
  /* Under the app bar and the pinned health banner (Dashboards.vue) */
  top: var(--sticky-top, var(--v-layout-top, 0px));
}
.attention-anchor.bottom {
  bottom: var(--chrome-bottom, var(--v-layout-bottom, 0px));
}
/* A 12px hit area with a 4px glowing bar on the outer edge */
/* Its color is --status, from st-critical / st-caution (dashboards.scss) */
.attention {
  position: absolute;
  left: 0;
  right: 0;
  height: 12px;
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
  background: var(--status);
  box-shadow: 0 0 12px 2px color-mix(in srgb, var(--status) 60%, transparent);
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
