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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <top-bar :menus="menus" :title="title" />
    <v-card>
      <v-expansion-panels v-model="panel">
        <v-expansion-panel>
          <v-expansion-panel-title>
            <v-tabs v-model="curTab" fixed-tabs>
              <v-tab
                v-for="(tab, index) in tabs"
                :key="index"
                :to="tab.url"
                :text="tab.name"
                base-color="var(--color-text-interactive-default)"
                @click.native.stop
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
    <v-dialog v-model="optionsDialog" max-width="300">
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span>Options</span>
          <v-spacer />
        </v-system-bar>
        <div class="mt-6 pa-3">
          <v-text-field
            min="0"
            max="10000"
            step="100"
            type="number"
            label="Refresh Interval (ms)"
            :model-value="refreshInterval"
            @update:model-value="refreshInterval = $event"
          />
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'
import LogMessages from '@openc3/tool-common/src/components/LogMessages'
import TopBar from '@openc3/tool-common/src/components/TopBar'
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
      curTab: null,
      tabs: [
        {
          name: 'Interfaces',
          url: '/interfaces',
        },
        {
          name: 'Targets',
          url: '/targets',
        },
        {
          name: 'Cmd packets',
          url: '/cmd-packets',
        },
        {
          name: 'Tlm packets',
          url: '/tlm-packets',
        },
        {
          name: 'Routers',
          url: '/routers',
        },
        {
          name: 'Status',
          url: '/status',
        },
      ],
      updater: null,
      refreshInterval: 1000,
      optionsDialog: false,
      menus: [
        {
          label: 'File',
          items: [
            {
              label: 'Options',
              icon: 'mdi-cog',
              command: () => {
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
    clearCounters() {
      this.api.get_interface_names().then((response) => {
        for (var i = 0; i < response.length; i++) {
          this.api.interface_cmd(response[i], 'clear_counters')
        }
      })
    },
  },
}
</script>

<style scoped>
.v-expansion-panel-content :deep(.v-expansion-panel-content__wrap) {
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
.v-expansion-panel-header {
  min-height: initial;
  padding: 0px;
}
</style>
