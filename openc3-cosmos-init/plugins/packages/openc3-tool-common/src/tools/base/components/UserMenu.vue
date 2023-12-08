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
    <v-overlay :value="showUserMenu" class="overlay" />
    <v-menu
      v-model="showUserMenu"
      transition="slide-y-transition"
      offset-y
      :close-on-content-click="false"
      :nudge-width="120"
      :nudge-bottom="20"
    >
      <template v-slot:activator="{ on, attrs }">
        <rux-monitoring-icon
          v-bind="attrs"
          v-on="on"
          class="rux-icon"
          icon="person"
          status="off"
          :label="username"
          :sublabel="role()"
        ></rux-monitoring-icon>
      </template>

      <v-card>
        <v-card-text class="text-center">
          <div style="text-align: center; margin: 5px">{{ username }}</div>
          <div v-if="authenticated">
            <v-btn block @click="logout" color="primary"> Logout </v-btn>
          </div>
          <div v-else>
            <v-btn block @click="login" color="primary"> Login </v-btn>
          </div>
          <div
            v-if="username === 'Anonymous'"
            @click="showUpgradeToEnterpriseDialog = true"
            class="pt-2 link"
          >
            Click to learn more about<br />
            COSMOS Enterprise Edition
          </div>
        </v-card-text>
      </v-card>
    </v-menu>
    <upgrade-to-enterprise-dialog
      v-model="showUpgradeToEnterpriseDialog"
    ></upgrade-to-enterprise-dialog>
  </div>
</template>

<script>
import UpgradeToEnterpriseDialog from '../../../components/UpgradeToEnterpriseDialog'

export default {
  components: {
    UpgradeToEnterpriseDialog,
  },
  props: {
    size: {
      type: [String, Number],
      default: 26,
    },
  },
  data: function () {
    let user = OpenC3Auth.user()
    return {
      showUserMenu: false,
      authenticated: !!localStorage.openc3Token,
      username: user['name'],
      showUpgradeToEnterpriseDialog: false,
    }
  },
  methods: {
    logout: function () {
      OpenC3Auth.logout()
    },
    login: function () {
      OpenC3Auth.login(location.href)
    },
    role: function () {
      if (this.username === 'Anonymous') {
        return 'Admin'
      } else {
        return [
          ...new Set( // Use Set to remove duplicates
            OpenC3Auth.userroles()
              // Roles are like ALLSCOPES__custom DEFAULT__viewer
              // but it also includes default-roles-openc3
              .map((element) => element.split('__')[1])
              .filter(Boolean), // Get rid of non roles (default-roles-openc3)
          ),
        ]
          .map((element) => self.capitalize(element))
          .sort()
          .join(', ')
      }
    },
    capitalize(string) {
      return string.charAt(0).toUpperCase() + string.slice(1)
    },
  },
}
</script>

<style scoped>
.link {
  cursor: pointer;
}
.overlay {
  height: 100vh;
  width: 100vw;
}
</style>
