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
    <v-card>
      <v-card-title> Reset suppressed warnings </v-card-title>
      <v-card-subtitle>
        This resets "don't show this again" dialogs on this browser
      </v-card-subtitle>
      <v-card-text class="pb-0 ml-2">
        <template v-if="suppressedWarnings.length">
          <v-checkbox
            v-model="selectAllSuppressedWarnings"
            label="Select all"
            class="mt-0"
            data-test="select-all-suppressed-warnings"
          />
          <v-checkbox
            v-for="warning in suppressedWarnings"
            :key="warning.key"
            v-model="selectedSuppressedWarnings"
            :label="warning.text"
            :value="warning.key"
            class="mt-0"
            dense
          />
        </template>
        <template v-else> No warnings to reset </template>
      </v-card-text>
      <v-card-actions>
        <v-btn
          :disabled="!selectedSuppressedWarnings.length"
          @click="resetSuppressedWarnings"
          color="warning"
          text
          class="ml-2"
          data-test="reset-suppressed-warnings"
        >
          Reset
        </v-btn>
      </v-card-actions>
    </v-card>
    <v-divider />
    <v-card>
      <v-card-title> Clear default configs </v-card-title>
      <v-card-subtitle>
        This clears the default tool configs on this browser
      </v-card-subtitle>
      <v-card-text class="pb-0 ml-2">
        <template v-if="lastConfigs.length">
          <v-checkbox
            v-model="selectAllLastConfigs"
            label="Select all"
            class="mt-0"
            data-test="select-all-default-configs"
          />
          <v-checkbox
            v-for="config in lastConfigs"
            :key="config.key"
            v-model="selectedLastConfigs"
            :label="config.text"
            :value="config.key"
            class="mt-0"
            dense
          />
        </template>
        <template v-else> No configs to clear </template>
      </v-card-text>
      <v-card-actions>
        <v-btn
          :disabled="!selectedLastConfigs.length"
          @click="clearLastConfigs"
          color="warning"
          text
          class="ml-2"
          data-test="clear-default-configs"
        >
          Clear
        </v-btn>
      </v-card-actions>
    </v-card>
    <v-divider />
    <astro-settings />
    <v-divider />
    <classification-banner-settings />
    <v-divider />
    <v-card>
      <v-card-title> Subtitle </v-card-title>
      <v-card-subtitle>
        This sets a subtitle to display below the COSMOS logo in the Navigation
        bar.
      </v-card-subtitle>
      <v-card-text class="pb-0 ml-2">
        <v-text-field
          label="Subtitle"
          v-model="subtitle"
          data-test="subtitle"
        />
      </v-card-text>
      <v-card-actions>
        <v-container class="pt-0">
          <v-row dense>
            <v-col class="pl-0">
              <v-btn
                @click="saveSubtitle"
                color="success"
                text
                data-test="save-subtitle"
              >
                Save
              </v-btn>
            </v-col>
          </v-row>
          <v-alert v-model="subtitleErrorSaving" type="error" dismissible dense>
            Error saving
          </v-alert>
          <v-alert
            v-model="subtitleSuccessSaving"
            type="success"
            dismissible
            dense
          >
            Saved! (Refresh the page to see changes)
          </v-alert>
        </v-container>
      </v-card-actions>
    </v-card>
    <v-divider />
    <v-card>
      <v-card-title> Source code URL </v-card-title>
      <v-card-subtitle>
        This sets the URL for the "Source" link in the footer. This is required
        under the AGPL license.
      </v-card-subtitle>
      <v-card-text class="pb-0 ml-2">
        <v-text-field
          label="Source URL"
          v-model="sourceUrl"
          data-test="source-url"
        />
      </v-card-text>
      <v-card-actions>
        <v-container class="pt-0">
          <v-row dense>
            <v-col class="pl-0">
              <v-btn
                @click="saveSourceUrl"
                color="success"
                text
                data-test="save-source-url"
              >
                Save
              </v-btn>
            </v-col>
          </v-row>
          <v-alert
            v-model="sourceUrlErrorSaving"
            type="error"
            dismissible
            dense
          >
            Error saving
          </v-alert>
          <v-alert
            v-model="sourceUrlSuccessSaving"
            type="success"
            dismissible
            dense
          >
            Saved! (Refresh the page to see changes)
          </v-alert>
        </v-container>
      </v-card-actions>
    </v-card>
    <v-divider />
    <v-card>
      <v-card-title> Rubygems URL </v-card-title>
      <v-card-subtitle>
        This sets the URL for installing dependency rubygems. Also used for
        rubygem discovery.
      </v-card-subtitle>
      <v-card-text class="pb-0 ml-2">
        <v-text-field
          label="Rubygems URL"
          v-model="rubygemsUrl"
          data-test="rubygems-url"
        />
      </v-card-text>
      <v-card-actions>
        <v-container class="pt-0">
          <v-row dense>
            <v-col class="pl-0">
              <v-btn
                @click="saveRubygemsUrl"
                color="success"
                text
                data-test="save-rubygems-url"
              >
                Save
              </v-btn>
            </v-col>
          </v-row>
          <v-alert
            v-model="rubygemsUrlErrorSaving"
            type="error"
            dismissible
            dense
          >
            Error saving
          </v-alert>
          <v-alert
            v-model="rubygemsUrlSuccessSaving"
            type="success"
            dismissible
            dense
          >
            Saved! (Refresh the page to see changes)
          </v-alert>
        </v-container>
      </v-card-actions>
    </v-card>
    <v-divider />
    <v-card>
      <v-card-title> Pypi URL </v-card-title>
      <v-card-subtitle>
        This sets the URL for installing dependency python packages. Also used
        for package discovery.
      </v-card-subtitle>
      <v-card-text class="pb-0 ml-2">
        <v-text-field label="Pypi URL" v-model="pypiUrl" data-test="pypi-url" />
      </v-card-text>
      <v-card-actions>
        <v-container class="pt-0">
          <v-row dense>
            <v-col class="pl-0">
              <v-btn
                @click="savePypiUrl"
                color="success"
                text
                data-test="save-pypi-url"
              >
                Save
              </v-btn>
            </v-col>
          </v-row>
          <v-alert v-model="pypiUrlErrorSaving" type="error" dismissible dense>
            Error saving
          </v-alert>
          <v-alert
            v-model="pypiUrlSuccessSaving"
            type="success"
            dismissible
            dense
          >
            Saved! (Refresh the page to see changes)
          </v-alert>
        </v-container>
      </v-card-actions>
    </v-card>
  </div>
