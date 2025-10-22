<!--
# Copyright 2024 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" persistent width="600" @keydown.esc="cancel">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span> Modified Plugin </span>
        <v-spacer />
      </v-toolbar>
      <v-card-text class="pa-3 card-container">
        <div>
          Plugin {{ plugin }} was modified. Would you like to delete the
          existing modified files?
        </div>
        <v-list-item
          v-for="(target, index) in modifiedTargets"
          :key="index"
          lines="two"
        >
          <v-list-item-title>{{ target.name }}</v-list-item-title>
          <div class="file-list-container">
            <v-list-item-subtitle
              v-for="(file, itemIndex) in target.files"
              :key="itemIndex"
              >{{ file }}</v-list-item-subtitle
            >
          </div>
        </v-list-item>
        <v-checkbox
          v-model="deleteModified"
          label="DELETE MODIFIED! THIS CAN NOT BE UNDONE!!!"
          color="error"
          data-test="modified-plugin-delete-checkbox"
        />
      </v-card-text>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn
          variant="outlined"
          data-test="modified-plugin-cancel"
          @click="cancel"
        >
          Cancel
        </v-btn>
        <v-btn
          variant="flat"
          data-test="modified-plugin-submit"
          @click="
            () => {
              show = false
              $emit('submit', deleteModified)
            }
          "
        >
          Confirm
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  props: {
    modelValue: Boolean,
    plugin: String,
    targets: Array,
    pluginDelete: Boolean,
  },
  data() {
    return {
      modifiedTargets: [],
      deleteModified: false,
    }
  },
  methods: {
    cancel() {
      this.show = false
      this.$emit('cancel')
    },
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
  created() {
    for (const target of this.targets) {
      Api.get(`/openc3-api/targets/${target.name}/modified_files`).then(
        (response) => {
          if (response.data.length !== 0) {
            // Only push targets which actually have modified files
            this.modifiedTargets.push({
              name: target.name,
              files: response.data,
            })
          }
        },
      )
    }
  },
}
</script>

<style scoped>
.card-container {
  max-height: 80vh;
  overflow-y: auto;
}

.file-list-container {
  max-height: 50vh;
  overflow-y: auto;
}
</style>
