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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <!-- Edit Item dialog -->
  <v-dialog v-model="show" width="400" @keydown.enter="success()">
    <v-card>
      <v-card-title class="mb-2">Edit Item</v-card-title>
      <v-card-text>
        <v-select
          v-model="editItem.valueType"
          variant="outlined"
          hide-details
          label="Value Type"
          :items="valueTypes"
          class="mb-2"
        />
        <v-select
          v-model="editItem.reduced"
          variant="outlined"
          hide-details
          label="Reduction"
          :items="reduction"
          class="mb-2"
        />
        <v-select
          v-model="editItem.reducedType"
          variant="outlined"
          hide-details
          label="Reduced Type"
          :items="reducedTypes"
          :disabled="editItem.reduced === 'DECOM'"
          class="mb-2"
        />
        <v-select
          v-model="editItem.color"
          variant="outlined"
          hide-details
          label="Color"
          :items="colors"
          class="mb-2"
          @update:model-value="$emit('changeColor', $event)"
        />
        <div v-if="limitsNames.length > 1">
          <v-select
            v-model="limitsName"
            variant="outlined"
            hide-details
            label="Display Limits"
            :items="limitsNames"
            @update:model-value="$emit('changeLimits', limits[limitsName])"
          />
          <div class="pa-3">{{ limitsName }}: {{ limits[limitsName] }}</div>
        </div>
      </v-card-text>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn variant="outlined" @click="$emit('cancel')"> Cancel </v-btn>
        <v-btn variant="flat" @click="$emit('close', editItem)"> Ok </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'
export default {
  props: {
    modelValue: Boolean,
    item: {
      type: Object,
      required: true,
    },
    colors: {
      type: Array,
      required: true,
    },
  },
  data: function () {
    return {
      editItem: null,
      limitsName: 'NONE',
      // NONE: [] matches the default limits assigned in Graph addItems
      limits: { NONE: [] },
      valueTypes: ['CONVERTED', 'RAW'],
      reduction: [
        // Map NONE to DECOM for clarity
        { title: 'NONE', value: 'DECOM' },
        { title: 'REDUCED_MINUTE', value: 'REDUCED_MINUTE' },
        { title: 'REDUCED_HOUR', value: 'REDUCED_HOUR' },
        { title: 'REDUCED_DAY', value: 'REDUCED_DAY' },
      ],
      reducedTypes: ['MIN', 'MAX', 'AVG', 'STDDEV'],
    }
  },
  computed: {
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
    limitsNames() {
      return Object.keys(this.limits)
    },
  },
  async created() {
    this.editItem = { ...this.item }
    new OpenC3Api()
      .get_item(this.item.targetName, this.item.packetName, this.item.itemName)
      .then((details) => {
        for (const [key, value] of Object.entries(details.limits)) {
          if (Object.keys(value).includes('red_low')) {
            this.limits[key] = Object.values(value)
          }
        }
        // Locate the key for the value array that we pass in
        this.limitsName = Object.keys(this.limits).find(
          // Little hack to compare arrays you convert them to strings
          (key) => this.limits[key] + '' === this.editItem.limits + '',
        )
      })
  },
}
</script>
