<!--
# Copyright 2025 OpenC3, Inc.
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

  <v-dialog v-model="showApiKeyAlert">
    <v-card class="pa-3">
      <v-card-text class="pb-0">
        You're using COSMOS Enterprise, but you haven't set an OpenC3 Store API
        key yet. You must set this to access Enterprise plugins.
        <br />
        <br />
        Visit the
        <a :href="accountSettingsUrl" target="_blank">
          OpenC3 Store account settings<v-icon
            icon="mdi-open-in-new"
            size="x-small"
          />
        </a>
        to generate an API key. Then, return here and open the Plugin Store
        settings with the
        <v-icon icon="mdi-cog" size="small" /> icon and paste your API key into
        the API key field.
      </v-card-text>
      <v-card-actions>
        <v-checkbox
          v-model="suppressApiKeyAlert"
          class="px-3"
          label="Don't show this message again"
          hide-details
        />
        <v-btn variant="elevated" text="OK" @click="closeApiKeyAlert" />
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { Api } from '@openc3/js-common/services'
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
      isEnterprise: false,
      showApiKeyAlert: false,
      suppressApiKeyAlert: false,
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
  computed: {
    accountSettingsUrl: function () {
      const navigableHost = this.storeUrl.replace(
        'host.docker.internal',
        'localhost',
      )
      return new URL('account', navigableHost)
    },
  },
  watch: {
    apiKey: function (val) {
      this.checkEnterpriseKey()
    },
    isEnterprise: function (val) {
      this.checkEnterpriseKey()
    },
    suppressApiKeyAlert: function (val) {
      localStorage.setItem('pluginStore.suppressApiKeyAlert', val)
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
    Api.get('/openc3-api/info').then(({ data }) => {
      this.isEnterprise = data.enterprise
    })
    this.loadSetting(URL_SETTING_NAME, { scope: SETTING_SCOPE })
    this.loadSetting(API_KEY_SETTING_NAME, { scope: SETTING_SCOPE })
    this.$emit('update:storeUrl', this.storeUrl)
  },
  methods: {
    checkEnterpriseKey: function () {
      if (this.isEnterprise && this.apiKey === '') {
        this.openApiKeyAlert()
      }
    },
    openApiKeyAlert: function () {
      if (localStorage.getItem('pluginStore.suppressApiKeyAlert') !== 'true') {
        this.showApiKeyAlert = true
      }
    },
    closeApiKeyAlert: function () {
      this.showApiKeyAlert = false
    },
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
