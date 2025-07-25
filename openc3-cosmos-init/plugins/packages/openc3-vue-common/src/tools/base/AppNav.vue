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
      id="openc3-nav-drawer"
      :model-value="drawer"
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
          size="small"
          :href="tool.url"
          class="fixcenter"
          color="primary"
          @click.prevent="() => navigateToUrl(tool.url)"
        >
          Admin Console
        </v-btn>
      </div>
      <v-divider />
      <v-treeview
        :items="items"
        :opened="initiallyOpen"
        item-value="name"
        density="compact"
        open-on-click
      >
        <!-- Beginning Icon -->
        <template #prepend="{ item }">
          <template v-if="item.icon">
            <a
              v-if="item.window === 'INLINE'"
              :href="item.url"
              @click.prevent="() => navigateToUrl(item.url)"
            >
              <v-icon class="mr-2"> {{ item.icon }} </v-icon>
            </a>
            <a v-else :href="item.url">
              <v-icon class="mr-2"> {{ item.icon }} </v-icon>
            </a>
          </template>
        </template>

        <!-- Link Text -->
        <template #title="{ item }">
          <!-- Category has no Icon -->
          <a
            v-if="!item.icon"
            :href="item.url"
            @click.prevent="() => navigateToUrl(item.url)"
          >
            {{ item.name }}
          </a>
          <template v-else>
            <!-- Tool Link -->
            <a
              v-if="item.window === 'INLINE'"
              :href="item.url"
              @click.prevent="() => navigateToUrl(item.url)"
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
        <template #append="{ item }">
          <a v-if="item.icon" :href="newTabUrl(item)" target="_blank">
            <v-icon>mdi-open-in-new</v-icon>
          </a>
        </template>
      </v-treeview>
    </v-navigation-drawer>
    <v-app-bar v-if="!chromeless" id="openc3-app-toolbar">
      <v-row class="flex-nowrap" justify="space-between" no-gutters>
        <v-col align-self="start">
          <v-row class="flex-nowrap">
            <rux-icon
              class="ml-3 mr-2 pa-2"
              size="small"
              icon="apps"
              @click="drawer = !drawer"
            ></rux-icon>
            <span id="openc3-menu" />
          </v-row>
        </v-col>
        <v-col>
          <v-row class="clock flex-nowrap mt-0">
            <rux-clock
              v-if="!astro.hideClock"
              date-in=""
              :timezone="astroTimeZone"
            />
          </v-row>
        </v-col>
        <v-col align-self="center" class="mt-2">
          <v-row class="flex-nowrap">
            <v-spacer />
            <div
              v-if="contextTag.text"
              class="context-tag mr-2 mt-4"
              :style="{ 
                color: contextTag.fontColor,
                backgroundColor: contextTag.backgroundColor
              }"
            >
              {{ contextTag.text }}
            </div>
            <scope-selector class="mr-6 mt-4" />
            <notifications class="mr-6" data-test="notifications" />
            <user-menu class="mr-6" /> </v-row
        ></v-col>
      </v-row>
    </v-app-bar>
    <upgrade-to-enterprise-dialog
      v-model="showUpgradeToEnterpriseDialog"
      reason="Enterprise adds Calendar and Autonomic"
    />
  </div>
</template>

<script>
import { navigateToUrl, registerApplication, start } from 'single-spa'
import { Api, OpenC3Api } from '@openc3/js-common/services'
import { UpgradeToEnterpriseDialog } from '@/components'
import Notifications from './Notifications.vue'
import ScopeSelector from './ScopeSelector.vue'
import UserMenu from './UserMenu.vue'

