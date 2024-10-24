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
    <v-select label="Color" :items="swatches" v-model="selectedColor">
      <template v-slot:prepend-inner v-if="selectedColor">
        <v-icon :color="selectedColor"> mdi-square </v-icon>
      </template>
      <template v-slot:item="{ props, item }">
        <v-list-item v-bind="props" :value="item">
          <template v-slot:prepend>
            <v-icon :color="item"> mdi-square </v-icon>
          </template>
        </v-list-item>
      </template>
    </v-select>
  </div>
</template>

<script>
export default {
  components: {},
  props: {
    modelValue: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      selectedColor: '',
    }
  },
  computed: {
    color: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
    swatches: function () {
      return [
        '#005a8f',
        '#003784',
        '#8F3400',
        '#df1368',
        '#ff5252',
        '#df323b',
        '#9f0010',
        '#2d9437',
        '#004700',
        '#db7200',
        '#802700',
        '#0f2941',
      ]
    },
  },
  methods: {},
}
</script>
