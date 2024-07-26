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
    <v-navigation-drawer
      v-if="!chromeless"
      v-model="drawer"
      app
      id="openc3-nav-drawer"
    >
      <img :src="logo" class="logo" alt="OpenC3" />
      <div class="cosmos" @click="showUpgradeToEnterpriseDialog = true">
        COSMOS
      </div>
      <div style="text-align: center; font-size: 18pt">
        {{ subtitle }}
      </div>
      <div v-for="(tool, name) in adminTools" :key="name" class="ma-3">
        <v-btn
          block
          small
          :href="tool.url"
          onclick="singleSpaNavigate(event)"
          class="fixcenter"
          color="primary"
        >
          Admin Console
        </v-btn>
      </div>
      <v-divider />
      <v-treeview
        :items="items"
        :open="initiallyOpen"
        item-key="name"
        dense
        open-on-click
        expand-icon=""
      >
        <!-- Beginning Icon -->
        <template v-slot:prepend="{ item, open }">
          <v-icon v-if="!item.icon">
            {{ open ? 'mdi-chevron-down' : 'mdi-chevron-right' }}
          </v-icon>
          <template v-else>
            <a
              v-if="item.window === 'INLINE'"
              :href="item.url"
              onclick="singleSpaNavigate(event)"
            >
              <v-icon> {{ item.icon }} </v-icon>
            </a>
            <a v-else :href="item.url">
              <v-icon> {{ item.icon }} </v-icon>
            </a>
          </template>
        </template>

        <!-- Link Text -->
        <template v-slot:label="{ item }">
          <!-- Category has no Icon -->
          <a
            v-if="!item.icon"
            :href="item.url"
            onclick="singleSpaNavigate(event)"
          >
            {{ item.name }}
          </a>
          <template v-else>
            <!-- Tool Link -->
            <a
              v-if="item.window === 'INLINE'"
              :href="item.url"
              onclick="singleSpaNavigate(event)"
            >
              {{ item.name }}
            </a>
            <a
              v-else-if="item.window === 'IFRAME'"
              :href="
                '/tools/iframe?title=' +
                encodeURIComponent(item.name) +
                '&url=' +
                item.url
              "
            >
              {{ item.name }}
            </a>
            <a v-else-if="item.window === 'SAME'" :href="item.url">
              {{ item.name }}
            </a>
            <a v-else :href="item.url" target="_blank">
              <!-- item.window === 'NEW' -->
              {{ item.name }}
            </a>
          </template>
        </template>

        <!-- New Tab Link -->
        <template v-slot:append="{ item }">
          <a v-if="item.icon" :href="newTabUrl(item)" target="_blank">
            <v-icon>mdi-open-in-new</v-icon>
          </a>
        </template>
      </v-treeview>
    </v-navigation-drawer>
    <v-app-bar app v-if="!chromeless" id="openc3-app-toolbar">
      <v-row
        class="flex-nowrap"
        justify="space-between"
        no-gutters
        style="margin-top: 20px"
      >
        <v-col align-self="center">
          <v-row class="flex-nowrap">
            <rux-icon
              class="mr-2 pa-2"
              size="small"
              icon="apps"
              @click="drawer = !drawer"
            ></rux-icon>
            <span id="openc3-menu" />
          </v-row>
        </v-col>
        <v-col style="margin: auto">
          <rux-clock
            class="clock"
            v-if="!astro.hideClock"
            date-in=""
          ></rux-clock>
        </v-col>
        <v-col align-self="center">
          <v-row class="flex-nowrap" style="margin-top: 10px">
            <v-spacer />
            <scope-selector class="mr-6 mt-4" />
            <notifications class="mr-6" data-test="notifications" />
            <user-menu class="mr-3" /> </v-row
        ></v-col>
      </v-row>
    </v-app-bar>
    <upgrade-to-enterprise-dialog
      v-model="showUpgradeToEnterpriseDialog"
      reason="Enterprise adds Calendar and Autonomic"
    ></upgrade-to-enterprise-dialog>
  </div>
</template>