export default {
  components: {
    Notifications,
    ScopeSelector,
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
      timeZone: 'local',
      subtitle: null,
      // Update AstroSettings.vue when changing this
      astro: {
        hideClock: false,
      },
      items: [],
      drawer: true,
      appNav: {},
      logo: '/img/logo.png',
      initiallyOpen: [],
      showUpgradeToEnterpriseDialog: false,
      chromeless: null,
      contextTag: {
        text: null,
        fontColor: null,
        backgroundColor: null,
      },
    }
  },
  computed: {
    // a computed getter
    shownTools: function () {
      let result = {}
      for (let key of Object.keys(this.appNav)) {
        if (this.appNav[key].shown && this.appNav[key].category !== 'Admin') {
          result[key] = this.appNav[key]
        }
      }
      return result
    },
    adminTools: function () {
      let result = {}
      for (let key of Object.keys(this.appNav)) {
        if (this.appNav[key].shown && this.appNav[key].category === 'Admin') {
          result[key] = this.appNav[key]
        }
      }
      return result
    },
    astroTimeZone: function () {
      if (this.timeZone === 'local') {
        return Intl.DateTimeFormat().resolvedOptions().timeZone
      }
      return this.timeZone
    },
  },
  created() {
    const urlParams = new URLSearchParams(window.location.search)
    this.chromeless = urlParams.get('chromeless')

    this.api
      .get_setting('astro')
      .then((response) => {
        if (response) {
          // The response is an object with settings
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
    this.api
      .get_setting('context_tag')
      .then((response) => {
        if (response) {
          const parsed = JSON.parse(response)
          this.contextTag = {
            text: parsed.text,
            fontColor: parsed.fontColor,
            backgroundColor: parsed.backgroundColor,
          }
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
        for (let key of Object.keys(this.appNav)) {
          if (this.appNav[key].shown) {
            if (
              this.appNav[key].category &&
              this.appNav[key].category !== 'Admin'
            ) {
              // TODO: Make this initiallyOpen configurable like with a CATEGORY parameter?
              if (!this.initiallyOpen.includes(this.appNav[key].category)) {
                this.initiallyOpen.push(this.appNav[key].category)
              }
              const result = this.items.filter(
                (item) => item.name === this.appNav[key].category,
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
          if (this.appNav[key].inline_url) {
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

        // Check every minute if we need to update our token
        setInterval(() => {
          OpenC3Auth.updateToken(120).then(function (refreshed) {
            if (refreshed) {
              OpenC3Auth.setTokens()
            }
          })
        }, 60000)
      },
    )
  },
  methods: {
    navigateToUrl,
    newTabUrl(tool) {
      let url = null
      try {
        if (tool.url[0] == '/' && tool.url[1] != '/') {
          url = new URL(tool.url, window.location.origin)
        } else {
          url = new URL(tool.url)
        }
        url.searchParams.set('scope', window.openc3Scope)
      } catch (error) {
        window.$cosmosNotify.serious({
          title: `Invalid URL '${tool.url}' for tool ${tool.name}`,
          message: error.message,
        })
        url.href = '/'
      }
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
/* Custom CSS as the button color override is not possible. Styling to be close to Astro App States */
.context-tag {
  border-radius: 4px;
  height: 38px;
  font-family: var(--font-body-2-font-family);
  padding: .1875rem .5rem;
  display: flex;
  align-items: center;
  justify-content: center;
}
</style>

<style>
/* Classification banners */
#openc3-nav-drawer {
  margin-bottom: var(--classification-height-bottom);
}
#openc3-nav-drawer,
header {
  margin-top: var(--classification-height-top);
}
#openc3-app-toolbar {
  top: var(--classification-height-top);
}
#openc3-nav-drawer .v-navigation-drawer__content {
  height: calc(
    100% - var(--classification-height-top) -
      var(--classification-height-bottom)
  );
}
/* END classification banners */

/* Remove the padding on root level nodes since we removed the expand icon */
#openc3-nav-drawer
  .v-treeview
  > .v-treeview-item
  > .v-treeview-item__root
  > .v-treeview-item__level {
  width: 0px;
  padding-left: 0px;
}
#openc3-nav-drawer
  .v-treeview
  > .v-treeview-item
  > .v-treeview-item__root
  > .v-treeview-item__toggle {
  width: 0px;
  padding-left: 0px;
}
#openc3-nav-drawer .v-treeview > .v-treeview-group > .v-list-group__header {
  padding-left: 30px;
}
#openc3-nav-drawer .v-treeview > .v-treeview-group > .v-list-group__items {
  --indent-padding: 30px;
}
#openc3-nav-drawer .v-treeview .v-treeview-item {
  padding-left: 0px;
}
#openc3-nav-drawer .v-treeview .v-treeview-item .v-list-item-action {
  width: 0px;
  padding-left: 0px;
}
#openc3-nav-drawer
  .v-treeview-item__children
  div.v-treeview-item__level:nth-child(1) {
  width: 0px;
  padding-left: 0px;
}
</style>
