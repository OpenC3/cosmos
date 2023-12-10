<!--
# Copyright 2023 OpenC3, Inc.
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
    <v-card-title>Astro Settings</v-card-title>
    <v-card-text class="pb-0">
      <v-alert v-model="errorLoading" type="error" dismissible dense>
        Error loading previous configuration due to {{ errorText }}
      </v-alert>
      <v-container class="pb-0">
        <v-row dense>
          <v-col>
            <v-switch
              label="Hide Astro Clock"
              v-model="hideClock"
              data-test="hide-astro-clock"
            />
          </v-col>
        </v-row>
      </v-container>
    </v-card-text>
    <v-card-actions>
      <v-container class="pt-0">
        <v-row dense>
          <v-col class="pl-0">
            <v-btn
              @click="save"
              color="success"
              text
              data-test="save-astro-settings"
            >
              Save
            </v-btn>
          </v-col>
        </v-row>
        <v-alert v-model="errorSaving" type="error" dismissible dense>
          Error saving due to {{ errorText }}
        </v-alert>
        <v-alert v-model="successSaving" type="success" dismissible dense>
          Saved! (Refresh the page to see changes)
        </v-alert>
      </v-container>
    </v-card-actions>
  </v-card>
</template>

<script>
import { OpenC3Api } from '../../services/openc3-api'

const settingName = 'astro'
export default {
  data() {
    return {
      api: null,
      errorLoading: false,
      errorSaving: false,
      errorText: '',
      successSaving: false,
      hideClock: false,
    }
  },
  computed: {
    saveObj: function () {
      return JSON.stringify({
        hideClock: this.hideClock,
      })
    },
  },
  created() {
    this.api = new OpenC3Api()
    this.load()
  },
  methods: {
    load: function () {
      this.api
        .get_setting(settingName)
        .then((response) => {
          this.errorLoading = false
          if (response) {
            const parsed = JSON.parse(response)
            this.hideClock = parsed.hideClock
          }
        })
        .catch((error) => {
          this.errorText = error
          this.errorLoading = true
        })
    },
    save: function () {
      this.api
        .set_setting(settingName, this.saveObj)
        .then(() => {
          this.errorSaving = false
          this.successSaving = true
        })
        .catch((error) => {
          this.errorText = error
          this.errorSaving = true
        })
    },
  },
}
</script>
