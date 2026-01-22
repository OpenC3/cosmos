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
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <top-bar :menus="menus" :title="title" />
  <!-- .v-table--fixed-header>.v-table__wrapper>table>thead has z-index: 2
       which makes the LogMessages table header go above the raw dialogs
       so we must increase the z-index of the card above 2 -->
  <v-card style="z-index: 4 !important">
    <v-expansion-panels v-model="panel">
      <v-expansion-panel>
        <v-expansion-panel-title>
          <v-tabs v-model="curTab" fixed-tabs grow align-tabs="start">
            <v-tab
              v-for="(tab, index) in tabs"
              :key="index"
              :to="tab.path"
              :text="tab.name"
              @click.stop
            />
          </v-tabs>
        </v-expansion-panel-title>
        <v-expansion-panel-text>
          <router-view :refresh-interval="refreshInterval" />
        </v-expansion-panel-text>
      </v-expansion-panel>
    </v-expansion-panels>
  </v-card>
  <div style="height: 15px" />
  <log-messages :time-zone="timeZone" />

  <v-dialog
    v-model="optionsDialog"
    max-width="300"
    persistent
    @keydown.esc="cancelOptions"
  >
    <v-card>
      <v-form v-model="optionsFormValid" @submit.prevent>
        <v-toolbar height="24">
          <v-spacer />
          <span>Options</span>
          <v-spacer />
        </v-toolbar>
        <v-card-text>
          <div class="pa-3">
            <v-row>
              <v-text-field
                v-model="optionsRefreshInterval"
                min="1"
                max="3600"
                step="1"
                type="number"
                label="Refresh Interval (s)"
                :rules="[rules.required, rules.min]"
                data-test="refresh-interval"
              />
            </v-row>
            <v-row class="mt-5">
              <v-spacer />
              <v-btn
                variant="outlined"
                class="mx-2"
                data-test="options-cancel-btn"
                @click="cancelOptions"
              >
                Cancel
              </v-btn>
              <v-btn
                type="submit"
                color="primary"
                class="mx-2"
                :disabled="!optionsFormValid"
                data-test="options-save-btn"
                @click="saveOptions"
              >
                Save
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </v-form>
    </v-card>
  </v-dialog>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'
import { LogMessages, TopBar } from '@openc3/vue-common/components'

export default {
  components: {
    LogMessages,
    TopBar,
  },
  data() {
    return {
      api: null,
      title: 'CmdTlmServer',
      timeZone: 'local',
      panel: 0,
      curTab: 0,
      tabs: [
        {
          name: 'Interfaces',
          path: { name: 'InterfacesTab' },
        },
        {
          name: 'Targets',
          path: { name: 'TargetsTab' },
        },
        {
          name: 'Cmd packets',
          path: { name: 'CmdPacketsTab' },
        },
        {
          name: 'Tlm packets',
          path: { name: 'TlmPacketsTab' },
        },
        {
          name: 'Routers',
          path: { name: 'RoutersTab' },
        },
        {
          name: 'Data Flows',
          path: { name: 'DataFlowsTab' },
        },
        {
          name: 'Status',
          path: { name: 'StatusTab' },
        },
      ],
      updater: null,
      refreshInterval: 1000,
      optionsRefreshInterval: 1,
      optionsDialog: false,
      optionsFormValid: true,
      rules: {
        required: (value) => !!value || 'Required',
        min: (value) => value >= 1 || 'Must be at least 1',
      },
      menus: [
        {
          label: 'File',
          items: [
            {
              label: 'Options',
              icon: 'mdi-cog',
              command: () => {
                this.optionsRefreshInterval = this.refreshInterval / 1000
                this.optionsDialog = true
              },
            },
            {
              label: 'Clear Counters',
              icon: 'mdi-eraser',
              command: () => {
                this.clearCounters()
              },
            },
          ],
        },
      ],
    }
  },
  created() {
    this.api = new OpenC3Api()
    this.api
      .get_setting('time_zone')
      .then((response) => {
        if (response) {
          this.timeZone = response
        }
      })
      .catch((error) => {
        // Do nothing
      })
  },
  methods: {
    saveOptions() {
      if (this.optionsRefreshInterval && this.optionsRefreshInterval >= 1) {
        this.refreshInterval = this.optionsRefreshInterval * 1000
      }
      this.optionsDialog = false
    },
    cancelOptions() {
      this.optionsRefreshInterval = this.refreshInterval / 1000
      this.optionsDialog = false
    },
    clearCounters() {
      this.api.get_interface_names().then((response) => {
        for (const name of response) {
          this.api.interface_cmd(name, 'clear_counters')
        }
      })
    },
  },
}
</script>

<style scoped>
.v-expansion-panel-text :deep(.v-expansion-panel-text__wrapper) {
  padding: 0px;
}

.v-list :deep(.v-label) {
  margin-left: 5px;
}

.v-list-item__icon {
  /* For some reason the default margin-right is huge */
  margin-right: 15px !important;
}

.v-list-item__title {
  color: white;
}

.v-expansion-panel-title {
  min-height: initial;
  padding: 0px;
}
</style>
