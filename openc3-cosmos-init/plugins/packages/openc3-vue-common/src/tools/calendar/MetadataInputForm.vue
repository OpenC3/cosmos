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
  <div>
    <v-table dense>
      <tbody>
        <tr>
          <th scope="col" class="text-left">Key</th>
          <th scope="col" class="text-left">Value</th>
          <th scope="col" class="text-right">
            <v-tooltip location="top">
              <template v-slot:activator="{ props }">
                <div v-bind="props">
                  <v-icon data-test="new-metadata-icon" @click="newMetadata">
                    mdi-plus
                  </v-icon>
                </div>
              </template>
              <span> New Metadata </span>
            </v-tooltip>
          </th>
        </tr>
        <tr v-for="(meta, i) in metadata" :key="`tr-${i}`">
          <td>
            <v-text-field
              v-model="meta.key"
              type="text"
              density="compact"
              :data-test="`key-${i}`"
            />
          </td>
          <td>
            <v-text-field
              v-model="meta.value"
              type="text"
              density="compact"
              :data-test="`value-${i}`"
            />
          </td>
          <td>
            <v-tooltip location="top">
              <template v-slot:activator="{ props }">
                <div v-bind="props">
                  <v-icon
                    :data-test="`delete-metadata-icon-${i}`"
                    @click="rm(i)"
                  >
                    mdi-delete
                  </v-icon>
                </div>
              </template>
              <span> Delete Metadata </span>
            </v-tooltip>
          </td>
        </tr>
      </tbody>
    </v-table>
  </div>
</template>

<script>
export default {
  components: {},
  props: {
    modelValue: {
      type: Array,
      required: true,
    },
  },
  data() {
    return {}
  },
  computed: {
    metadata: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
  },
  methods: {
    newMetadata: function () {
      this.metadata.push({
        key: '',
        value: '',
      })
    },
    rm: function (index) {
      this.metadata.splice(index, 1)
    },
  },
}
</script>
