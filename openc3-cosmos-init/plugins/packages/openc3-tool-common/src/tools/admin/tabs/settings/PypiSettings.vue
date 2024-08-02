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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card>
    <v-card-title> Pypi URL </v-card-title>
    <v-card-subtitle>
      This sets the URL for installing dependency python packages. Also used for
      package discovery.
    </v-card-subtitle>
    <v-alert v-model="errorLoading" type="error" dismissible dense>
      Error loading previous configuration due to {{ errorText }}
    </v-alert>
    <v-alert v-model="errorSaving" type="error" dismissible dense>
      Error saving due to {{ errorText }}
    </v-alert>
    <v-alert v-model="successSaving" type="success" dismissible dense>
      Saved! (Refresh the page to see changes)
    </v-alert>
    <v-card-text class="pb-0">
      <v-text-field label="Pypi URL" v-model="pypiUrl" data-test="pypi-url" />
    </v-card-text>
    <v-card-actions>
      <v-btn @click="save" color="success" text data-test="save-pypi-url">
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import Settings from './settings.js'

const settingName = 'pypi_url'
export default {
  mixins: [Settings],
  data() {
    return {
      pypiUrl: 'https://pypi.org',
    }
  },
  created() {
    this.loadSetting(settingName)
  },
  methods: {
    save() {
      this.saveSetting(settingName, this.pypiUrl)
    },
    parseSetting: function (response) {
      if (response) {
        this.pypiUrl = response
      }
    },
  },
}
</script>
