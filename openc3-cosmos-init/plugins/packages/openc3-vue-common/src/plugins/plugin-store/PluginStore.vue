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
        <div class="text-h3 mb-3">
          OpenC3 Plugin Store
        </div>
        <div class="text-subtitle-1">
          Browse plugins made by OpenC3 and the COSMOS community
        </div>
      </div>
      <v-spacer />
      <v-tooltip location="top">
        <template v-slot:activator="{ props }">
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

      <v-btn @click="close" icon="mdi-close" variant="text" />
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
        <v-col v-for="plugin in filteredPlugins" cols="4">
          <plugin-card v-bind="plugin" @triggerInstall="install" />
        </v-col>
      </v-row>
    </v-container>
  </v-sheet>
</template>

<script>
import { PluginCard } from '@/plugins/plugin-store'

export default {
  emits: ['close', 'triggerInstall'],
  components: {
    PluginCard,
  },
  data() {
    return {
      search: '',
      verifiedOnly: false,
      plugins: [
        {
          title: 'An awesome plugin',
          titleSlug: 'an-awesome-plugin',
          author: 'Totally Real Space Co.',
          authorSlug: 'totally-real-space',
          description: 'Short description that fits on two lines.',
          keywords: ['cosmos', 'plugin'],
          image: 'https://cdn.prod.website-files.com/646d451b4b3d75dd994b85bd/660dbb96f6470c6536bfd6be_forgec2.jpg',
          license: 'BSD',
          rating: 2.5,
          downloads: 12,
          verified: false,
          homepage: 'https://www.google.com',
          repository: 'https://github.com',
          gemUrl: 'https://rubygems.org/an-awesome-plugin.gem',
          sha256: '9038o0450439850943850984305804398509348509843',
        },
        {
          title: 'Power Supply Adapter',
          titleSlug: 'power-supply-adapter',
          author: 'David Heinemeier Hansson',
          authorSlug: 'dhh',
          description: 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.',
          keywords: ['power supply'],
          image: null,
          license: 'MIT',
          rating: 5,
          downloads: 42,
          verified: false,
          homepage: 'https://www.google.com',
          repository: 'https://github.com',
          gemUrl: 'https://rubygems.org/power-supply-adapter.gem',
          sha256: '9038o0450439850943850984305804398509348509843',
        },
        {
          title: 'Calendar',
          titleSlug: 'calendar',
          author: 'OpenC3 Inc.',
          authorSlug: 'openc3',
          description: 'Calendar visualizes metadata, notes, and timeline information in one easy to understand place. Timelines allow for the simple execution of commands and scripts based on future dates and times.',
          image: 'https://docs.openc3.com/assets/images/blank_calendar-70e605942120937b862bd7039348229bab9af1f9c93d356ddbf401a3e8543c74.png',
          license: 'Commercial - Enterprise Only',
          rating: 4.5,
          downloads: 1337,
          verified: true,
          homepage: 'https://docs.openc3.com/docs/tools/calendar',
          repository: 'https://github.com/OpenC3/cosmos-enterprise/tree/main/openc3-cosmos-enterprise-init/plugins/packages/openc3-cosmos-tool-calendar',
          gemUrl: 'https://rubygems.org/calendar.gem',
          sha256: '9038o0450439850943850984305804398509348509843',
        },
      ],
    }
  },
  computed: {
    filteredPlugins: function () {
      let filtered = this.plugins
      if (this.verifiedOnly) {
        filtered = filtered.filter(plugin => plugin.verified)
      }
      if (this.search.length) {
        filtered = filtered.filter(plugin => plugin.title.toLowerCase().includes(this.search.toLowerCase()))
      }
      return filtered
    },
  },
  methods: {
    close: function () {
      this.$emit('close')
    },
    install: function (gemUrl) {
      this.$emit('triggerInstall', gemUrl)
    },
  },
}
</script>

<style>
.v-sheet {
  background-color: var(--color-background-base-default);
}
</style>
