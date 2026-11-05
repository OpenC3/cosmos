<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

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
      <v-card-text>
        <v-text-field
          v-model="storeUrl"
          label="Store URL"
          :rules="[rules.required, rules.url]"
        />
        <v-text-field v-model="apiKey" type="password" label="API Key" />
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

const URL_SETTING_NAME = 'store_url'
const API_KEY_SETTING_NAME = 'store_api_key'
const SETTING_SCOPE = 'DEFAULT'
const DEFAULT_STORE_URL = 'https://store.openc3.com'

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
      apiKey: null,
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
    apiKey: function (val) {
      localStorage.setItem('pluginStore.isApiKeySet', !!val)
    },
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
    this.loadSetting(URL_SETTING_NAME, { scope: SETTING_SCOPE })
    this.loadSetting(API_KEY_SETTING_NAME, { scope: SETTING_SCOPE })
    this.$emit('update:storeUrl', this.storeUrl)
  },
  methods: {
    save: function () {
      this.saveSetting(URL_SETTING_NAME, this.storeUrl, {
        scope: SETTING_SCOPE,
      })
      this.saveSetting(API_KEY_SETTING_NAME, this.apiKey, {
        scope: SETTING_SCOPE,
      })
      this.$emit('update:storeUrl', this.storeUrl)
      this.showDialog = false
    },
    parseSetting: function (response, { setting }) {
      switch (setting) {
        case URL_SETTING_NAME:
          this.storeUrl = response || DEFAULT_STORE_URL
          break
        case API_KEY_SETTING_NAME:
          this.apiKey = response || ''
          break
      }
    },
  },
}
</script>
