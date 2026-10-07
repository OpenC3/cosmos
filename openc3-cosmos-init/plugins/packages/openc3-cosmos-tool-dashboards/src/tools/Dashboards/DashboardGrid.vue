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
        :class="[
          'grid-cell',
          { 'panel-dragging': drag && drag.uid === panel.uid },
        ]"
        :style="cellStyle(rectOf(panel))"
      >
        <panel-frame
          :panel="panel"
          :level="levels[panel.uid]"
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
            :panel="panel"
            @level="(level) => (levels[panel.uid] = level)"
          />
        </panel-frame>
      </div>
      <slot name="after" :next-row="nextRow" />
    </transition-group>
  </div>
</template>

<script>
import PanelFrame from './components/PanelFrame.vue'
import { PANEL_TYPES } from './panels/registry'
import {
  BREAKPOINT_NOTES,
  GRID_COLUMNS,
  GRID_GAP,
  ROW_HEIGHT,
  bottomRow,
  breakpointFor,
  cellSize,
  clampRect,
  deriveLayout,
  resolveLayout,
} from './layout'

// Renders panels on the 12 column grid. Measures its own width to pick the
// desktop, tablet or phone layout. In edit mode on the desktop layout panels
// can be dragged, resized and nudged; changes are reported with `layout` as
// { uid: rect }.
export default {
  components: { PanelFrame },
  props: {
    panels: { type: Array, required: true },
    editing: { type: Boolean, default: false },
  },
  emits: ['configure', 'duplicate', 'delete', 'layout'],
  data() {
    return {
      types: PANEL_TYPES,
      notes: BREAKPOINT_NOTES,
      // Grid geometry for the stylesheet, from the same constants the layout
      // math uses
      gridVars: {
        '--grid-columns': GRID_COLUMNS,
        '--grid-row': `${ROW_HEIGHT}px`,
        '--grid-gap': `${GRID_GAP}px`,
      },
      levels: {},
      width: 1200,
      // Active pointer drag: { uid, mode, startX, startY, origin, cell }
      drag: null,
      // Positions shown while dragging, reported on drop
      preview: null,
    }
  },
  computed: {
    breakpoint() {
      return breakpointFor(this.width)
    },
    canArrange() {
      return this.editing && this.breakpoint === 'desktop'
    },
    layout() {
      return deriveLayout(this.panels, this.breakpoint)
    },
    nextRow() {
      return bottomRow(Object.values(this.layout))
    },
  },
  mounted() {
    this.resizeObserver = new ResizeObserver(([entry]) => {
      this.width = entry.contentRect.width
    })
    this.resizeObserver.observe(this.$refs.wrap)
  },
  unmounted() {
    this.resizeObserver?.disconnect()
    this.dragCancel()
  },
  methods: {
    rectOf(panel) {
      return this.preview?.[panel.uid] || this.layout[panel.uid]
    },
    cellStyle(rect) {
      return {
        gridColumn: `${rect.x + 1} / span ${rect.w}`,
        gridRow: `${rect.y + 1} / span ${rect.h}`,
        minWidth: 0,
        minHeight: 0,
      }
    },
    gridElement() {
      return this.$refs.grid?.$el
    },

    // Pointer drag to move or resize (desktop layout only)
    startDrag(panel, mode, event) {
      if (!this.canArrange || this.drag) return
      const grid = this.gridElement()
      if (!grid) return
      this.drag = {
        uid: panel.uid,
        mode,
        startX: event.clientX,
        startY: event.clientY,
        origin: { x: panel.x, y: panel.y, w: panel.w, h: panel.h },
        cell: cellSize(grid),
      }
      window.addEventListener('pointermove', this.dragMove)
      window.addEventListener('pointerup', this.dragEnd)
      window.addEventListener('pointercancel', this.dragCancel)
      window.addEventListener('keydown', this.dragKey)
    },
    dragMove(event) {
      const { uid, mode, startX, startY, origin, cell } = this.drag
      const dx = Math.round((event.clientX - startX) / cell.x)
      const dy = Math.round((event.clientY - startY) / cell.y)
      // Only re-flow when the pointer crosses into another cell
      if (dx === this.drag.dx && dy === this.drag.dy) return
      this.drag.dx = dx
      this.drag.dy = dy
      const rect =
        mode === 'move'
          ? { ...origin, x: origin.x + dx, y: origin.y + dy }
          : { ...origin, w: origin.w + dx, h: origin.h + dy }
      const panels = this.panels.map((panel) =>
        panel.uid === uid ? { ...panel, ...clampRect(rect) } : panel,
      )
      this.preview = resolveLayout(panels, uid, mode === 'move' ? origin : null)
    },
    dragEnd() {
      if (this.preview) this.$emit('layout', this.preview)
      this.dragCancel()
    },
    dragCancel() {
      window.removeEventListener('pointermove', this.dragMove)
      window.removeEventListener('pointerup', this.dragEnd)
      window.removeEventListener('pointercancel', this.dragCancel)
      window.removeEventListener('keydown', this.dragKey)
      this.drag = null
      this.preview = null
    },
    dragKey(event) {
      if (event.key === 'Escape') this.dragCancel()
    },
    nudge(panel, { dx, dy, dw, dh }) {
      const origin = { x: panel.x, y: panel.y, w: panel.w, h: panel.h }
      const rect = clampRect({
        x: panel.x + dx,
        y: panel.y + dy,
        w: panel.w + dw,
        h: panel.h + dh,
      })
      const panels = this.panels.map((p) =>
        p.uid === panel.uid ? { ...p, ...rect } : p,
      )
      this.$emit(
        'layout',
        resolveLayout(panels, panel.uid, dw || dh ? null : origin),
      )
    },
  },
}
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
</style>
