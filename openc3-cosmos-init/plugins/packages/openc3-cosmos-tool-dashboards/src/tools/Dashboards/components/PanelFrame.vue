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
    ref="frame"
    :class="[
      'panel-frame d-flex flex-column h-100 rounded-lg position-relative overflow-hidden',
      ring,
      { 'elevation-12': dragging, 'is-arranging': editing },
    ]"
    flat
    :aria-label="title"
    :aria-roledescription="editing ? 'Movable panel' : undefined"
    :tabindex="editing ? 0 : undefined"
    tag="section"
    data-test="dashboard-panel"
    @keydown="keydown"
    @pointerdown="focusFrame"
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
      <!-- A link where the type gives one (e.g. a script to Script
           Runner), not while arranging, when the header is a drag handle -->
      <a
        v-if="!titleOnly && subtitleLink && !editing"
        :href="subtitleLink"
        target="_blank"
        rel="noopener"
        class="panel-subtitle subtitle-link mono text-decoration-underline cursor-pointer text-truncate min-w-0"
        data-test="panel-subtitle-link"
      >
        {{ subtitle }}
      </a>
      <span
        v-else-if="!titleOnly"
        class="panel-subtitle mono text-medium-emphasis text-truncate min-w-0"
      >
        {{ subtitle }}
      </span>
      <v-spacer />
      <v-btn
        v-if="!editMode.on"
        :icon="fullscreen ? 'mdi-fullscreen-exit' : 'mdi-fullscreen'"
        size="small"
        variant="text"
        density="comfortable"
        :class="['fullscreen-btn', { shown: fullscreen }]"
        :aria-label="fullscreen ? 'Exit full screen' : 'Full screen'"
        :aria-pressed="fullscreen"
        aria-keyshortcuts="V"
        :title="fullscreen ? 'Exit full screen (V or Esc)' : 'Full screen (V)'"
        data-test="panel-fullscreen"
        @click="$emit('fullscreen')"
      />
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
import { computed, inject, provide, unref, useTemplateRef } from 'vue'
import StatusSymbol from './StatusSymbol.vue'
import { ringClass } from '../status'
import { PANEL_TYPES, panelTitle } from '../panels/registry'

const props = defineProps({
  panel: { type: Object, required: true },
  level: { type: String, default: null },
  editing: { type: Boolean, default: false },
  dragging: { type: Boolean, default: false },
  // Shown over the whole dashboard (DashboardGrid)
  fullscreen: { type: Boolean, default: false },
})
// move-start / resize-start carry the pointer event that began the drag,
// nudge is { dx, dy, dw, dh } in grid units from the keyboard, fullscreen
// toggles full screen
const emit = defineEmits([
  'fullscreen',
  'configure',
  'duplicate',
  'delete',
  'move-start',
  'resize-start',
  'nudge',
])

const frameRef = useTemplateRef('frame')
// Which panel the content belongs to, for things drawn outside the frame
// (HoverTip)
provide(
  'panelUid',
  computed(() => props.panel.uid),
)
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
const subtitleLink = computed(() => type.value.subtitleLink?.(props.panel))
const gridRects = inject('gridRects', null)
// The dashboard is being edited, at any width (`editing` is only true where
// panels can be arranged, the desktop layout)
const editMode = inject('editing', () => ({ on: false }), true)
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

// Fields inside a panel keep their arrow keys
const OWN_ARROWS =
  'input, textarea, select, [contenteditable], [role="combobox"], [role="listbox"], [role="slider"]'

// Clicking a panel while editing selects it for the arrow keys. The header's
// drag (pointerdown) prevents the default focus, so focus it here; a click
// on something focusable inside still moves focus there, and its arrow keys
// bubble up to keydown.
function focusFrame(event) {
  if (!props.editing || event.button !== 0) return
  if (event.target.closest(OWN_ARROWS)) return
  frameRef.value?.$el?.focus({ preventScroll: true })
}

// Arrow keys move the focused panel (or one with focus inside it),
// Shift+arrows resize it
function keydown(event) {
  if (!props.editing || event.altKey || event.ctrlKey || event.metaKey) return
  // Already handled by a control inside (e.g. a menu button opening its menu)
  if (event.defaultPrevented) return
  if (event.target.closest(OWN_ARROWS)) return
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
  /* Not Vuetify's border utility: its !important color would hide the
     status ring (dashboards.scss) */
  border: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
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
/* Only on hover or focus, so headers stay quiet; always while full screen
   so there's a visible way back. Always on touch screens (no hover). */
.fullscreen-btn:not(.shown) {
  opacity: 0;
  transition: opacity 0.15s;
}
.panel-frame:hover .fullscreen-btn,
.panel-frame:focus-within .fullscreen-btn {
  opacity: 1;
}
@media (hover: none) {
  .fullscreen-btn:not(.shown) {
    opacity: 1;
  }
}
/* The panel the arrow keys move, after a click or Tab */
.panel-frame.is-arranging:focus-within {
  outline: 2px solid rgb(var(--v-theme-primary));
  outline-offset: 2px;
}
/* Underlined in the subtitle's own color; brighter on hover */
.subtitle-link {
  color: rgba(var(--v-theme-on-surface), var(--v-medium-emphasis-opacity));
  text-underline-offset: 2px;
}
.subtitle-link:hover {
  color: rgb(var(--v-theme-on-surface));
  text-decoration-thickness: 2px;
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
