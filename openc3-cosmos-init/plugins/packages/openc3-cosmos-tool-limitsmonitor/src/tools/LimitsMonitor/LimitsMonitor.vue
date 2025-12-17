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
    <limits-control
      ref="control"
      :key="renderKey"
      v-model="ignored"
      :time-zone="timeZone"
    />
    <div style="height: 15px" />
    <limits-events :time-zone="timeZone" />
    <!-- Note we're using v-if here so it gets re-created each time and refreshes the list -->
    <open-config-dialog
      v-if="openConfig"
      v-model="openConfig"
      :config-key="configKey"
      @success="openConfiguration"
    />
    <!-- Note we're using v-if here so it gets re-created each time and refreshes the list -->
    <save-config-dialog
      v-if="saveConfig"
      v-model="saveConfig"
      :config-key="configKey"
      @success="saveConfiguration"
    />
    <v-dialog
      v-model="limitsSetDialog"
      max-width="650"
      persistent
      @keydown.esc="limitsSetDialog = false"
    >
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span>Change Limits Set</span>
          <v-spacer />
        </v-toolbar>
        <v-card-text class="mt-6">
          <span style="display: block">
            The Limits Set is a global option which changes the Limits Set
            across all tools.
          </span>
          <span style="display: block">
            NOTE: Changing this option clears the current list and recalculates
            based on the new set.
          </span>
          <v-select
            v-model="currentLimitsSet"
            label="Limits Set"
            :items="limitsSets"
            density="compact"
            variant="outlined"
            data-test="limits-set"
            hide-details
            class="mt-3"
            style="max-width: 200px"
          />
        </v-card-text>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn variant="outlined" @click="limitsSetDialog = false">
            Cancel
          </v-btn>
          <v-btn variant="flat" @click="setLimitsSet"> Ok </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'
import {
  Config,
  OpenConfigDialog,
  SaveConfigDialog,
  TopBar,
} from '@openc3/vue-common/components'
import LimitsControl from './LimitsControl'
import LimitsEvents from './LimitsEvents'

export default {
  components: {
    LimitsControl,
    LimitsEvents,
    TopBar,
    OpenConfigDialog,
    SaveConfigDialog,
  },
  mixins: [Config],
  data() {
    return {
      title: 'Limits Monitor',
      configKey: 'limits_monitor',
      api: new OpenC3Api(),
      timeZone: 'local',
      renderKey: 0,
      ignored: [],
      openConfig: false,
      saveConfig: false,
      limitsSets: [],
      currentLimitsSet: null,
      currentSetRefreshInterval: null,
      limitsSetDialog: false,
      menus: [
        {
          label: 'File',
          items: [
            {
              label: 'Show Ignored',
              icon: 'mdi-magnify-close',
              command: () => {
                this.$refs.control.showIgnored()
              },
            },
            {
              label: 'Change Limits Set',
              icon: 'mdi-swap-horizontal',
              command: () => {
                this.limitsSetDialog = true
              },
            },
            {
              divider: true,
            },
            {
              label: 'Open Configuration',
              icon: 'mdi-folder-open',
              command: () => {
                this.openConfig = true
              },
            },
            {
              label: 'Save Configuration',
              icon: 'mdi-content-save',
              command: () => {
                this.saveConfig = true
              },
            },
            {
              label: 'Reset Configuration',
              icon: 'mdi-monitor-shimmer',
              command: () => {
                this.ignored = []
                this.resetConfigBase()
                this.renderKey++
              },
            },
          ],
        },
      ],
    }
  },
  created() {
    this.api.get_limits_sets().then((sets) => {
      this.limitsSets = sets
    })
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
  mounted: function () {
    // Called like /tools/limitsmonitor?config=ignored
    if (this.$route.query && this.$route.query.config) {
      this.openConfiguration(this.$route.query.config, true) // routed
    } else {
      let config = this.loadDefaultConfig()
      // Only apply the config if it's not an empty object (config does not exist)
      if (JSON.stringify(config) !== '{}') {
        this.ignored = config
        this.renderKey++
      }
    }
  },
  unmounted: function () {
    clearInterval(this.currentSetRefreshInterval)
  },
  methods: {
    setLimitsSet: function () {
      this.api.set_limits_set(this.currentLimitsSet)
      this.limitsSetDialog = false
      this.renderKey++ // Trigger re-render
    },
    openConfiguration: function (name, routed = false) {
      this.openConfigBase(name, routed, (config) => {
        this.ignored = config
        this.renderKey++ // Trigger re-render
      })
    },
    saveConfiguration: function (name) {
      this.saveConfigBase(name, this.ignored)
    },
  },
}
</script>
