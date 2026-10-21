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
  <div class="d-flex flex-wrap ga-2">
    <!-- null: the theme's default color -->
    <button
      v-if="allowDefault"
      type="button"
      :class="['swatch default rounded', { selected: !modelValue }]"
      :style="sizeStyle"
      aria-label="Default color"
      title="Default"
      @click="$emit('update:modelValue', null)"
    />
    <button
      v-for="color in colors"
      :key="color"
      type="button"
      :class="['swatch rounded', { selected: color === modelValue }]"
      :style="{ ...sizeStyle, background: color }"
      :aria-label="color"
      @click="$emit('update:modelValue', color)"
    />
  </div>
</template>

<script>
// A row of color swatches; the picked one is outlined
export default {
  props: {
    colors: { type: Array, required: true },
    modelValue: { type: String, default: null },
    // Swatch width and height in px
    size: { type: Number, default: 24 },
    // Lead with a swatch for no color (null)
    allowDefault: { type: Boolean, default: false },
  },
  emits: ['update:modelValue'],
  computed: {
    sizeStyle() {
      return { width: `${this.size}px`, height: `${this.size}px` }
    },
  },
}
</script>

<style scoped>
.swatch {
  cursor: pointer;
  border: 2px solid transparent;
}
.swatch.default {
  background: rgb(var(--v-theme-secondary));
}
.swatch.selected {
  border-color: rgb(var(--v-theme-on-surface));
}
</style>
