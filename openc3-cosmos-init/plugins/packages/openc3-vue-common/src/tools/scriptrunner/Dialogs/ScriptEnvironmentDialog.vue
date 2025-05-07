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
  <v-dialog v-model="show" width="600">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span>Script Environment Variables</span>
        <v-spacer />
      </v-toolbar>
      <div class="pa-2">
        <v-card-text>
          <environment-chooser v-model="selected" />
        </v-card-text>
      </div>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn
          variant="outlined"
          data-test="environment-dialog-cancel"
          @click="cancel"
        >
          Cancel
        </v-btn>
        <v-btn
          variant="flat"
          data-test="environment-dialog-save"
          :disabled="!!inputError"
          @click="updateEnvironment"
        >
          Save
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { EnvironmentChooser } from '@/components'

export default {
  components: {
    EnvironmentChooser,
  },
  props: {
    modelValue: {
      type: Boolean,
      required: true,
    },
    inputEnvironment: {
      type: Array,
      required: true,
    },
  },
  data() {
    return {
      selected: [],
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
  },
  mounted: function () {
    this.loadEnvironment()
  },
  methods: {
    loadEnvironment: function () {
      this.selected = [...this.inputEnvironment]
    },
    updateEnvironment: function () {
      this.$emit('environment', this.selected)
      this.show = !this.show
    },
    cancel: function () {
      this.show = !this.show
    },
  },
}
</script>
