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
  <div>
    <div class="text-subtitle-2 mb-1">Items</div>
    <div class="text-caption text-medium-emphasis">
      Pick a target, packet and item, then Add. Repeat to mix items from other
      targets.
    </div>
    <target-packet-item-chooser
      v-if="!full"
      choose-item
      button-text="Add"
      @add-item="addItem"
    />
    <div v-else class="text-caption text-medium-emphasis py-4">
      {{ type.label }} panels show {{ type.maxItems }} item{{
        type.maxItems === 1 ? '' : 's'
      }}. Remove one to add another.
    </div>
    <div
      v-if="panel.items.length"
      class="border rounded-lg"
      data-test="config-items"
    >
      <div
        v-for="(item, index) in panel.items"
        :key="index"
        :class="[
          'd-flex align-center ga-3 px-3 py-1',
          { 'border-t': index > 0 },
        ]"
        data-test="config-item"
      >
        <span
          class="mono text-body-2 text-truncate flex-grow-1"
          :title="`${item.targetName} ${item.packetName} ${item.itemName}`"
        >
          {{ item.targetName }} {{ item.packetName }} {{ item.itemName }}
        </span>
        <item-options-editor
          :panel="panel"
          :item="item"
          :fallback="colorOf(item, index)"
          @update="(settings) => setItem(index, { settings })"
        />
        <v-select
          :model-value="item.valueType"
          :items="valueTypes"
          density="compact"
          variant="outlined"
          hide-details
          class="value-type flex-grow-0"
          aria-label="Value type"
          data-test="config-item-type"
          @update:model-value="(valueType) => setItem(index, { valueType })"
        />
        <v-btn
          icon="mdi-close"
          size="small"
          variant="text"
          :aria-label="`Remove ${item.itemName}`"
          data-test="config-item-remove"
          @click="removeItem(index)"
        />
      </div>
    </div>
  </div>
</template>

<script>
import { TargetPacketItemChooser } from '@openc3/vue-common/components'
import ItemOptionsEditor from '../../editor/ItemOptionsEditor.vue'
import { VALUE_TYPES } from '../../dashboardParser'
import { PANEL_TYPES } from '../registry'
import { seriesColor } from '../colors'

// The items a panel shows, from any targets, with each item's options
export default {
  components: { ItemOptionsEditor, TargetPacketItemChooser },
  props: {
    panel: { type: Object, required: true },
  },
  emits: ['update'],
  data() {
    return { valueTypes: VALUE_TYPES }
  },
  computed: {
    type() {
      return PANEL_TYPES[this.panel.type]
    },
    full() {
      return this.type.maxItems && this.panel.items.length >= this.type.maxItems
    },
  },
  methods: {
    addItem(item) {
      if (this.full) return
      this.$emit('update', {
        items: [
          ...this.panel.items,
          {
            targetName: item.targetName,
            packetName: item.packetName,
            itemName: item.itemName,
            valueType: item.valueType || 'CONVERTED',
            settings: {},
          },
        ],
      })
    },
    removeItem(index) {
      this.$emit('update', {
        items: this.panel.items.filter((_, i) => i !== index),
      })
    },
    setItem(index, change) {
      this.$emit('update', {
        items: this.panel.items.map((item, i) =>
          i === index ? { ...item, ...change } : item,
        ),
      })
    },
    colorOf(item, index) {
      return seriesColor(this.panel, item, index)
    },
  },
}
</script>

<style scoped>
/* A small dropdown that matches its row instead of a full size field */
.value-type {
  width: 150px;
}
.value-type :deep(.v-field) {
  --v-input-control-height: 32px;
  font-size: 12px;
}
.value-type :deep(.v-field__input) {
  min-height: 32px;
  padding-top: 4px;
  padding-bottom: 4px;
  font-size: 12px;
}
</style>
