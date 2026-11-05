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
      <v-autocomplete
        ref="stateAutocomplete"
        :items="rankedStateOptions"
        :model-value="selectValue"
        :disabled="disabled"
        item-title="label"
        item-value="value"
        :custom-filter="tokenizedFilter"
        :filter-keys="['title']"
        :class="stateClass"
        auto-select-first
        hide-details
        density="compact"
        variant="outlined"
        placeholder="Select..."
        min-width="120px"
        data-test="cmd-param-select"
        @update:search="search = $event"
        @update:model-value="handleStateSelect"
        @focus="resetSearchAndFocus"
      />
      <v-text-field
        v-if="manuallyEntered"
        :model-value="textFieldValue"
        hide-details
        density="compact"
        variant="outlined"
        min-width="60px"
        data-test="cmd-param-value"
        @update:model-value="handleChange"
      />
      <v-tooltip v-if="manuallyEntered" location="top">
        <template #activator="{ props }">
          <v-icon v-bind="props" class="ml-1">mdi-information-outline</v-icon>
        </template>
        <span
          >Enter a raw value (e.g. numeric) for this parameter.<br />State names
          are not accepted here.</span
        >
      </v-tooltip>
      <v-text-field
        v-else
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
import { tokenizedFilter, tokenizedSort } from '@openc3/js-common/utils'
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
    allowManualEntry: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update:modelValue', 'hazardous-change'],
  data() {
    return {
      manuallyEntered: false,
      search: '',
    }
  },
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
      if (this.manuallyEntered) {
        return '__manual__'
      }
      // this makes the placeholder prop work
      return this.modelValue === '' ? null : this.modelValue
    },
    stateOptions() {
      if (!this.states) {
        return null
      }
      const options = Object.keys(this.states).map((label) => {
        return {
          label,
          ...this.states[label],
        }
      })
      if (this.allowManualEntry) {
        options.push({ label: 'MANUALLY_ENTERED', value: '__manual__' })
      }
      return options
    },
    // Closest matches first so auto-select-first picks the best one on Enter
    rankedStateOptions() {
      if (!this.stateOptions) {
        return null
      }
      return tokenizedSort(this.stateOptions, this.search, 'label')
    },
    hazardous() {
      if (!this.states) {
        return false
      }
      // Manual entry requires ignoring range checks which is always hazardous
      if (this.manuallyEntered) {
        return true
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
    allowManualEntry(newVal) {
      if (!newVal) {
        this.manuallyEntered = false
      }
    },
  },
  methods: {
    tokenizedFilter,
    // Start each search from scratch and select the current text so typing
    // replaces it
    resetSearchAndFocus() {
      this.search = ''
      this.$nextTick(() => {
        this.$refs.stateAutocomplete?.$el.querySelector('input')?.select()
      })
    },
    handleChange(value) {
      this.$emit('update:modelValue', value)
    },
    handleStateSelect(value) {
      // Deleting all the search text clears the autocomplete. A state
      // parameter always needs a state so keep the current value.
      if (value === null || value === undefined) {
        return
      }
      if (value === '__manual__') {
        this.manuallyEntered = true
        this.$emit('update:modelValue', '')
      } else {
        this.manuallyEntered = false
        this.$emit('update:modelValue', value)
      }
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
/* Extra .v-autocomplete specificity beats the themed override in _overrides.scss */
.v-autocomplete.hazardous :deep(.v-autocomplete__selection-text),
.v-autocomplete.hazardous :deep(input) {
  color: rgb(255, 220, 0) !important;
}
</style>
