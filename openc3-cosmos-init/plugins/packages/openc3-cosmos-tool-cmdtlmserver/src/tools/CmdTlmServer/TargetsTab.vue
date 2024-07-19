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
  <v-card>
    <v-card-title>
      {{ data.length }} Targets
      <v-spacer />
      <v-tooltip bottom :disabled="enterprise">
        <template v-slot:activator="{ on, attrs }">
          <div
            v-on="on"
            v-bind="attrs"
            @click="showUpgradeToEnterpriseDialog = true"
          >
            <v-btn
              color="primary"
              class="mr-2"
              @click="takeAll()"
              :disabled="!enterprise"
            >
              Take All Cmd Authority
              <v-icon right> mdi-account-check </v-icon>
            </v-btn>
          </div>
        </template>
        <span>
          Command Authority is Enterprise Only.<br />Click the button above to
          learn more.
        </span>
      </v-tooltip>
      <v-tooltip bottom :disabled="enterprise">
        <template v-slot:activator="{ on, attrs }">
          <div
            v-on="on"
            v-bind="attrs"
            @click="showUpgradeToEnterpriseDialog = true"
          >
            <v-btn
              color="primary"
              class="mr-2"
              @click="releaseAll()"
              :disabled="!enterprise"
            >
              Release All Cmd Authority
              <v-icon right> mdi-account-cancel </v-icon>
            </v-btn>
          </div>
        </template>
        Command Authority is Enterprise Only.<br />Click the button above to
        learn more.
      </v-tooltip>
      <v-text-field
        v-model="search"
        label="Search"
        prepend-inner-icon="mdi-magnify"
        clearable
        outlined
        dense
        single-line
        hide-details
        class="search"
      />
    </v-card-title>
    <v-data-table
      :headers="headers"
      :items="data"
      :search="search"
      :items-per-page="10"
      :footer-props="{ itemsPerPageOptions: [10, 20, -1] }"
      calculate-widths
      multi-sort
      data-test="targets-table"
    >
      <template v-slot:item.take="{ item }">
        <span v-if="item.name === 'UNKNOWN'">N/A</span>
        <v-btn
          v-if="item.name != 'UNKNOWN'"
          block
          color="primary"
          @click="take(item.name)"
          :disabled="!enterprise"
        >
          Take
          <v-icon right> mdi-account-check </v-icon>
        </v-btn>
      </template>
      <template v-slot:item.release="{ item }">
        <span v-if="item.name === 'UNKNOWN'">N/A</span>
        <v-btn
          v-if="item.name != 'UNKNOWN'"
          block
          color="primary"
          @click="release(item.name)"
          :disabled="!enterprise"
        >
          Release
          <v-icon right> mdi-account-cancel </v-icon>
        </v-btn>
      </template>
    </v-data-table>
    <upgrade-to-enterprise-dialog
      v-model="showUpgradeToEnterpriseDialog"
      reason="Command Authority is Enterprise Only"
    ></upgrade-to-enterprise-dialog>
  </v-card>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'
import Updater from './Updater'
import UpgradeToEnterpriseDialog from '@openc3/tool-common/src/components/UpgradeToEnterpriseDialog'

export default {
  components: {
    UpgradeToEnterpriseDialog,
  },
  mixins: [Updater],
  props: {
    tabId: Number,
    curTab: Number,
  },
  data() {
    return {
      search: '',
      data: [],
      enterprise: false,
      headers: [
        { text: 'Target Name', value: 'name' },
        { text: 'Interfaces', value: 'interface' },
        {
          text: 'Command Authority Username',
          value: 'username',
        },
        { text: 'Take Command Authority', value: 'take' },
        { text: 'Release Command Authority', value: 'release' },
      ],
      showUpgradeToEnterpriseDialog: false,
    }
  },
  created: async function () {
    await Api.get('/openc3-api/info').then((response) => {
      if (response.data.enterprise) {
        this.enterprise = true
      }
    })
    this.api.get_target_interfaces().then((info) => {
      for (let x of info) {
        this.data.push({
          name: x[0],
          interface: x[1],
          username: 'Anonymous',
        })
      }
    })
  },
  methods: {
    update() {
      if (this.tabId != this.curTab) return
      this.api.get_target_interfaces().then(async (info) => {
        let cmdauth = null
        if (this.enterprise) {
          let response = await Api.get('/openc3-api/cmdauth')
          cmdauth = response.data
        }

        for (let i = 0; i < info.length; i++) {
          this.data[i].name = info[i][0]
          this.data[i].interface = info[i][1]
          if (this.enterprise) {
            if (cmdauth[this.data[i].name]) {
              this.data[i].username = cmdauth[this.data[i].name]['username']
            } else {
              this.data[i].username = ''
            }
          }
        }
      })
    },
    take(target_name) {
      Api.post('/openc3-api/cmdauth/take', {
        data: {
          target_name: target_name,
        },
      })
    },
    release(target_name) {
      Api.post('/openc3-api/cmdauth/release', {
        data: {
          target_name: target_name,
        },
      })
    },
    takeAll() {
      Api.post('/openc3-api/cmdauth/take-all', {
        data: {
          target_names: this.data.map((target) => target.name),
        },
      })
    },
    releaseAll() {
      Api.post('/openc3-api/cmdauth/release-all', {
        data: {
          target_names: this.data.map((target) => target.name),
        },
      })
    },
  },
}
</script>
