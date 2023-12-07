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
    <classification-banner-settings />
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
import ClassificationBannerSettings from '../ClassificationBannerSettings.vue'

export default {
  components: {
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
      sourceUrl: '',
      rubygemsUrl: '',
      pypiUrl: '',
      sourceUrlErrorSaving: false,
      sourceUrlSuccessSaving: false,
      rubygemsUrlErrorSaving: false,
      rubygemsUrlSuccessSaving: false,
      pypiUrlErrorSaving: false,
      pypiUrlSuccessSaving: false,
    }
  },
  watch: {
    selectAllSuppressedWarnings: function (val) {
      if (val) {
        this.selectedSuppressedWarnings = this.suppressedWarnings.map(
          (warning) => warning.key,
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
    loadSourceUrl: function () {
      this.api
        .get_setting('source_url')
        .then((response) => {
          this.sourceUrl = response
        })
        .catch(() => {
          this.sourceUrl = 'https://github.com/OpenC3/openc3'
        })
    },
    saveSourceUrl: function () {
      this.api
        .set_setting('source_url', this.sourceUrl)
        .then(() => {
          this.sourceUrlErrorSaving = false
          this.sourceUrlSuccessSaving = true
        })
        .catch(() => {
          this.sourceUrlErrorSaving = true
        })
    },
    loadRubygemsUrl: function () {
      this.api
        .get_setting('rubygems_url')
        .then((response) => {
          this.rubygemsUrl = response
        })
        .catch(() => {
          this.rubygemsUrl = 'https://rubygems.org'
        })
    },
    saveRubygemsUrl: function () {
      this.api
        .set_setting('rubygems_url', this.rubygemsUrl)
        .then(() => {
          this.rubygemsUrlErrorSaving = false
          this.rubygemsUrlSuccessSaving = true
        })
        .catch(() => {
          this.rubygemsUrlErrorSaving = true
        })
    },
    loadPypiUrl: function () {
      this.api
        .get_setting('pypi_url')
        .then((response) => {
          this.pypiUrl = response
        })
        .catch(() => {
          this.pypiUrl = 'https://pypi.org/simple'
        })
    },
    savePypiUrl: function () {
      this.api
        .set_setting('pypi_url', this.pypiUrl)
        .then(() => {
          this.pypiUrlErrorSaving = false
          this.pypiUrlSuccessSaving = true
        })
        .catch(() => {
          this.pypiUrlErrorSaving = true
        })
    },
  },
}
</script>
