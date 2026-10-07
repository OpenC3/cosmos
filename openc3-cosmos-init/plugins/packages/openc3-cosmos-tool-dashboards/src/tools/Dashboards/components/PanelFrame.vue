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
        class="panel-title text-truncate flex-shrink-1"
        style="min-width: 0"
        data-test="panel-title"
      >
        {{ title }}
      </h3>
      <span
        class="panel-subtitle mono text-medium-emphasis text-truncate"
        style="min-width: 0"
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
        <template #activator="{ props }">
          <v-btn
            v-bind="props"
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
    <div class="d-flex flex-column flex-grow-1" style="min-height: 0">
      <slot />
    </div>
    <button
      v-if="editing"
      type="button"
      class="resize-handle text-medium-emphasis"
      aria-label="Resize panel"
      title="Drag to resize"
      data-test="panel-resize"
      @pointerdown.stop.prevent="$emit('resize-start', $event)"
    >
      <v-icon icon="mdi-resize-bottom-right" size="16" />
    </button>
  </v-card>
</template>

<script>
import StatusSymbol from './StatusSymbol.vue'
import { ringClass } from '../status'
import { PANEL_TYPES } from '../panels/registry'

export default {
  components: { StatusSymbol },
  props: {
    panel: { type: Object, required: true },
    level: { type: String, default: null },
    editing: { type: Boolean, default: false },
    dragging: { type: Boolean, default: false },
  },
  // move-start / resize-start carry the pointer event that began the drag,
  // nudge is { dx, dy, dw, dh } in grid units from the keyboard
  emits: [
    'configure',
    'duplicate',
    'delete',
    'move-start',
    'resize-start',
    'nudge',
  ],
  computed: {
    type() {
      return PANEL_TYPES[this.panel.type]
    },
    // The panel's own title, else its type's, else its single item's name
    title() {
      if (this.panel.title) return this.panel.title
      const own = this.type.title?.(this.panel)
      if (own) return own
      if (this.panel.items.length === 1) return this.panel.items[0].itemName
      return this.type.label
    },
    // Its type's subtitle, else TARGET PACKET for every packet shown, so
    // multi-target panels say so
    subtitle() {
      if (this.type.subtitle) return this.type.subtitle(this.panel)
      const packets = new Set(
        this.panel.items.map((i) => `${i.targetName} ${i.packetName}`),
      )
      return [...packets].join(' · ')
    },
    ring() {
      return ringClass(this.level)
    },
    // Single item panels name their status in the header
    pill() {
      return this.level && this.panel.items.length === 1
    },
  },
  methods: {
    // Drag the header to move, except when pressing its buttons
    pointerdown(event) {
      if (!this.editing || event.button !== 0) return
      if (event.target.closest('button, a, input')) return
      event.preventDefault()
      this.$emit('move-start', event)
    },
    // Arrow keys move the focused panel, Shift+arrows resize it
    keydown(event) {
      if (!this.editing || event.target !== event.currentTarget) return
      const step = {
        ArrowLeft: [-1, 0],
        ArrowRight: [1, 0],
        ArrowUp: [0, -1],
        ArrowDown: [0, 1],
      }[event.key]
      if (!step) return
      event.preventDefault()
      const [a, b] = step
      this.$emit(
        'nudge',
        event.shiftKey
          ? { dx: 0, dy: 0, dw: a, dh: b }
          : { dx: a, dy: b, dw: 0, dh: 0 },
      )
    },
  },
}
</script>

<style scoped>
.panel-frame {
  container-type: inline-size;
}
.panel-title {
  font-size: 14px;
  font-weight: 700;
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
  position: absolute;
  right: 2px;
  bottom: 2px;
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 6px;
  cursor: nwse-resize;
  touch-action: none;
}
.resize-handle:hover {
  background: rgba(var(--v-theme-on-surface), 0.08);
}
</style>
