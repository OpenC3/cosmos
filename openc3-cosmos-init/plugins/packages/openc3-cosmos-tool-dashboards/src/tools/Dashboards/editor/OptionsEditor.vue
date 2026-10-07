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
      :class="{ 'full-row': def.multiline }"
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

<script>
import { option, visibleOptionDefs, withOption } from '../panels/options'

// Controls for every option a panel type declares in panels/registry.js. New
// options show up here without any UI work.
export default {
  props: {
    panel: { type: Object, required: true },
  },
  emits: ['update'],
  computed: {
    defs() {
      return visibleOptionDefs(this.panel)
    },
    // Item options pick from the panel's own items
    itemChoices() {
      return [
        { title: 'Automatic', value: null },
        ...this.panel.items.map((item) => ({
          title: `${item.targetName} ${item.packetName} ${item.itemName}`,
          value: this.itemKey(item),
        })),
      ]
    },
  },
  methods: {
    value(def) {
      return option(this.panel, def.name)
    },
    set(def, value) {
      this.$emit('update', {
        settings: withOption(this.panel, def.name, value),
      })
    },
    setNumber(def, value) {
      const number = Number(value)
      if (value === '' || Number.isNaN(number)) return
      this.set(def, number)
    },
    itemKey(item) {
      return item
        ? `${item.targetName} ${item.packetName} ${item.itemName}`
        : null
    },
    setItem(def, key) {
      const item = this.panel.items.find((i) => this.itemKey(i) === key)
      this.set(def, item ? { ...item, valueType: undefined } : null)
    },
  },
}
</script>

<style scoped>
/* Three options per line, one column on narrow screens */
.options-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px 16px;
  align-items: start;
}
.full-row {
  grid-column: 1 / -1;
}
@media (max-width: 700px) {
  .options-grid {
    grid-template-columns: minmax(0, 1fr);
  }
}
</style>
