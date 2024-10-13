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
  <v-dialog v-model="show" @keydown.esc="cancel" width="600">
    <v-card>
      <form v-on:submit.prevent="success">
        <v-toolbar height="24">
          <v-spacer />
          <span>Save Configuration</span>
          <v-spacer />
        </v-toolbar>

        <v-card-text>
          <div class="mt-4 pa-3">
            <v-row dense>
              <v-text-field
                label="search"
                v-model="search"
                type="text"
                prepend-inner-icon="mdi-magnify"
                clearable
                variant="outlined"
                density="compact"
                clear-icon="mdi-close-circle-outline"
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
              <template v-slot:item.actions="{ item }">
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
              <v-text-field
                v-model="configName"
                hide-details
                autofocus
                :disabled="!!selectedItem"
                label="Configuration Name"
                data-test="name-input-save-config-dialog"
              />
            </v-row>
            <v-row dense>
              <span class="ma-2 text-red" v-show="error" v-text="error" />
            </v-row>
          </div>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="outlined" class="mx-2" @click="cancel">
            Cancel
          </v-btn>
          <v-btn
            @click.prevent="success"
            type="submit"
            color="primary"
            class="mx-2"
            data-test="save-config-submit-btn"
            :disabled="!!error"
          >
            Ok
          </v-btn>
        </v-card-actions>
      </form>
    </v-card>
  </v-dialog>
</template>

<script>
import { OpenC3Api } from '../../services/openc3-api.js'

export default {
  props: {
    configKey: String,
    modelValue: Boolean, // modelValue is the default prop when using v-model
  },
  data() {
    return {
      configName: '',
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
      if (!this.configName) {
        return 'Config must have a name'
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
      this.$emit('success', this.configName)
      this.show = false
      this.search = null
      this.selectedRows = []
      this.configName = ''
    },
    cancel: function () {
      this.show = false
      this.search = null
      this.selectedRows = []
      this.configName = ''
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
            this.configName = ''
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
  watch: {
    selectedItem: function (val) {
      if (val) {
        this.configName = val.config
      }
    },
  },
}
</script>
