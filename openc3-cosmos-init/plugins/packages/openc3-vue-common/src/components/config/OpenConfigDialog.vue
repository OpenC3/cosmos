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
  <v-dialog v-model="show" persistent width="600" @keydown.esc="cancel">
    <v-card>
      <form @submit.prevent="success">
        <v-toolbar height="24">
          <v-spacer />
          <span>Open Configuration</span>
          <v-spacer />
        </v-toolbar>

        <v-card-text>
          <div class="mt-4 pa-3">
            <v-row dense>
              <v-text-field
                v-model="search"
                label="Search"
                type="text"
                prepend-inner-icon="mdi-magnify"
                clearable
                variant="outlined"
                density="compact"
                clear-icon="mdi-close-circle-outline"
                autofocus
                single-line
                hide-details
                data-test="search"
              />
            </v-row>
            <v-data-table
              v-model="selectedRows"
              show-select
              select-strategy="single"
              item-value="configId"
              :search="search"
              :headers="headers"
              :items="configs"
              :items-per-page="5"
              :items-per-page-options="[5]"
              @click:row="($event, row) => selectRow(row)"
            >
              <template #item.actions="{ item }">
                <v-btn
                  class="mt-1"
                  icon="mdi-delete"
                  variant="text"
                  data-test="item-delete"
                  @click="deleteConfig(item)"
                />
              </template>
            </v-data-table>
            <v-row dense>
              <span v-show="error" class="ma-2 text-red" v-text="error" />
            </v-row>
          </div>
        </v-card-text>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn
            variant="outlined"
            data-test="open-config-cancel-btn"
            @click="cancel"
          >
            Cancel
          </v-btn>
          <v-btn
            variant="flat"
            type="submit"
            data-test="open-config-submit-btn"
            :disabled="!!error"
            @click.prevent="success"
          >
            Ok
          </v-btn>
        </v-card-actions>
      </form>
    </v-card>
  </v-dialog>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  props: {
    configKey: String,
    modelValue: Boolean, // modelValue is the default prop when using v-model
  },
  data() {
    return {
      configs: [],
      headers: [
        {
          title: 'Configuration',
          value: 'config',
        },
        {
          title: 'Actions',
          value: 'actions',
          align: 'end',
          sortable: false,
        },
      ],
      search: null,
      selectedRows: [],
    }
  },
  computed: {
    selectedItem: function () {
      if (this.selectedRows.length) {
        return this.configs.find(
          (config) => config.configId === this.selectedRows[0],
        )
      }
      return null
    },
    error: function () {
      if (this.selectedItem === '' || this.selectedItem === null) {
        return 'Must select a config'
      }
      return null
    },
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value) // update is the default event when using v-model
      },
    },
  },
  mounted() {
    let configId = -1
    new OpenC3Api()
      .list_configs(this.configKey)
      .then((response) => {
        this.configs = response.map((config) => {
          configId += 1
          return { configId, config }
        })
      })
      .catch((error) => {
        this.$emit('warning', `Failed to connect to OpenC3. ${error}`)
      })
  },
  methods: {
    selectRow: function (row) {
      this.selectedRows = [row.item.configId]
    },
    success: function () {
      if (!this.selectedItem) return
      this.$emit('success', this.selectedItem.config)
      this.show = false
      this.search = null
      this.selectedRows = []
    },
    cancel: function () {
      this.show = false
      this.search = null
      this.selectedRows = []
    },
    deleteConfig: function (item) {
      this.$dialog
        .confirm(`Are you sure you want to delete: ${item.config}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          if (this.selectedItem?.config === item.config) {
            this.selectedRows = []
          }
          this.configs.splice(this.configs.indexOf(item), 1)
          new OpenC3Api().delete_config(this.configKey, item.config)
        })
        .catch((error) => {
          if (error !== true) {
            this.$emit(
              'warning',
              `Failed to delete config ${item.config} Error: ${error}`,
            )
          }
        })
    },
  },
}
</script>
