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
  <div class="d-flex align-center ga-1">
    <template v-for="def in defs" :key="def.name">
      <v-menu
        v-if="def.type === 'color'"
        :close-on-content-click="false"
        location="bottom start"
      >
        <template #activator="{ props: activatorProps }">
          <button
            v-bind="activatorProps"
            type="button"
            class="swatch-btn rounded cursor-pointer flex-0-0"
            :style="{ background: colorOf(def) }"
            :aria-label="`${def.label} for ${item.itemName}`"
            :title="def.label"
            :data-test="`item-option-${def.name}`"
          />
        </template>
        <v-card class="pa-3" width="280">
          <div class="text-subtitle-2 mb-2">{{ def.label }}</div>
          <color-swatches
            :colors="palette"
            :model-value="value(def)"
            class="mb-3"
            @update:model-value="(color) => set(def, color)"
          />
          <v-color-picker
            :model-value="value(def) || fallback"
            mode="hex"
            :modes="['hex']"
            hide-inputs
            elevation="0"
            width="256"
            @update:model-value="(color) => set(def, color.slice(0, 7))"
          />
          <v-btn
            block
            variant="text"
            size="small"
            class="mt-2"
            :disabled="!value(def)"
            @click="set(def, null)"
          >
            Automatic
          </v-btn>
        </v-card>
      </v-menu>
    </template>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import ColorSwatches from '../components/ColorSwatches.vue'
import { itemOption, itemOptionDefs, withItemOption } from '../panels/options'
import { SERIES_COLORS } from '../panels/colors'

// Controls for the item options a panel type declares (itemOptions in
// panels/registry.js), shown on each item row. Only colors exist today; add a
// control here alongside a new option type.
const props = defineProps({
  panel: { type: Object, required: true },
  item: { type: Object, required: true },
  // Color the item gets when its COLOR isn't set
  fallback: { type: String, default: SERIES_COLORS[0] },
})
const emit = defineEmits(['update'])

const palette = SERIES_COLORS

const defs = computed(() => itemOptionDefs(props.panel.type))

function value(def) {
  return itemOption(props.panel, props.item, def.name)
}

function colorOf(def) {
  return value(def) || props.fallback
}

function set(def, newValue) {
  emit('update', withItemOption(props.panel, props.item, def.name, newValue))
}
</script>

<style scoped>
.swatch-btn {
  width: 22px;
  height: 22px;
  border: 1px solid rgba(var(--v-border-color), 0.4);
}
</style>
