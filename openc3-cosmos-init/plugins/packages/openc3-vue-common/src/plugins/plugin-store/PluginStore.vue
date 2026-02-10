<!--
# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

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
              :href="storeUrl"
              target="_blank"
              icon="mdi-open-in-new"
              variant="text"
              class="mx-2"
            />
          </div>
        </template>
        <span> Open {{ formattedStoreUrl }} </span>
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
    </div>
    <v-spacer />
    <span class=""> Click on a plugin to see more information about it </span>
    <v-alert
      v-if="storeError"
      class="mt-6"
      color="error"
      :title="storeError.title"
      :text="storeError.body"
    />
    <v-container v-else>
      <v-row>
        <v-col v-for="plugin in filteredPlugins" :key="plugin.id" cols="4">
          <plugin-card v-bind="plugin" @trigger-install="install" />
        </v-col>
      </v-row>
    </v-container>
  </v-sheet>
  <plugin-store-settings-dialog
    v-model="showSettingsDialog"
    @update:store-url="updatePluginStore"
  />
</template>

<script>
import { Api, OpenC3Api } from '@openc3/js-common/services'
import { PluginCard } from '@/plugins/plugin-store'
import PluginStoreSettingsDialog from './PluginStoreSettingsDialog.vue' // idk why importing from @/plugins/plugin-store isn't working

const DEFAULT_STORE_URL = 'https://store.openc3.com'

export default {
  components: {
    PluginCard,
    PluginStoreSettingsDialog,
  },
  emits: ['close', 'triggerInstall'],
  data() {
    return {
      api: new OpenC3Api(),
      search: '',
      showSettingsDialog: false,
      plugins: [],
      storeError: null,
      storeUrl: DEFAULT_STORE_URL,
    }
  },
  computed: {
    filteredPlugins: function () {
      let filtered = this.plugins
      if (this.search.length) {
        filtered = filtered.filter((plugin) =>
          plugin.title.toLowerCase().includes(this.search.toLowerCase()),
        )
      }
      return filtered
    },
    formattedStoreUrl: function () {
      return this.storeUrl.split('://').at(-1)
    },
  },
  mounted: function () {
    // Don't call updatePluginStore() here. It should be called in the background before the user opens this store
    // view (see PluginsTab.vue `created()`) to keep this feeling fast
    this.fetchPluginStoreData()
    // TODO: do something with plugins that are already installed (no uninstall button: https://github.com/OpenC3/cosmos/pull/2162#discussion_r2249339853 )
  },
  methods: {
    fetchPluginStoreData: function () {
      Api.get('/openc3-api/pluginstore').then(({ data }) => {
        if (data.error) {
          const { title, body } = data
          this.storeError = { title, body }
          this.plugins = []
        } else {
          this.storeError = null
          this.plugins = data
        }
      })
    },
    close: function () {
      this.$emit('close')
    },
    install: function (plugin) {
      this.$emit('triggerInstall', plugin)
      this.close()
    },
    openSettings: function () {
      this.showSettingsDialog = true
    },
    updatePluginStore: function (storeUrl) {
      this.storeUrl = storeUrl
      this.api.update_plugin_store().then((response) => {
        this.fetchPluginStoreData()
      })
    },
  },
}
</script>

<style>
.v-sheet {
  background-color: var(--color-background-base-default);
}
</style>
