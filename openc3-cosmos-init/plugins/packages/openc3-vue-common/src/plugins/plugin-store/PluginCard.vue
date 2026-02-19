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
  <plugin-details-dialog v-bind="plugin" @trigger-install="install">
    <template #activator="{ props }">
      <v-card v-bind="props" height="350" class="d-flex flex-column">
        <v-card-title class="d-flex align-center justify-content-space-between">
          {{ title }}
        </v-card-title>
        <v-card-subtitle
          class="d-flex align-center justify-content-space-between"
        >
          <div>
            By <strong>{{ author }}</strong>
            <span v-if="author_extra?.badge_text" class="ml-1 font-italic">
              {{ author_extra.badge_text }}
            </span>
            <v-icon v-if="author_extra?.badge_icon" :icon="author_extra.badge_icon" :size="18" class="ml-1" />
          </div>
          <!--
          <v-spacer />
          <v-rating
            :model-value="rating"
            density="compact"
            size="small"
            readonly
            half-increments
          />
          -->
        </v-card-subtitle>
        <v-card-text>
          <div class="plugin-image-backdrop">
            <v-img v-if="image_url" :src="image_url" max-height="160" />
          </div>
          <div
            :class="{
              'truncate-description': true,
              'truncate-2': !!image_url,
              'truncate-10': !image_url,
            }"
            v-text="description"
          />
        </v-card-text>
        <v-spacer />
        <v-card-actions class="flex-wrap">
          <v-btn
            text="Install"
            append-icon="mdi-puzzle-plus"
            variant="elevated"
            @click.stop="install"
          />
        </v-card-actions>
      </v-card>
    </template>
  </plugin-details-dialog>
</template>

<script>
import PluginProps from './PluginProps'
import PluginDetailsDialog from './PluginDetailsDialog.vue'

export default {
  components: {
    PluginDetailsDialog,
  },
  mixins: [PluginProps],
  emits: ['triggerInstall'],
  methods: {
    install: function () {
      this.$emit('triggerInstall', this.plugin)
    },
  },
}
</script>

<style scoped>
.truncate-description {
  overflow: hidden;
  text-overflow: ellipsis;
  display: -webkit-box;
  -webkit-box-orient: vertical;
}

.truncate-2 {
  line-clamp: 2;
  -webkit-line-clamp: 2;
}

.truncate-10 {
  line-clamp: 10;
  -webkit-line-clamp: 10;
}

.plugin-image-backdrop {
  background-color: rgb(156, 163, 175);
}
</style>
