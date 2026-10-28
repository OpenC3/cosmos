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
  <!-- One wrapping row, or with defaultAbove the default centered on its
       own row and the colors spread across the next. The inner wrappers are
       display: contents in the single row layout. -->
  <div
    :class="
      defaultAbove
        ? 'd-flex flex-column ga-2'
        : 'd-flex flex-wrap align-center ga-2'
    "
  >
    <!-- null: the theme's default color. A labeled pill, set apart from the
         palette, so it doesn't read as one more color -->
    <div
      v-if="allowDefault"
      :class="defaultAbove ? 'd-flex justify-center' : 'contents'"
    >
      <button
        type="button"
        :class="[
          'default-option d-inline-flex align-center ga-1 rounded-pill px-2 cursor-pointer text-caption',
          { selected: !modelValue },
        ]"
        :style="{ height: `${size}px` }"
        :aria-pressed="!modelValue"
        :title="defaultTitle"
        data-test="color-default"
        @click="$emit('update:modelValue', null)"
      >
        <v-icon v-if="!modelValue" icon="mdi-check" size="14" />
        <span
          v-else
          class="default-dot rounded-circle"
          :style="defaultColor ? { background: defaultColor } : null"
        />
        {{ defaultLabel }}
      </button>
    </div>
    <div :class="defaultAbove ? 'd-flex justify-space-between' : 'contents'">
      <button
        v-for="color in colors"
        :key="color"
        type="button"
        :class="[
          'swatch d-inline-flex align-center justify-center rounded cursor-pointer',
          { selected: color === modelValue },
        ]"
        :style="{ ...sizeStyle, background: color }"
        :aria-label="color"
        :aria-pressed="color === modelValue"
        @click="$emit('update:modelValue', color)"
      >
        <v-icon
          v-if="color === modelValue"
          icon="mdi-check"
          size="16"
          class="swatch-check"
        />
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

// A row of color swatches; the picked one is ringed and checked
const props = defineProps({
  colors: { type: Array, required: true },
  modelValue: { type: String, default: null },
  // Swatch width and height in px
  size: { type: Number, default: 24 },
  // Lead with a button for no color (null), e.g. the theme's default
  allowDefault: { type: Boolean, default: false },
  defaultLabel: { type: String, default: 'Default' },
  // The color used while it's unset, for the default button's dot
  defaultColor: { type: String, default: null },
  defaultTitle: { type: String, default: "The theme's default color" },
  // The default centered on its own row, the colors across the next
  defaultAbove: { type: Boolean, default: false },
})
defineEmits(['update:modelValue'])

const sizeStyle = computed(() => ({
  width: `${props.size}px`,
  height: `${props.size}px`,
}))
</script>

<style scoped>
.contents {
  display: contents;
}
.swatch {
  border: 2px solid transparent;
}
/* A ring with a gap, so it shows against every swatch color */
.swatch.selected {
  border-color: rgb(var(--v-theme-surface));
  box-shadow: 0 0 0 2px rgb(var(--v-theme-on-surface));
}
.swatch-check {
  color: rgba(0, 0, 0, 0.75);
}
.default-option {
  border: 1px dashed rgba(var(--v-theme-on-surface), 0.38);
  background: transparent;
  color: rgba(var(--v-theme-on-surface), var(--v-medium-emphasis-opacity));
}
.default-option.selected {
  border: 1px solid rgb(var(--v-theme-on-surface));
  background: rgba(var(--v-theme-on-surface), 0.08);
  color: rgb(var(--v-theme-on-surface));
}
.default-dot {
  width: 10px;
  height: 10px;
  background: rgb(var(--v-theme-secondary));
}
</style>
