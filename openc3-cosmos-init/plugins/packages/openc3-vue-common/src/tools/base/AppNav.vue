<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
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
      v-model="drawer"
    >
      <img :src="logo" class="logo" alt="OpenC3" />
      <img
        :src="wordmark"
        class="cosmos-wordmark"
        alt="COSMOS"
        @click="showUpgradeToEnterpriseDialog = true"
      />
      <div class="cosmos">
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
        :activated="activeItems"
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
        <v-col style="margin: auto">
          <v-row class="clock flex-nowrap mt-0">
            <rux-clock
              v-if="!astro.hideClock"
              date-in=""
              :timezone="astroTimeZone"
            />
            <v-tooltip v-if="itemClockRunning" location="bottom">
              <template #activator="{ props }">
                <!-- Bind the class on a wrapper because Vue replaces the
                whole class attribute on change which would remove the
                'hydrated' class Stencil uses to make rux-clock visible -->
                <div
                  v-bind="props"
                  class="item-clock ml-4"
                  :class="{ 'item-clock-error': itemClockError }"
                  data-test="item-clock"
                >
                  <!-- Static so the clock only moves when the item updates.
                  rux-clock hardcodes the 'Time' label so hide it and render
                  our own title styled like the Astro AOS / LOS labels -->
                  <rux-clock
                    static
                    hide-date
                    hide-timezone
                    hide-labels
                    :date-in="itemClockDate"
                    :timezone="astroTimeZone"
                  />
                  <div
                    v-if="astro.showItemClockTitle"
                    class="item-clock-title"
                    data-test="item-clock-title"
                  >
                    {{ itemClockLabel }}
                  </div>
                </div>
              </template>
              <div>{{ itemClockFullName }}</div>
              <div v-if="itemClockError">{{ itemClockError }}</div>
            </v-tooltip>
          </v-row>
        </v-col>
        <v-col align-self="center" class="mt-2">
          <v-row class="flex-nowrap">
            <v-spacer />
            <context-tag />
            <div>
              <scope-selector class="mr-6 mt-4" />
            </div>
            <notifications class="mr-6" data-test="notifications" />
            <user-menu class="mr-6" />
          </v-row>
        </v-col>
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
import {
  Api,
  OpenC3Api,
  isAuthRequiredError,
  logUnlessAuthRequired,
} from '@openc3/js-common/services'
import { UpgradeToEnterpriseDialog } from '@/components'
import { getCachedSetting } from '@/util'
import Notifications from './Notifications.vue'
import ScopeSelector from './ScopeSelector.vue'
import UserMenu from './UserMenu.vue'
import ContextTag from './ContextTag.vue'

