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
  <v-data-table
    :headers="[]"
    :items="shownPlugins"
    density="compact"
    class="list"
    data-test="plugin-list"
  >
    <template #item="{ item: plugin }">
      <plugin-list-item
        v-bind="plugin"
        :targets="pluginTargets(plugin.name)"
        :is-modified="isModified(plugin.name)"
        @edit="() => editPlugin(plugin.name)"
        @upgrade="() => upgradePlugin(plugin.name)"
        @delete="() => deletePrompt(plugin.name)"
      />
    </template>
  </v-data-table>
</template>

<script>
import PluginListItem from './PluginListItem.vue'

export default {
  components: {
    PluginListItem,
  },
  props: {
    plugins: {
      type: Array,
      required: true,
    },
    targets: {
      type: Object,
      required: true,
    },
    showDefaultTools: {
      type: Boolean,
      default: false,
    },
    defaultPlugins: {
      type: Array,
      required: true,
    },
  },
  emits: ['edit', 'delete', 'upgrade'],
  data() {
    return {
      showPluginDetails: false,
      detailPlugin: null,
    }
  },
  computed: {
    shownPlugins() {
      const pluginsToShow = []
      const defaultPluginsToShow = []
      this.plugins.forEach((plugin) => {
        const pluginNameFirst = plugin.name.split('__')[0]
        const pluginNameSplit = pluginNameFirst.split('-').slice(0, -1)
        const pluginNameShort = pluginNameSplit.join('-')
        if (this.defaultPlugins.includes(pluginNameShort)) {
          defaultPluginsToShow.push(plugin)
        } else {
          pluginsToShow.push(plugin)
        }
      })
      pluginsToShow.sort((a, b) =>
        a.name < b.name ? -1 : a.name > b.name ? 1 : 0,
      )
      if (this.showDefaultTools) {
        defaultPluginsToShow.sort((a, b) =>
          a.name < b.name ? -1 : a.name > b.name ? 1 : 0,
        )
        return pluginsToShow.concat(defaultPluginsToShow)
      }
      return pluginsToShow
    },
  },
  methods: {
    showDetails: function (plugin) {
      this.detailPlugin = plugin
      this.showPluginDetails = true
    },
    pluginTargets: function (plugin) {
      let result = []
      for (const target in this.targets) {
        if (this.targets[target]['plugin'] === plugin) {
          result.push(this.targets[target])
        }
      }
      return result
    },
    isModified: function (plugin) {
      return Object.entries(this.targets).some(([targetName, target]) => {
        return target['plugin'] === plugin && target['modified'] === true
      })
    },
    editPlugin: function (plugin) {
      this.$emit('edit', plugin)
    },
    upgradePlugin(plugin) {
      this.$emit('upgrade', plugin)
    },
    deletePrompt: function (plugin) {
      this.$emit('delete', plugin)
    },
  },
}
</script>

<style scoped>
.list {
  background-color: var(--color-background-surface-default) !important;
  overflow-x: hidden;
}
.v-theme--cosmosDark.v-list div:nth-child(odd) .v-list-item {
  background-color: var(--color-background-base-selected) !important;
}
</style>

