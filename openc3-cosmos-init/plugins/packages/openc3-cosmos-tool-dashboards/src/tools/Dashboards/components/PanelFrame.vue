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
  <v-card
    :class="[
      'panel-frame d-flex flex-column h-100 rounded-lg position-relative overflow-hidden',
      ring,
      { 'elevation-12': dragging },
    ]"
    border
    flat
    :aria-label="title"
    :aria-roledescription="editing ? 'Movable panel' : undefined"
    :tabindex="editing ? 0 : undefined"
    tag="section"
    data-test="dashboard-panel"
    @keydown="keydown"
  >
    <div
      :class="[
        'panel-header d-flex align-center ga-2 pr-2 pt-2',
        editing ? 'pl-1 move-handle' : 'pl-4',
      ]"
      style="min-height: 36px"
      data-test="panel-header"
      @pointerdown="pointerdown"
    >
      <v-icon
        v-if="editing"
        icon="mdi-drag"
        size="18"
        class="text-medium-emphasis"
        aria-hidden="true"
      />
      <h3
        class="panel-title font-weight-bold text-truncate flex-shrink-1 min-w-0"
        data-test="panel-title"
      >
        {{ title }}
      </h3>
      <span
        v-if="!titleOnly"
        class="panel-subtitle mono text-medium-emphasis text-truncate min-w-0"
      >
        {{ subtitle }}
      </span>
      <v-spacer />
      <status-symbol
        v-if="pill"
        :level="level"
        :size="16"
        class="flex-shrink-0"
        data-test="panel-status"
      />
      <v-menu v-if="editing" location="bottom end">
        <template #activator="{ props: activatorProps }">
          <v-btn
            v-bind="activatorProps"
            icon="mdi-dots-vertical"
            size="small"
            variant="text"
            density="comfortable"
            aria-label="Panel menu"
            data-test="panel-menu"
          />
        </template>
        <v-list density="compact">
          <v-list-item
            prepend-icon="mdi-pencil"
            title="Configure"
            data-test="panel-configure"
            @click="$emit('configure')"
          />
          <v-list-item
            prepend-icon="mdi-content-copy"
            title="Duplicate"
            data-test="panel-duplicate"
            @click="$emit('duplicate')"
          />
          <v-list-item
            prepend-icon="mdi-delete"
            title="Delete"
            data-test="panel-delete"
            @click="$emit('delete')"
          />
        </v-list>
      </v-menu>
    </div>
    <div class="d-flex flex-column flex-grow-1 min-h-0">
      <slot />
    </div>
    <button
      v-if="editing"
      type="button"
      class="resize-handle position-absolute d-flex align-center justify-center text-medium-emphasis"
      aria-label="Resize panel"
      title="Drag to resize"
      data-test="panel-resize"
      @pointerdown.stop.prevent="$emit('resize-start', $event)"
    >
      <v-icon icon="mdi-resize-bottom-right" size="16" />
    </button>
  </v-card>
</template>

<script setup>
import { computed, inject, unref } from 'vue'
import StatusSymbol from './StatusSymbol.vue'
import { ringClass } from '../status'
import { PANEL_TYPES, panelTitle } from '../panels/registry'

const props = defineProps({
  panel: { type: Object, required: true },
  level: { type: String, default: null },
  editing: { type: Boolean, default: false },
  dragging: { type: Boolean, default: false },
})
// move-start / resize-start carry the pointer event that began the drag,
// nudge is { dx, dy, dw, dh } in grid units from the keyboard
const emit = defineEmits([
  'configure',
  'duplicate',
  'delete',
  'move-start',
  'resize-start',
  'nudge',
])

const type = computed(() => PANEL_TYPES[props.panel.type])
// The panel's own title, else its type's, else its single item's name
const title = computed(() => panelTitle(props.panel))
// Its type's subtitle, else TARGET PACKET for every packet shown, so
// multi-target panels say so
const subtitle = computed(() => {
  if (type.value.subtitle) return type.value.subtitle(props.panel)
  const packets = new Set(
    props.panel.items.map((i) => `${i.targetName} ${i.packetName}`),
  )
  return [...packets].join(' · ')
})
// Where the panel is drawn (following a resize mid-drag) and the grid's
// COLUMNS, so "2 columns" means the same width on 12 and 24 column grids
const gridRects = inject('gridRects', null)
const columns = inject('columns', 12)
const titleOnly = computed(() => {
  if (!type.value.titleOnlyWhenNarrow) return false
  const width = unref(gridRects)?.[props.panel.uid]?.w ?? props.panel.w
  return (width * 12) / unref(columns) <= 2
})
const ring = computed(() => ringClass(props.level))
// The status symbol in the header: single item panels always name their
// status, and any panel with a caution or critical ring shows it
const pill = computed(() => {
  if (!props.level) return false
  return props.panel.items.length === 1 || !!ring.value
})

// Drag the header to move, except when pressing its buttons
function pointerdown(event) {
  if (!props.editing || event.button !== 0) return
  if (event.target.closest('button, a, input')) return
  event.preventDefault()
  emit('move-start', event)
}

// Arrow keys move the focused panel, Shift+arrows resize it
function keydown(event) {
  if (!props.editing || event.target !== event.currentTarget) return
  const step = {
    ArrowLeft: [-1, 0],
    ArrowRight: [1, 0],
    ArrowUp: [0, -1],
    ArrowDown: [0, 1],
  }[event.key]
  if (!step) return
  event.preventDefault()
  const [a, b] = step
  emit(
    'nudge',
    event.shiftKey
      ? { dx: 0, dy: 0, dw: a, dh: b }
      : { dx: a, dy: b, dw: 0, dh: 0 },
  )
}
</script>

<style scoped>
.panel-frame {
  container-type: inline-size;
}
.panel-title {
  font-size: 14px;
}
.panel-subtitle {
  font-size: 12px;
}
/* Narrow panels (phones, half width tiles) first shrink the header text,
   then drop the target / packet line only when there's still no room */
@container (max-width: 320px) {
  .panel-title {
    font-size: 12px;
  }
  .panel-subtitle {
    font-size: 10px;
  }
}
@container (max-width: 200px) {
  .panel-subtitle {
    display: none;
  }
}
.move-handle {
  cursor: grab;
  touch-action: none;
}
.move-handle:active {
  cursor: grabbing;
}
.resize-handle {
  /* Above panel content that layers itself (e.g. a STAT value over its
     graph), so small panels can still be resized */
  z-index: 2;
  right: 2px;
  bottom: 2px;
  width: 24px;
  height: 24px;
  border-radius: 6px;
  cursor: nwse-resize;
  touch-action: none;
}
.resize-handle:hover {
  background: rgba(var(--v-theme-on-surface), 0.08);
}
</style>
