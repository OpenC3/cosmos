<!--
# Copyright 2022 OpenC3, Inc.
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
-->

<template>
  <v-dialog v-model="show" width="600">
    <v-card>
      <v-system-bar>
        <v-spacer />
        <span> Modified Plugin </span>
        <v-spacer />
      </v-system-bar>
      <v-card-text class="pa-3">
        <div>
          Plugin {{ plugin }} was modified. Would you like to delete the
          existing modified files?
        </div>
        <v-list-item
          two-line
          v-for="(target, index) in modifiedTargets"
          :key="index"
        >
          <v-list-item-content>
            <v-list-item-title>{{ target.name }}</v-list-item-title>
            <v-list-item-subtitle
              v-for="(file, itemIndex) in target.files"
              :key="itemIndex"
              >{{ file }}</v-list-item-subtitle
            >
          </v-list-item-content>
        </v-list-item>
        <v-checkbox
          v-model="deleteModified"
          label="DELETE MODIFIED! THIS CAN NOT BE UNDONE!!!"
          color="error"
          data-test="modified-plugin-delete-checkbox"
        />
      </v-card-text>
      <v-card-actions>
        <v-spacer />
        <v-btn
          class="mx-2"
          outlined
          data-test="modified-plugin-cancel"
          @click="
            show = false
            $emit('cancel')
          "
          >Cancel</v-btn
        >
        <v-btn
          class="mx-2"
          color="primary"
          data-test="modified-plugin-submit"
          @click="
            show = false
            $emit('submit', deleteModified)
          "
          >{{ submitButton }}</v-btn
        >
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'

export default {
  props: {
    value: Boolean, // value is the default prop when using v-model
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
  computed: {
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
    submitButton: function () {
      if (this.pluginDelete) {
        return 'Delete'
      } else {
        return 'Install'
      }
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
        }
      )
    }
  },
}
</script>

<style scoped></style>
