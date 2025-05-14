<!--
# Copyright 2025 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-sheet class="pb-11 pt-8 px-8" height="100%">
    <div class="d-flex justify-content-space-between">
      <div>
        <div class="text-h3 mb-3">OpenC3 Plugin Store</div>
        <div class="text-subtitle-1">
          Browse plugins made by OpenC3 and the COSMOS community
        </div>
      </div>
      <v-spacer />
      <v-btn icon="mdi-cog" variant="text" @click="openSettings" />

      <v-tooltip location="top">
        <template #activator="{ props }">
          <div v-bind="props">
            <v-btn
              href="https://plugins.openc3.com"
              target="_blank"
              icon="mdi-open-in-new"
              variant="text"
              class="mx-2"
            />
          </div>
        </template>
        <span> Open plugins.openc3.com </span>
      </v-tooltip>

      <v-btn icon="mdi-close" variant="text" @click="close" />
    </div>
    <div class="d-inline-flex align-center w-100">
      <v-text-field
        v-model="search"
        label="Search"
        prepend-inner-icon="mdi-magnify"
        clearable
        variant="outlined"
        density="compact"
        single-line
        hide-details
        data-test="search-plugin-store"
      />
      <v-switch
        v-model="verifiedOnly"
        label="Verified only"
        density="compact"
        hide-details
        class="ml-4"
      />
    </div>
    <v-spacer />
    <span class=""> Click on a plugin to see more information about it </span>
    <v-container>
      <v-row>
        <v-col v-for="plugin in filteredPlugins" :key="plugin.id" cols="4">
          <plugin-card v-bind="plugin" @trigger-install="install" />
        </v-col>
      </v-row>
    </v-container>
  </v-sheet>
  <plugin-store-settings-dialog
    v-model="showSettingsDialog"
    @update:store-url="updateStoreUrl"
  />
</template>

<script>
import { PluginCard } from '@/plugins/plugin-store'
import PluginStoreSettingsDialog from './PluginStoreSettingsDialog.vue' // idk why importing from @/plugins/plugin-store isn't working
import { PluginStoreApi } from '@/tools/admin/tabs/plugins'

export default {
  components: {
    PluginCard,
    PluginStoreSettingsDialog,
  },
  emits: ['close', 'triggerInstall'],
  data() {
    return {
      pluginStoreApi: new PluginStoreApi(),
      search: '',
      verifiedOnly: false,
      showSettingsDialog: false,
      plugins: [],
    }
  },
  computed: {
    filteredPlugins: function () {
      let filtered = this.plugins
      if (this.verifiedOnly) {
        filtered = filtered.filter((plugin) => plugin.verified)
      }
      if (this.search.length) {
        filtered = filtered.filter((plugin) =>
          plugin.title.toLowerCase().includes(this.search.toLowerCase()),
        )
      }
      return filtered
    },
  },
  mounted: function () {
    this.pluginStoreApi.getAll().then((response) => {
      this.plugins = response.data
    })
    // TODO: do something with plugins that are already installed (show uninstall button instead?)
  },
  methods: {
    close: function () {
      this.$emit('close')
    },
    install: function (gemUrl) {
      this.$emit('triggerInstall', gemUrl)
    },
    openSettings: function () {
      this.showSettingsDialog = true
    },
    updateStoreUrl: function () {
      this.pluginStoreApi.refreshPluginStoreUrl()
    },
  },
}
</script>

<style>
.v-sheet {
  background-color: var(--color-background-base-default);
}
</style>
