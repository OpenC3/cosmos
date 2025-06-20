<!--
# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="showDialog" width="600">
    <v-toolbar height="24">
      <v-spacer />
      <span>Plugin Store Settings</span>
      <v-spacer />
    </v-toolbar>
    <v-card class="pa-3">
      <v-card-text>
        <v-text-field
          v-model="storeUrl"
          label="Store URL"
          :rules="[rules.required, rules.url]"
        />
      </v-card-text>
      <v-card-actions>
        <v-btn
          color="success"
          variant="text"
          text="Save"
          data-test="save-store-settings-btn"
          @click="save"
        />
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'
import { PluginStoreApi } from '@/tools/admin/tabs/plugins'

const settingName = 'store_url'
export default {
  props: {
    modelValue: Boolean,
  },
  emits: ['update:modelValue', 'update:storeUrl'],
  data() {
    return {
      cosmosApi: new OpenC3Api(),
      storeApi: new PluginStoreApi(),
      showDialog: false,
      storeUrl: '',
      rules: {
        required: (value) => !!value || 'Required',
        url: (value) => {
          try {
            new URL(value)
          } catch (_) {
            return 'Not a valid URL'
          }
          return true
        },
      },
    }
  },
  watch: {
    modelValue: function (val) {
      if (val) {
        this.showDialog = val
      }
    },
    showDialog: function (val) {
      if (!val) {
        this.$emit('update:modelValue', val)
      }
    },
  },
  created: function () {
    this.storeApi.getStoreUrl().then((storeUrl) => (this.storeUrl = storeUrl))
  },
  methods: {
    save() {
      this.storeApi
        .refreshPluginStoreUrl(this.storeUrl)
        .then(() => {
          this.$notify.normal({
            title: 'Saved store URL',
          })
          this.$emit('update:storeUrl', this.storeUrl)
          this.showDialog = false
        })
        .catch(() => {
          this.$notify.caution({
            title: 'Failed to save store URL',
          })
        })
    },
  },
}
</script>
