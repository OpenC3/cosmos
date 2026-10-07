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
        <template #activator="{ props }">
          <button
            v-bind="props"
            type="button"
            class="swatch-btn rounded"
            :style="{ background: colorOf(def) }"
            :aria-label="`${def.label} for ${item.itemName}`"
            :title="def.label"
            :data-test="`item-option-${def.name}`"
          />
        </template>
        <v-card class="pa-3" width="280">
          <div class="text-subtitle-2 mb-2">{{ def.label }}</div>
          <div class="d-flex flex-wrap ga-2 mb-3">
            <button
              v-for="color in palette"
              :key="color"
              type="button"
              :class="['swatch rounded', { selected: color === value(def) }]"
              :style="{ background: color }"
              :aria-label="color"
              @click="set(def, color)"
            />
          </div>
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

<script>
import { itemOption, itemOptionDefs, withItemOption } from '../panels/options'
import { SERIES_COLORS } from '../panels/colors'

// Controls for the item options a panel type declares (itemOptions in
// panels/registry.js), shown on each item row. Only colors exist today; add a
// control here alongside a new option type.
export default {
  props: {
    panel: { type: Object, required: true },
    item: { type: Object, required: true },
    // Color the item gets when its COLOR isn't set
    fallback: { type: String, default: SERIES_COLORS[0] },
  },
  emits: ['update'],
  data() {
    return { palette: SERIES_COLORS }
  },
  computed: {
    defs() {
      return itemOptionDefs(this.panel.type)
    },
  },
  methods: {
    value(def) {
      return itemOption(this.panel, this.item, def.name)
    },
    colorOf(def) {
      return this.value(def) || this.fallback
    },
    set(def, value) {
      this.$emit(
        'update',
        withItemOption(this.panel, this.item, def.name, value),
      )
    },
  },
}
</script>

<style scoped>
.swatch-btn {
  width: 22px;
  height: 22px;
  border: 1px solid rgba(var(--v-border-color), 0.4);
  cursor: pointer;
  flex: none;
}
.swatch {
  width: 24px;
  height: 24px;
  cursor: pointer;
  border: 2px solid transparent;
}
.swatch.selected {
  border-color: rgb(var(--v-theme-on-surface));
}
</style>
