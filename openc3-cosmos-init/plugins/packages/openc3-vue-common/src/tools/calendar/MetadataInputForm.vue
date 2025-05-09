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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <span> Add metdata key value(s)</span>
    <v-table density="compact">
      <tbody>
        <tr>
          <th scope="col" class="text-left">Key</th>
          <th scope="col" class="text-left">Value</th>
          <th scope="col" class="text-right" width="52px">
            <v-btn
              icon="mdi-plus"
              variant="text"
              data-test="new-metadata-icon"
              @click="newMetadata"
            />
          </th>
        </tr>
        <tr v-for="(meta, i) in metadata" :key="`tr-${i}`">
          <td>
            <v-text-field
              v-model="meta.key"
              density="compact"
              type="text"
              hide-details
              :data-test="`key-${i}`"
            />
          </td>
          <td>
            <v-text-field
              v-model="meta.value"
              density="compact"
              type="text"
              hide-details
              :data-test="`value-${i}`"
            />
          </td>
          <td>
            <v-btn
              icon="mdi-delete"
              variant="text"
              :data-test="`delete-metadata-icon-${i}`"
              @click="rm(i)"
            />
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
