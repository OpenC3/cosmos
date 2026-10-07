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
  <div data-test="panel-settings">
    <section class="settings-grid pb-2">
      <v-autocomplete
        :model-value="panel.type"
        :items="typeItems"
        item-title="title"
        item-value="value"
        :item-props="itemProps"
        label="Type"
        density="compact"
        variant="outlined"
        hide-details
        auto-select-first
        data-test="panel-type"
        @update:model-value="changeType"
      >
        <template #selection="{ item }">
          <span class="d-flex align-center ga-2">
            <v-icon :icon="item.raw.icon" size="18" />
            {{ item.raw.title }}
          </span>
        </template>
        <template #item="{ props, item }">
          <v-list-subheader
            v-if="item.raw.header"
            class="text-uppercase font-weight-bold"
          >
            {{ item.raw.title }}
          </v-list-subheader>
          <v-list-item
            v-else
            v-bind="props"
            :prepend-icon="item.raw.icon"
            :subtitle="item.raw.description"
            :data-test="`panel-type-${item.raw.value}`"
          />
        </template>
      </v-autocomplete>
      <v-text-field
        :model-value="panel.title"
        label="Title"
        placeholder="Defaults to the item or command name"
        density="compact"
        variant="outlined"
        hide-details
        class="span-2"
        data-test="panel-title-input"
        @update:model-value="(title) => $emit('update', { title })"
      />
    </section>
    <div class="text-caption text-medium-emphasis pb-3">
      {{ types[panel.type].description }}
    </div>
    <v-divider />

    <section v-if="types[panel.type].content" class="py-3">
      <component
        :is="types[panel.type].content"
        :panel="panel"
        @update="(change) => $emit('update', change)"
      />
    </section>
    <v-divider />

    <template v-if="hasOptions">
      <section class="py-3">
        <div class="text-subtitle-2 mb-2">Options</div>
        <options-editor
          :panel="panel"
          @update="(change) => $emit('update', change)"
        />
      </section>
      <v-divider />
    </template>

    <section class="py-3">
      <div class="text-subtitle-2 mb-2">
        Size
        <span class="text-caption text-medium-emphasis ml-2">
          {{ columns }} column grid. Drag the panel to move it, or its corner to
          resize.
        </span>
      </div>
      <div class="d-flex flex-wrap align-center ga-4">
        <v-btn-toggle
          :model-value="panel.w"
          density="compact"
          variant="outlined"
          divided
          data-test="panel-width-presets"
          @update:model-value="setWidth"
        >
          <v-btn
            v-for="preset in widthPresets"
            :key="preset.w"
            :value="preset.w"
            size="small"
            :title="`${preset.w} of ${columns} columns`"
          >
            {{ preset.label }}
          </v-btn>
        </v-btn-toggle>
        <div
          class="d-flex align-center ga-2 flex-grow-1"
          style="min-width: 220px"
        >
          <span class="text-body-2">Width</span>
          <v-slider
            :model-value="panel.w"
            :min="minW"
            :max="columns"
            :step="1"
            hide-details
            color="primary"
            aria-label="Width in columns"
            data-test="panel-width"
            @update:model-value="setWidth"
          />
          <span class="text-body-2 num text-no-wrap">
            {{ panel.w }} / {{ columns }}
          </span>
        </div>
        <div
          class="d-flex align-center ga-2 flex-grow-1"
          style="min-width: 220px"
        >
          <span class="text-body-2">Height</span>
          <v-slider
            :model-value="panel.h"
            :min="minH"
            :max="maxH"
            :step="1"
            hide-details
            color="primary"
            aria-label="Height in rows"
            data-test="panel-height"
            @update:model-value="(h) => $emit('resize', { w: panel.w, h })"
          />
          <span class="text-body-2 num text-no-wrap">{{ panel.h }} rows</span>
        </div>
      </div>
      <div class="d-flex ga-1 mt-3" aria-hidden="true">
        <span
          v-for="column in columns"
          :key="column"
          :class="[
            'flex-grow-1 rounded-sm',
            column > panel.x && column <= panel.x + panel.w
              ? 'bg-primary'
              : 'bg-surface-variant',
          ]"
          style="height: 6px; opacity: 0.8"
        />
      </div>
    </section>
  </div>
</template>

<script>
import OptionsEditor from './OptionsEditor.vue'
import { PANEL_TYPES } from '../panels/registry'
import { optionDefs, settingsForType } from '../panels/options'
import { GRID_COLUMNS, MAX_H, MIN_H, MIN_W } from '../layout'
import { clearedFieldsFor } from '../dashboardParser'

// Everything about one panel: type, title, what it shows, its options and
// size. Changes are emitted as `update` with the changed fields; size changes
// as `resize`.
export default {
  components: { OptionsEditor },
  props: {
    panel: { type: Object, required: true },
  },
  emits: ['update', 'resize'],
  data() {
    return {
      types: PANEL_TYPES,
      columns: GRID_COLUMNS,
      minW: MIN_W,
      minH: MIN_H,
      maxH: MAX_H,
      widthPresets: [
        { label: '¼', w: 3 },
        { label: '⅓', w: 4 },
        { label: '½', w: 6 },
        { label: '⅔', w: 8 },
        { label: '¾', w: 9 },
        { label: 'Full', w: 12 },
      ],
    }
  },
  computed: {
    // Types grouped by category, so a long list of panel types stays easy to
    // scan; the dropdown is searchable by name
    typeItems() {
      const groups = {}
      for (const [value, type] of Object.entries(PANEL_TYPES)) {
        if (type.hidden) continue
        const category = type.category || 'Other'
        ;(groups[category] ||= []).push({
          title: type.label,
          value,
          icon: type.icon,
          description: type.description,
        })
      }
      return Object.entries(groups).flatMap(([category, items]) => [
        { title: category, value: `__${category}`, header: true },
        ...items,
      ])
    },
    hasOptions() {
      return optionDefs(this.panel.type).length > 0
    },
  },
  methods: {
    itemProps(item) {
      return item.header ? { disabled: true } : {}
    },
    setWidth(w) {
      if (!w) return
      this.$emit('resize', { w, h: this.panel.h })
    },
    // Keep what still applies to the new type
    changeType(type) {
      if (!type || type === this.panel.type || !PANEL_TYPES[type]) return
      // Clear fields the new type doesn't use, then keep what still applies
      const cleared = clearedFieldsFor(type)
      const max = PANEL_TYPES[type].maxItems
      const items = cleared.items ?? this.panel.items.slice(0, max || undefined)
      this.$emit('update', {
        ...cleared,
        type,
        items,
        settings: settingsForType(this.panel.settings, type),
      })
    },
  },
}
</script>

<style scoped>
.settings-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
}
.span-2 {
  grid-column: span 2;
}
</style>
