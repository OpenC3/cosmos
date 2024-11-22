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
  <div>
    <v-table dense>
      <span> Add environment variables (optional)</span>
      <tbody>
        <tr>
          <th scope="col" class="text-left">Key</th>
          <th scope="col" class="text-left">Value</th>
          <th scope="col" class="text-right">
            <v-tooltip location="top">
              <template v-slot:activator="{ props }">
                <div v-bind="props">
                  <v-icon data-test="new-metadata-icon" @click="addEnvVar">
                    mdi-plus
                  </v-icon>
                </div>
              </template>
              <span> Add Environment </span>
            </v-tooltip>
          </th>
        </tr>
        <tr v-for="(env, i) in selected" :key="`tr-${i}`">
          <td>
            <v-text-field
              v-model="env.key"
              density="compact"
              type="text"
              :readonly="env.readonly"
              :data-test="`key-${i}`"
            />
          </td>
          <td>
            <v-text-field
              v-model="env.value"
              density="compact"
              type="text"
              :readonly="env.readonly"
              :data-test="`value-${i}`"
            />
          </td>
          <td>
            <v-tooltip location="top">
              <template v-slot:activator="{ props }">
                <div v-bind="props">
                  <v-icon
                    :data-test="`remove-env-icon-${i}`"
                    @click="delEnvVar(i)"
                  >
                    mdi-delete
                  </v-icon>
                </div>
              </template>
              <span> Delete Environment </span>
            </v-tooltip>
          </td>
        </tr>
      </tbody>
    </v-table>
  </div>
</template>

<script>
export default {
  props: {
    modelValue: {
      type: Array,
      required: true,
    },
  },
  computed: {
    selected: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
  },
  methods: {
    addEnvVar: function () {
      this.selected.push({
        key: '',
        value: '',
      })
    },
    delEnvVar: function (index) {
      this.selected.splice(index, 1)
    },
  },
}
</script>
