<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <td>
    <v-checkbox
      v-if="isCheckbox"
      dense
      hide-details
      v-model="checkValue"
      @update:model-value="checkboxChange"
      :disabled="!dataItem.editable"
      data-test="table-item-checkbox"
    />
    <v-select
      v-else-if="dataItem.states"
      density="compact"
      hide-details
      v-model="stateValue"
      @update:model-value="stateChange"
      :items="itemStates"
      :disabled="!dataItem.editable"
      data-test="table-item-select"
    />
    <v-text-field
      v-else
      variant="solo"
      density="compact"
      single-line
      hide-no-data
      hide-details
      @change="textChange"
      :model-value="format(dataItem.value)"
      :disabled="!dataItem.editable"
      data-test="table-item-text-field"
    />
  </td>
</template>

<script>
import VWidget from '@openc3/tool-common/src/components/widgets/VWidget'

export default {
  mixins: [VWidget],
  props: {
    item: {
      type: Object,
      required: true,
    },
  },
  data() {
    return {
      dataItem: this.item,
      stateValue: null,
      checkValue: false,
    }
  },
  created() {
    if (this.dataItem.states) {
      this.stateValue = this.dataItem.states[this.dataItem.value]
    }
    if (this.isCheckbox) {
      this.checkValue = this.stateValue === 1
    }
  },
  computed: {
    isCheckbox: function () {
      let result = true
      if (this.dataItem.states) {
        for (const state of Object.keys(this.dataItem.states)) {
          if (state !== 'CHECKED' && state !== 'UNCHECKED') {
            result = false
          }
        }
      } else {
        result = false
      }
      return result
    },
    itemStates: function () {
      let result = []
      for (const [text, value] of Object.entries(this.dataItem.states)) {
        result.push({ text: text, value: value })
      }
      return result
    },
  },
  methods: {
    checkboxChange: function () {
      if (this.checkValue) {
        this.$emit('change', 'CHECKED')
      } else {
        this.$emit('change', 'UNCHECKED')
      }
    },
    stateChange: function () {
      // Lookup the state key that corresponds to the value
      let state = Object.keys(this.dataItem.states).find(
        (key) => this.dataItem.states[key] === this.stateValue,
      )
      this.$emit('change', state)
    },
    textChange: function (value) {
      // Set the value since we're not using v-model on the textfield
      this.dataItem.value = value
      this.$emit('change', this.dataItem.value)
    },
    format: function (value) {
      if (
        value &&
        value['json_class'] === 'String' &&
        value['raw'] !== undefined
      ) {
        this.dataItem.editable = false
      }
      return this.formatValue(value)
    },
  },
}
</script>
