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
  <svg
    v-if="level"
    :class="['sym', `s-${level}`]"
    :style="size ? { width: `${size}px`, height: `${size}px` } : null"
    viewBox="0 0 12 12"
    :role="decorative ? undefined : 'img'"
    :aria-hidden="decorative ? 'true' : undefined"
    :aria-label="decorative ? undefined : label"
  >
    <path :d="path" />
  </svg>
</template>

<script setup>
import { computed } from 'vue'
import { LEVEL_LABELS, SYMBOL_PATHS } from '../status'

const props = defineProps({
  level: { type: String, default: null },
  size: { type: Number, default: null },
  // Decorative when a text label sits next to the symbol
  decorative: { type: Boolean, default: false },
})

const path = computed(() => SYMBOL_PATHS[props.level])
const label = computed(() => LEVEL_LABELS[props.level])
</script>
