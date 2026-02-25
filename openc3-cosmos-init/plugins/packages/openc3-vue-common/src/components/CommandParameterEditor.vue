<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <v-text-field
      v-if="!states"
      :model-value="textFieldValue"
      :disabled="disabled"
      hide-details
      density="compact"
      variant="filled"
      data-test="cmd-param-value"
      @update:model-value="handleChange"
    />
    <div v-else class="d-flex align-center">
      <v-select
        :items="stateOptions"
        :model-value="selectValue"
        :disabled="disabled"
        item-title="label"
        :class="stateClass"
        hide-details
        density="compact"
        variant="outlined"
        placeholder="Select..."
        min-width="120px"
        data-test="cmd-param-select"
        @update:model-value="handleChange"
      />
      <v-text-field
        :model-value="stateValue"
        disabled
        hide-details
        density="compact"
        variant="outlined"
        min-width="60px"
        data-test="cmd-param-value"
      />
    </div>
  </div>
</template>

<script>
import { CmdUtilities } from '../util'
export default {
  name: 'CommandParameterEditor',
  mixins: [CmdUtilities],
  props: {
    modelValue: {
      type: [String, Number],
      default: undefined,
    },
    states: {
      type: Object,
      default: () => null,
    },
    statesInHex: {
      type: Boolean,
      default: false,
    },
    disabled: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update:modelValue', 'hazardous-change'],
  computed: {
    textFieldValue() {
      return this.convertToString(this.modelValue)
    },
    stateValue() {
      if (this.statesInHex) {
        return '0x' + this.modelValue.toString(16)
      } else {
        return this.modelValue
      }
    },
    selectValue() {
      // this makes the placeholder prop work
      return this.modelValue === '' ? null : this.modelValue
    },
    stateOptions() {
      if (!this.states) {
        return null
      }
      return Object.keys(this.states).map((label) => {
        return {
          label,
          ...this.states[label],
        }
      })
    },
    hazardous() {
      if (!this.states) {
        return false
      }
      return (
        Object.entries(this.states)
          .find(([label, state]) => state.value === this.modelValue)
          ?.at(1)?.hazardous !== undefined
      )
    },
    stateClass() {
      return this.hazardous ? 'hazardous mr-4' : 'mr-4'
    },
  },
  watch: {
    hazardous: {
      immediate: true,
      handler(newVal) {
        this.$emit('hazardous-change', newVal)
      },
    },
  },
  methods: {
    handleChange(value) {
      this.$emit('update:modelValue', value)
    },
  },
}
</script>
<style scoped>
/* This allows Value or State selection to be wider and show state names */
.container :deep(.v-select__selections) {
  width: auto;
}
.v-overflow-btn {
  margin-top: 0px;
}
.container {
  padding: 0px;
}
.hazardous :deep(.v-select__selection-text) {
  color: rgb(255, 220, 0) !important;
}
</style>
