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
      <v-alert v-model="errorLoading" type="error" closable density="compact">
        Error loading previous configuration due to {{ errorText }}
      </v-alert>
      <v-alert v-model="errorSaving" type="error" closable density="compact">
        Error saving due to {{ errorText }}
      </v-alert>
      <v-alert
        v-model="successSaving"
        type="success"
        closable
        density="compact"
      >
        Saved!
      </v-alert>
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
import Settings from '@/tools/admin/tabs/settings/settings.js'

const settingName = 'store_url'
export default {
  mixins: [Settings],
  props: {
    modelValue: Boolean,
  },
  emits: ['update:modelValue', 'update:storeUrl'],
  data() {
    return {
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
    this.loadSetting(settingName)
  },
  methods: {
    save() {
      this.saveSetting(settingName, this.storeUrl)
      this.$emit('update:storeUrl', this.storeUrl)
      this.showDialog = false
    },
    parseSetting: function (response) {
      if (response) {
        this.storeUrl = response
      } else {
        // Default URL if setting is not found
        this.storeUrl = 'https://store.openc3.com'
      }
    },
  },
}
</script>
