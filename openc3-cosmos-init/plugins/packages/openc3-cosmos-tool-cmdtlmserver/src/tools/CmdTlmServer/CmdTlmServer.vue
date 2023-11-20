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
# All changes Copyright 2023, OpenC3, Inc.
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
          <v-expansion-panel-header>
            <v-tabs v-model="curTab" fixed-tabs>
              <v-tab
                v-for="(tab, index) in tabs"
                :key="index"
                :to="tab.url"
                @click.native.stop
              >
                {{ tab.name }}
              </v-tab>
            </v-tabs>
          </v-expansion-panel-header>
          <v-expansion-panel-content>
            <router-view :refresh-interval="refreshInterval" />
          </v-expansion-panel-content>
        </v-expansion-panel>
      </v-expansion-panels>
    </v-card>
    <div style="height: 15px" />
    <log-messages />
    <v-dialog v-model="optionsDialog" max-width="300">
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span>Options</span>
          <v-spacer />
        </v-system-bar>
        <div class="pa-3">
          <v-text-field
            min="0"
            max="10000"
            step="100"
            type="number"
            label="Refresh Interval (ms)"
            :value="refreshInterval"
            @change="refreshInterval = $event"
          />
        </div>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import LogMessages from '@openc3/tool-common/src/components/LogMessages'
import TopBar from '@openc3/tool-common/src/components/TopBar'
export default {
  components: {
    LogMessages,
    TopBar,
  },
  data() {
    return {
      title: 'COSMOS CmdTlmServer',
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
          name: 'Cmd Packets',
          url: '/cmd-packets',
        },
        {
          name: 'Tlm Packets',
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
              command: () => {
                this.optionsDialog = true
              },
            },
          ],
        },
      ],
    }
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
