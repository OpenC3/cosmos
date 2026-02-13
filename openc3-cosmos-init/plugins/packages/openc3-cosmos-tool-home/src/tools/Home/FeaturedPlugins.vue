<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <div class="d-flex align-center ga-2 mb-5">
      <v-icon icon="mdi-store" size="20" color="secondary" />
      <span class="text-h6 text-white font-weight-bold">
        Featured Plugins
      </span>
      <a
        class="ml-auto text-body-2 browse-link"
        href="https://store.openc3.com"
        target="_blank"
        rel="noopener noreferrer"
      >
        Browse All &rarr;
      </a>
    </div>
    <div class="d-flex ga-4">
      <v-card
        v-for="plugin in plugins"
        :key="plugin.id"
        :href="`https://store.openc3.com/cosmos_plugins/${plugin.id}`"
        target="_blank"
        rel="noopener noreferrer"
        class="flex-1-1-0 card"
        variant="outlined"
        rounded="lg"
      >
        <v-img
          v-if="plugin.image_url"
          :src="plugin.image_url"
          :alt="plugin.title"
          height="120"
          width="100%"
        />
        <div
          v-else
          class="d-flex align-center justify-center"
          style="
            height: 120px;
            background: rgba(var(--v-theme-secondary), 0.05);
          "
        >
          <v-icon icon="mdi-puzzle" size="32" color="secondary" />
        </div>
        <v-card-text class="pa-3">
          <div class="text-body-1 font-weight-bold text-white">
            {{ plugin.title }}
          </div>
          <div class="text-caption text-medium-emphasis">
            {{ plugin.author }}
          </div>
          <div class="text-body-2 text-medium-emphasis mt-2">
            {{ truncate(plugin.description, 80) }}
          </div>
        </v-card-text>
      </v-card>
    </div>
  </div>
</template>

<script>
import { Api } from '@openc3/js-common/services'

export default {
  data() {
    return {
      plugins: [],
    }
  },
  mounted() {
    Api.get('/openc3-api/pluginstore?featured_only=true')
      .then(({ data }) => {
        if (!data.error && Array.isArray(data)) {
          this.plugins = data.slice(0, 3)
        }
      })
      .catch(() => {})
  },
  methods: {
    truncate(text, length) {
      if (!text) return ''
      return text.length > length ? text.substring(0, length) + '...' : text
    },
  },
}
</script>

<style scoped>
.browse-link {
  color: rgb(var(--v-theme-secondary));
  text-decoration: none;
  transition: opacity 0.2s ease;
}
.browse-link:hover {
  opacity: 0.8;
}
.card {
  border-color: rgba(var(--v-theme-secondary), 0.2);
  transition: all 0.2s ease;
  overflow: hidden;
  min-width: 0;
}
.card:hover {
  background: rgba(var(--v-theme-secondary), 0.1);
  border-color: rgb(var(--v-theme-secondary));
}
</style>