export default {
  components: {
    Notifications,
    ScopeSelector,
    UserMenu,
    UpgradeToEnterpriseDialog,
    ContextTag,
  },
  props: {
    edition: {
      type: String,
      default: '',
    },
  },
  data() {
    return {
      timeZone: 'local',
      subtitle: null,
      // Update AstroSettings.vue when changing this
      astro: {
        hideClock: false,
        showItemClock: false,
        showItemClockTitle: true,
        itemClockTitle: '',
        itemClock: {
          targetName: null,
          packetName: null,
          itemName: null,
        },
      },
      itemClockRunning: false,
      // Until we get a good value display the epoch rather than an empty
      // date-in which would make rux-clock show the current time
      itemClockDate: new Date(0).toISOString(),
      itemClockError: null,
      itemClockInterval: null,
      items: [],
      drawer: true,
      appNav: {},
      logo: '/img/logo.png',
      wordmark: '/img/COSMOS.svg',
      initiallyOpen: [],
      activeItems: [],
      showUpgradeToEnterpriseDialog: false,
      chromeless: null,
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
    itemClockFullName: function () {
      const item = this.astro.itemClock
      return `${item.targetName} ${item.packetName} ${item.itemName}`
    },
    itemClockLabel: function () {
      const item = this.astro.itemClock
      return (
        this.astro.itemClockTitle || `${item.targetName} ${item.packetName}`
      )
    },
  },
  created() {
    const urlParams = new URLSearchParams(window.location.search)
    this.chromeless = urlParams.get('chromeless')

    // These three go out as a single batched get_settings request
    getCachedSetting('astro')
      .then((response) => {
        if (response) {
          // The response is an object with settings
          this.astro = { ...this.astro, ...JSON.parse(response) }
          this.startItemClock()
        }
      })
      .catch((error) => {
        // Do nothing - malformed setting, keep the defaults
      })
    getCachedSetting('subtitle').then((response) => {
      if (response) {
        this.subtitle = response
      }
    })
    getCachedSetting('time_zone').then((response) => {
      if (response) {
        this.timeZone = response
      }
    })
    // Tools are global and are always installed into the DEFAULT scope.
    // This endpoint requires no authorization and the nav has to render even
    // when we have no token (the login page mounts it too), so don't let the
    // auth guard block the request.
    Api.get('/openc3-api/tools/all', {
      params: { scope: 'DEFAULT' },
      optionalAuth: true,
    })
      .then((response) => {
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
        this.updateActiveItem()

        // Check every minute if we need to update our token
        setInterval(() => {
          OpenC3Auth.updateToken(120)
            .then(function (refreshed) {
              if (refreshed) {
                OpenC3Auth.setTokens()
              }
            })
            // An AuthRequiredError means we have no token and are being
            // redirected to login, so there's nothing to do here. Anything
            // else (network, unexpected auth failure) still gets logged.
            .catch(logUnlessAuthRequired)
        }, 60000)
      })
      .catch(logUnlessAuthRequired)
  },
  mounted() {
    globalThis.addEventListener(
      'single-spa:routing-event',
      this.updateActiveItem,
    )
  },
  beforeUnmount() {
    clearInterval(this.itemClockInterval)
    globalThis.removeEventListener(
      'single-spa:routing-event',
      this.updateActiveItem,
    )
  },
  methods: {
    navigateToUrl,
    startItemClock() {
      const item = this.astro.itemClock
      if (
        this.chromeless ||
        !this.astro.showItemClock ||
        !item?.targetName ||
        !item?.packetName ||
        !item?.itemName
      ) {
        return
      }
      const api = new OpenC3Api()
      const key = `${item.targetName}__${item.packetName}__${item.itemName}__CONVERTED`
      this.itemClockRunning = true
      // Skip ticks while a request is outstanding so a slow API doesn't
      // pile up concurrent requests
      let inFlight = false
      const poll = () => {
        if (inFlight) {
          return
        }
        inFlight = true
        api
          .get_tlm_values([key], 30, null, null, null, {
            // Don't pop an error notification every second if the item
            // was deleted or the API is unavailable
            'Ignore-Errors': '404 500',
          })
          .then((data) => {
            this.itemClockDate = this.parseItemClockValue(data?.[0]?.[0])
            this.itemClockError = null
          })
          .catch((error) => {
            // No token means we're being redirected to login, not a clock error
            if (isAuthRequiredError(error)) {
              return
            }
            // Keep the last good value but grey it out and show why
            this.itemClockError = error?.message || String(error)
          })
          .finally(() => {
            inFlight = false
          })
      }
      poll()
      this.itemClockInterval = setInterval(poll, 1000)
    },
    // Convert the TIMESECONDS (float seconds since epoch) or
    // TIMEFORMATTED (UTC 'YYYY/MM/DD HH:MM:SS.sss') value to an ISO string.
    // Throws if the value can't be converted to a date.
    parseItemClockValue(value) {
      let date = null
      if (typeof value === 'number' || typeof value === 'bigint') {
        date = new Date(Number(value) * 1000)
      } else if (typeof value === 'string' && value.length > 0) {
        const match = value.match(
          /^(\d{4})\/(\d{2})\/(\d{2})[ T](\d{2}:\d{2}:\d{2}(?:\.\d+)?)$/,
        )
        if (match) {
          date = new Date(`${match[1]}-${match[2]}-${match[3]}T${match[4]}Z`)
        } else {
          date = new Date(value)
        }
      }
      if (date === null || Number.isNaN(date.getTime())) {
        throw new Error(`Unable to convert '${value}' to a time`)
      }
      return date.toISOString()
    },
    updateActiveItem() {
      const path = globalThis.location.pathname
      const allTools = this.items.flatMap((item) =>
        item.children ? item.children : [item],
      )
      const match = allTools.find(
        (tool) => tool.url && path.startsWith(tool.url),
      )
      this.activeItems = match ? [match.name] : []
    },
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
.item-clock {
  display: flex;
  flex-direction: column;
}
/* Stretch the time box to the width of the title so a long title
widens the clock rather than getting cut off */
.item-clock rux-clock::part(container) {
  display: grid;
  width: 100%;
}
.item-clock rux-clock::part(time) {
  align-self: stretch;
  justify-content: center;
}
/* Match the rux-clock .rux-clock__segment__label styling */
.item-clock-title {
  font-family: var(--font-body-2-font-family);
  font-size: var(--font-body-2-font-size, 0.875rem);
  font-weight: var(--font-body-2-font-weight, 400);
  letter-spacing: var(--font-body-2-letter-spacing, 0.005em);
  line-height: var(--font-body-3-line-height, calc(16 / 12));
  color: var(--color-palette-neutral-000, #ffffff);
  background: var(--gsb-color-background, #172635);
  padding: 0 var(--spacing-3, 0.75rem);
  height: var(--spacing-6, 1.5rem);
  display: flex;
  align-items: flex-end;
  justify-content: center;
  white-space: nowrap;
}
.item-clock-error {
  opacity: 0.4;
  filter: grayscale(1);
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
.cosmos-wordmark {
  display: block;
  margin-left: auto;
  margin-right: auto;
  width: 50%;
  padding: 8px 0;
  cursor: pointer;
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
  padding-left: 8px;
  padding-right: 8px;
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
/* Make the entire treeview item row clickable, not just the icon/text */
#openc3-nav-drawer .v-treeview-item .v-treeview-item__root {
  position: relative;
}
#openc3-nav-drawer .v-treeview-item .v-list-item-title > a::after {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
}
#openc3-nav-drawer .v-treeview-item .v-treeview-item__append {
  position: relative;
  z-index: 1;
}
</style>