</template>

<script>
import { OpenC3Api } from '../../../services/openc3-api'
import AstroSettings from '../AstroSettings.vue'
import ClassificationBannerSettings from '../ClassificationBannerSettings.vue'

export default {
  components: {
    AstroSettings,
    ClassificationBannerSettings,
  },
  data() {
    return {
      api: new OpenC3Api(),
      suppressedWarnings: [],
      selectedSuppressedWarnings: [],
      selectAllSuppressedWarnings: false,
      lastConfigs: [],
      selectedLastConfigs: [],
      selectAllLastConfigs: false,
      subtitle: '',
      subtitleErrorSaving: false,
      subtitleSuccessSaving: false,
      sourceUrl: '',
      sourceUrlErrorSaving: false,
      sourceUrlSuccessSaving: false,
      rubygemsUrl: '',
      rubygemsUrlErrorSaving: false,
      rubygemsUrlSuccessSaving: false,
      pypiUrl: '',
      pypiUrlErrorSaving: false,
      pypiUrlSuccessSaving: false,
    }
  },
  watch: {
    selectAllSuppressedWarnings: function (val) {
      if (val) {
        this.selectedSuppressedWarnings = this.suppressedWarnings.map(
          (warning) => warning.key
        )
      } else {
        this.selectedSuppressedWarnings = []
      }
    },
    selectAllLastConfigs: function (val) {
      if (val) {
        this.selectedLastConfigs = this.lastConfigs.map((config) => config.key)
      } else {
        this.selectedLastConfigs = []
      }
    },
  },
  created() {
    this.loadSuppressedWarnings()
    this.loadLastConfigs()
    this.loadSubtitle()
    this.loadSourceUrl()
    this.loadRubygemsUrl()
    this.loadPypiUrl()
  },
  methods: {
    loadSuppressedWarnings: function () {
      this.suppressedWarnings = Object.keys(localStorage)
        .filter((key) => {
          return key.startsWith('suppresswarning__')
        })
        .map(this.localStorageKeyToDisplayObject)
      this.selectedSuppressedWarnings = []
    },
    resetSuppressedWarnings: function () {
      this.deleteLocalStorageKeys(this.selectedSuppressedWarnings)
      this.loadSuppressedWarnings()
    },
    loadLastConfigs: function () {
      this.lastConfigs = Object.keys(localStorage)
        .filter((key) => {
          return key.endsWith('__default')
        })
        .map((key) => {
          const name = key.split('__')[0].replaceAll('_', ' ')
          return {
            key,
            text: name.charAt(0).toUpperCase() + name.slice(1),
          }
        })
      this.selectedLastConfigs = []
    },
    clearLastConfigs: function () {
      this.deleteLocalStorageKeys(this.selectedLastConfigs)
      this.loadLastConfigs()
    },
    deleteLocalStorageKeys: function (keys) {
      for (const key of keys) {
        delete localStorage[key]
      }
    },
    localStorageKeyToDisplayObject: function (key) {
      const name = key.split('__')[0].replaceAll('_', ' ')
      return {
        key,
        text: name.charAt(0).toUpperCase() + name.slice(1),
        value: localStorage[key],
      }
    },
    loadSetting: function (setting, variable, defaultValue) {
      this.api
        .get_setting(setting)
        .then((response) => {
          this[variable] = response
        })
        .catch(() => {
          this[variable] = defaultValue
        })
    },
    saveSetting: function (setting, variable) {
      this.api
        .set_setting(setting, this[variable])
        .then(() => {
          this[`${variable}ErrorSaving`] = false
          this[`${variable}SuccessSaving`] = true
        })
        .catch(() => {
          this[`${variable}ErrorSaving`] = true
          this[`${variable}SuccessSaving`] = false
        })
    },
    loadSubtitle: function () {
      this.loadSetting('subtitle', 'subtitle', null)
    },
    saveSubtitle: function () {
      this.saveSetting('subtitle', 'subtitle')
    },
    loadSourceUrl: function () {
      this.loadSetting(
        'source_url',
        'sourceUrl',
        'https://github.com/OpenC3/cosmos'
      )
    },
    saveSourceUrl: function () {
      this.saveSetting('source_url', 'sourceUrl')
    },
    loadRubygemsUrl: function () {
      this.loadSetting('rubygems_url', 'rubygemsUrl', 'https://rubygems.org')
    },
    saveRubygemsUrl: function () {
      this.saveSetting('rubygems_url', 'rubygemsUrl')
    },
    loadPypiUrl: function () {
      this.loadSetting('pypi_url', 'pypiUrl', 'https://pypi.org')
    },
    savePypiUrl: function () {
      this.saveSetting('pypi_url', 'pypiUrl')
    },
  },
}
</script>
