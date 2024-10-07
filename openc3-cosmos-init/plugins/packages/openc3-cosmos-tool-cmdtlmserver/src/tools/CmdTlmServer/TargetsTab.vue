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
    <v-card-title class="d-flex align-center justify-content-space-between">
      {{ data.length }} Targets
      <v-spacer />
      <v-tooltip location="bottom" :disabled="enterprise && commandAuthority">
        <template v-slot:activator="{ props }">
          <!-- This is a little weird because it captures all the clicks -->
          <!-- including the clicks on the button so the tooltipHandler -->
          <!-- is also the button handler  -->
          <div v-bind="props" @click="tooltipHandler('takeAll')">
            <v-btn
              color="primary"
              class="mr-2"
              :disabled="!commandAuthority"
              data-test="take-all"
            >
              Take All Cmd Authority
              <v-icon end> mdi-account-check </v-icon>
            </v-btn>
          </div>
        </template>
        <span v-if="enterprise">
          Command Authority is disabled.<br />Click the button above to navigate
          to the Admin Console / Scopes Tab.
        </span>
        <span v-else>
          Command Authority is Enterprise Only.<br />Click the button above to
          learn more.
        </span>
      </v-tooltip>
      <v-tooltip location="bottom" :disabled="enterprise && commandAuthority">
        <template v-slot:activator="{ props }">
          <div v-bind="props" @click="tooltipHandler('releaseAll')">
            <v-btn
              color="primary"
              class="mr-2"
              :disabled="!commandAuthority"
              data-test="release-all"
            >
              Release All Cmd Authority
              <v-icon end> mdi-account-cancel </v-icon>
            </v-btn>
          </div>
        </template>
        <span v-if="enterprise">
          Command Authority is disabled.<br />Click the button above to navigate
          to the Admin Console / Scopes Tab.
        </span>
        <span v-else>
          Command Authority is Enterprise Only.<br />Click the button above to
          learn more.
        </span>
      </v-tooltip>
      <v-text-field
        v-model="search"
        label="Search"
        prepend-inner-icon="mdi-magnify"
        clearable
        variant="outlined"
        density="compact"
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
      :items-per-page-options="[10, 20, -1]"
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
          :disabled="!commandAuthority"
        >
          Take
          <v-icon end> mdi-account-check </v-icon>
        </v-btn>
      </template>
      <template v-slot:item.release="{ item }">
        <span v-if="item.name === 'UNKNOWN'">N/A</span>
        <v-btn
          v-if="item.name != 'UNKNOWN'"
          block
          color="primary"
          @click="release(item.name)"
          :disabled="!commandAuthority"
        >
          Release
          <v-icon end> mdi-account-cancel </v-icon>
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
import Cable from '@openc3/tool-common/src/services/cable.js'

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
      cable: new Cable(),
      enterprise: false,
      headers: [
        { title: 'Target Name', value: 'name' },
        { title: 'Interfaces', value: 'interface' },
        {
          title: 'Command Authority Username',
          value: 'username',
        },
        { title: 'Take Command Authority', value: 'take' },
        { title: 'Release Command Authority', value: 'release' },
      ],
      cmdAuth: {},
      commandAuthority: false,
      showUpgradeToEnterpriseDialog: false,
    }
  },
  created: async function () {
    await Api.get('/openc3-api/info').then((response) => {
      if (response.data.enterprise) {
        this.enterprise = true
      }
    })
    // Populate the table once and then just update the data in the
    // update() method. This ensures the data doesn't get deleted
    // on each update which can break takeAll and releaseAll
    this.api.get_target_interfaces().then((info) => {
      for (let x of info) {
        this.data.push({
          name: x[0],
          interface: x[1],
          username: '',
        })
      }
    })
    if (this.enterprise) {
      // Get the initial scope setting
      Api.get(`/openc3-api/scopes/${window.openc3Scope}`).then((response) => {
        if (response.data.command_authority) {
          this.commandAuthority = true
        }
      })
      // Get the initial command authority settings
      Api.get('/openc3-api/cmdauth').then((response) => {
        this.cmdAuth = response.data
      })
      // Create a cable to the SystemEventsChannel so we can maintain
      // state with the backend
      this.cable
        .createSubscription('SystemEventsChannel', window.openc3Scope, {
          received: (data) => {
            this.cable.recordPing()
            this.handleMessages(data)
          },
        })
        .then((systemSubscription) => {
          this.systemSubscription = systemSubscription
        })
    }
  },
  unmounted() {
    if (this.systemSubscription) {
      this.systemSubscription.unsubscribe()
    }
    this.cable.disconnect()
  },
  methods: {
    // Enterprise only
    handleMessages(data) {
      data.forEach((message) => {
        let event = JSON.parse(message['event'])
        switch (event.type) {
          case 'scope':
            if (window.openc3Scope === event.name) {
              this.commandAuthority = event.command_authority
            }
            break
          case 'cmd_auth_take':
            this.cmdAuth[event.name] = event
            break
          case 'cmd_auth_release':
            delete this.cmdAuth[event.name]
            break
          // There is also 'role' but we don't care
        }
      })
    },
    tooltipHandler(method) {
      if (this.enterprise) {
        if (this.commandAuthority) {
          this[method]()
        } else {
          window.open('/tools/admin/scopes', '_blank')
        }
      } else {
        this.showUpgradeToEnterpriseDialog = true
      }
    },
    update() {
      if (this.tabId != this.curTab) return
      this.api.get_target_interfaces().then(async (info) => {
        for (let i = 0; i < info.length; i++) {
          this.data[i].name = info[i][0]
          this.data[i].interface = info[i][1]
          if (this.enterprise) {
            if (this.cmdAuth[this.data[i].name]) {
              this.data[i].username =
                this.cmdAuth[this.data[i].name]['username']
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
      Api.post('/openc3-api/cmdauth/take-all')
    },
    releaseAll() {
      Api.post('/openc3-api/cmdauth/release-all')
    },
  },
}
</script>
