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
          :label="name"
          :sublabel="roles()"
        ></rux-monitoring-icon>
      </template>

      <v-card>
        <v-card-text class="text-center">
          <div style="text-align: center; margin: 5px">
            {{ name }}
          </div>
          <div v-if="name !== 'Anonymous'">
            <div class="roles">Username: {{ username }}</div>
            <div class="pb-3 roles">Roles: {{ roles() }}</div>
          </div>
          <div v-if="authenticated">
            <v-btn block @click="logout" color="primary"> Logout </v-btn>
            <div class="pa-3" v-if="name !== 'Anonymous'">
              <v-row class="pt-3 user-title">Other Active Users:</v-row>
              <v-row
                v-for="(user, index) in activeUsers"
                :key="index"
                class="user"
              >
                {{ user }}
              </v-row>
            </div>
          </div>
          <div v-else>
            <v-btn block @click="login" color="primary"> Login </v-btn>
          </div>
          <div
            v-if="name === 'Anonymous'"
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
      reason="Enterprise has individual users with RBAC"
    ></upgrade-to-enterprise-dialog>
  </div>
</template>

<script>
import Api from '../../../services/api'
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
      name: user['name'],
      // preferred_username is returned by the token (see authorization.rb)
      username: user['preferred_username'],
      showUpgradeToEnterpriseDialog: false,
      activeUsers: ['None'],
    }
  },
  watch: {
    // Whenever we show the user menu, refresh the list of active users
    showUserMenu: function (newValue, oldValue) {
      if (newValue === true) {
        if (this.name !== 'Anonymous') {
          Api.get('/openc3-api/users/active').then((response) => {
            this.activeUsers = response.data.filter(
              (item) => !item.includes(this.name),
            )
            if (this.activeUsers.length === 0) {
              this.activeUsers = ['None']
            }
          })
        }
      }
    },
  },
  methods: {
    logout: function () {
      OpenC3Auth.logout()
      Api.put(`/openc3-api/users/logout/${this.username}`)
    },
    login: function () {
      OpenC3Auth.login(location.href)
    },
    roles: function () {
      if (this.name === 'Anonymous') {
        return 'Admin'
      } else {
        return OpenC3Auth.userroles()
          .map((element) => this.capitalize(element))
          .sort()
          .join(', ')
      }
    },
    capitalize: function (string) {
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
.user-title {
  font-weight: bold;
}
.user,
.roles {
  font-size: 0.8rem;
}
</style>