<script>
import { OpenC3Api } from '../../services/openc3-api'
import Api from '../../services/api'
import logo from '../../../public/img/logo.png'
import { registerApplication, start } from 'single-spa'
import ScopeSelector from './components/ScopeSelector.vue'
import Notifications from './components/Notifications.vue'
import UserMenu from './components/UserMenu.vue'
import UpgradeToEnterpriseDialog from '../../components/UpgradeToEnterpriseDialog'
export default {
  components: {
    ScopeSelector,
    Notifications,
    UserMenu,
    UpgradeToEnterpriseDialog,
  },
  props: {
    edition: {
      type: String,
      default: '',
    },
  },
  data() {
    return {
      api: new OpenC3Api(),
      subtitle: null,
      astro: {
        hideClock: false,
      },
      items: [],
      drawer: true,
      appNav: {},
      logo: logo,
      initiallyOpen: [],
      showUpgradeToEnterpriseDialog: false,
      chromeless: this.$route.query.chromeless,
    }
  },
  computed: {
    // a computed getter
    shownTools: function () {
      let result = {}
      for (var key of Object.keys(this.appNav)) {
        if (this.appNav[key].shown && this.appNav[key].category !== 'Admin') {
          result[key] = this.appNav[key]
        }
      }
      return result
    },
    adminTools: function () {
      let result = {}
      for (var key of Object.keys(this.appNav)) {
        if (this.appNav[key].shown && this.appNav[key].category === 'Admin') {
          result[key] = this.appNav[key]
        }
      }
      return result
    },
  },
  created() {
    this.api
      .get_setting('astro')
      .then((response) => {
        if (response) {
          this.astro = JSON.parse(response)
        }
      })
      .catch((error) => {
        // Do nothing
      })
    this.api
      .get_setting('subtitle')
      .then((response) => {
        if (response) {
          this.subtitle = response
        }
      })
      .catch((error) => {
        // Do nothing
      })
    // Tools are global and are always installed into the DEFAULT scope
    Api.get('/openc3-api/tools/all', { params: { scope: 'DEFAULT' } }).then(
      (response) => {
        this.appNav = response.data

        let id = 1
        // Register apps and start single-spa
        for (var key of Object.keys(this.appNav)) {
          if (this.appNav[key].shown) {
            if (
              this.appNav[key].category &&
              this.appNav[key].category !== 'Admin'
            ) {
              // TODO: Make this initiallyOpen configurable like with a CATEGORY parameter?
              this.initiallyOpen.push(this.appNav[key].category)
              const result = this.items.filter(
                (item) => item.name === this.appNav[key].category
              )
              if (result.length === 0) {
                // Create category and first item
                this.items.push({
                  id: id,
                  name: this.appNav[key].category,
                  children: [
                    {
                      id: id + 1,
                      name: this.appNav[key].name,
                      icon: this.appNav[key].icon,
                      url: this.appNav[key].url,
                      inline_url: this.appNav[key].inline_url,
                      window: this.appNav[key].window,
                    },
                  ],
                })
                id++
              } else {
                // Add to existing category
                result[0].children.push({
                  id: id,
                  name: this.appNav[key].name,
                  icon: this.appNav[key].icon,
                  url: this.appNav[key].url,
                  inline_url: this.appNav[key].inline_url,
                  window: this.appNav[key].window,
                })
              }
            } else if (!this.appNav[key].category) {
              // Create category
              this.items.push({
                id: id,
                name: this.appNav[key].name,
                icon: this.appNav[key].icon,
                url: this.appNav[key].url,
                inline_url: this.appNav[key].inline_url,
                window: this.appNav[key].window,
              })
            }
            id++
          }
          if (
            this.appNav[key].inline_url &&
            this.appNav[key].window === 'INLINE'
          ) {
            if (
              this.appNav[key].folder_name &&
              this.appNav[key].folder_name !== 'base'
            ) {
              let folder_name = this.appNav[key].folder_name
              let name = '@openc3/tool-' + folder_name
              registerApplication({
                name: name,
                app: () => System.import(name),
                activeWhen: ['/tools/' + folder_name],
              })
            }
          }
        }
        start({
          urlRerouteOnly: true,
        })

        // Redirect some base paths to the first tool
        if (
          window.location.pathname == '/' ||
          window.location.pathname == '/tools' ||
          window.location.pathname == '/tools/'
        ) {
          for (var key of Object.keys(this.shownTools)) {
            if (this.appNav[key].shown) {
              history.replaceState(null, '', this.appNav[key].url)
              break
            }
          }
        }

        // Check every minute if we need to update our token
        setInterval(() => {
          OpenC3Auth.updateToken(120).then(function (refreshed) {
            if (refreshed) {
              OpenC3Auth.setTokens()
            }
          })
        }, 60000)
      }
    )
  },
  methods: {
    newTabUrl(tool) {
      let url = null
      if (tool.url[0] == '/' && tool.url[1] != '/') {
        url = new URL(tool.url, window.location.origin)
      } else {
        url = new URL(tool.url)
      }
      url.searchParams.set('scope', window.openc3Scope)
      return url.href
    },
  },
}
</script>

<style scoped>
.clock {
  margin-top: 10px;
  justify-content: center;
}
.logo {
  display: block;
  margin-left: auto;
  margin-right: auto;
}
.cosmos {
  cursor: pointer;
  text-align: center;
  font-size: 18pt;
}
div a {
  color: white;
  font-size: 16px;
  display: block;
  height: 100%;
  width: 100%;
}
a.fixcenter {
  display: flex;
}
#openc3-app-toolbar .top-bar-divider-full-height {
  margin: -4px 4px;
  min-height: calc(100% + 8px);
}
</style>
<style>
/* Remove the padding on root level nodes since we removed the expand icon */
#openc3-nav-drawer
  .v-treeview
  > .v-treeview-node
  > .v-treeview-node__root
  > .v-treeview-node__level {
  width: 0px;
}
#openc3-nav-drawer
  .v-treeview
  > .v-treeview-node
  > .v-treeview-node__root
  > .v-treeview-node__toggle {
  width: 0px;
}
#openc3-nav-drawer
  .v-treeview-node__children
  div.v-treeview-node__level:nth-child(1) {
  width: 0px;
}
</style>
