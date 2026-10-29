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
  <div v-if="defs.length" class="options-grid" data-test="panel-options">
    <div
      v-for="def in defs"
      :key="def.name"
      :class="{ 'full-row': def.multiline, 'new-row': def.newRow }"
      :style="{ '--span': def.span || 4 }"
    >
      <v-switch
        v-if="def.type === 'boolean'"
        :model-value="value(def)"
        :label="def.label"
        color="primary"
        density="compact"
        hide-details
        :data-test="`option-${def.name}`"
        @update:model-value="(v) => set(def, v)"
      />
      <v-select
        v-else-if="def.type === 'select'"
        :model-value="value(def)"
        :items="def.items"
        :label="def.label"
        density="compact"
        variant="outlined"
        hide-details
        :data-test="`option-${def.name}`"
        @update:model-value="(v) => set(def, v)"
      />
      <v-text-field
        v-else-if="def.type === 'number'"
        :model-value="value(def)"
        :label="def.label"
        :suffix="def.unit"
        :min="def.min"
        :max="def.max"
        type="number"
        density="compact"
        variant="outlined"
        hide-details
        :data-test="`option-${def.name}`"
        @update:model-value="(v) => setNumber(def, v)"
      />
      <v-textarea
        v-else-if="def.type === 'text' && def.multiline"
        :model-value="value(def)"
        :label="def.label"
        rows="2"
        auto-grow
        density="compact"
        variant="outlined"
        hide-details
        :data-test="`option-${def.name}`"
        @update:model-value="(v) => set(def, v)"
      />
      <v-text-field
        v-else-if="def.type === 'text'"
        :model-value="value(def)"
        :label="def.label"
        density="compact"
        variant="outlined"
        hide-details
        :data-test="`option-${def.name}`"
        @update:model-value="(v) => set(def, v)"
      />
      <v-select
        v-else-if="def.type === 'item'"
        :model-value="itemKey(value(def))"
        :items="itemChoices"
        :label="def.label"
        density="compact"
        variant="outlined"
        hide-details
        :data-test="`option-${def.name}`"
        @update:model-value="(v) => setItem(def, v)"
      />
      <div v-if="def.help" class="text-caption text-medium-emphasis mt-1">
        {{ def.help }}
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { option, visibleOptionDefs, withOption } from '../panels/options'

// Controls for every option a panel type declares in panels/registry.js. New
// options show up here without any UI work.
const props = defineProps({
  panel: { type: Object, required: true },
})
const emit = defineEmits(['update'])

const defs = computed(() => visibleOptionDefs(props.panel))
// Item options pick from the panel's own items
const itemChoices = computed(() => [
  { title: 'Automatic', value: null },
  ...props.panel.items.map((item) => ({
    title: `${item.targetName} ${item.packetName} ${item.itemName}`,
    value: itemKey(item),
  })),
])

function value(def) {
  return option(props.panel, def.name)
}

function set(def, newValue) {
  emit('update', {
    settings: withOption(props.panel, def.name, newValue),
  })
}

function setNumber(def, newValue) {
  // Clearing the field goes back to the default
  if (newValue === '' || newValue === null) return set(def, null)
  const number = Number(newValue)
  if (Number.isNaN(number)) return
  set(def, number)
}

function itemKey(item) {
  return item ? `${item.targetName} ${item.packetName} ${item.itemName}` : null
}

function setItem(def, key) {
  const item = props.panel.items.find((i) => itemKey(i) === key)
  set(def, item ? { ...item, valueType: undefined } : null)
}
</script>

<style scoped>
/* 12 columns: options span 4 (three per line) unless they set `span`, and
   `newRow` starts a line. One column on narrow screens. */
.options-grid {
  display: grid;
  grid-template-columns: repeat(12, minmax(0, 1fr));
  gap: 12px 16px;
  align-items: start;
}
.options-grid > * {
  grid-column: span var(--span);
}
.options-grid > .new-row {
  grid-column: 1 / span var(--span);
}
.options-grid > .full-row {
  grid-column: 1 / -1;
}
@media (max-width: 700px) {
  .options-grid > * {
    grid-column: 1 / -1 !important;
  }
}
</style>
