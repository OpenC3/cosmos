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
  <v-dialog v-model="show" width="600" @keydown.enter="success()">
    <v-card class="pa-3">
      <v-card-title class="headline">Edit Item</v-card-title>
      <v-select
        outlined
        hide-details
        label="Value Type"
        :items="valueTypes"
        v-model="editItem.valueType"
      />
      <v-select
        outlined
        hide-details
        label="Reduction"
        :items="reduction"
        v-model="editItem.reduced"
      />
      <v-select
        outlined
        hide-details
        label="Reduced Type"
        :items="reducedTypes"
        :disabled="currentReduced === 'DECOM'"
        v-model="editItem.reducedType"
      />
      <v-select
        outlined
        hide-details
        label="Color"
        :items="colors"
        v-model="editItem.color"
        @change="$emit('changeColor', $event)"
      />
      <div v-if="limitsNames.length > 1">
        <v-select
          outlined
          hide-details
          label="Display Limits"
          :items="limitsNames"
          v-model="selectedLimits"
          @change="$emit('enableLimits', limits[selectedLimits])"
        />
        <div class="pa-3">
          {{ selectedLimits }}: {{ limits[selectedLimits] }}
        </div>
      </div>
      <v-card-actions>
        <v-btn color="primary" @click="$emit('close', editItem)">Ok</v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { OpenC3Api } from '../services/openc3-api.js'
export default {
  props: {
    value: Boolean, // value is the default prop when using v-model
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
      limits: { NONE: [] },
      selectedLimits: null,
      valueTypes: ['CONVERTED', 'RAW'],
      reduction: [
        // Map NONE to DECOM for clarity
        { text: 'NONE', value: 'DECOM' },
        { text: 'REDUCED_MINUTE', value: 'REDUCED_MINUTE' },
        { text: 'REDUCED_HOUR', value: 'REDUCED_HOUR' },
        { text: 'REDUCED_DAY', value: 'REDUCED_DAY' },
      ],
      reducedTypes: ['MIN', 'MAX', 'AVG', 'STDDEV'],
    }
  },
  computed: {
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
    limitsNames() {
      return Object.keys(this.limits)
    },
  },
  async created() {
    this.editItem = { ...this.item }
    await this.api
    this.api = new OpenC3Api()
      .get_item(this.item.targetName, this.item.packetName, this.item.itemName)
      .then((details) => {
        console.log(details.limits)
        for (const [key, value] of Object.entries(details.limits)) {
          console.log(`${key}: ${value} keys:${Object.keys(value)}`)
          if (Object.keys(value).includes('red_low')) {
            // Must call this.$set to allow Vue to make the limits object reactive
            this.$set(this.limits, key, Object.values(value))
          }
        }
      })
  },
}
</script>
