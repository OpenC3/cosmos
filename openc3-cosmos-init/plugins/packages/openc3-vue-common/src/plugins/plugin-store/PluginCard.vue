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
  <plugin-details-dialog v-bind="plugin" @trigger-install="install">
    <template #activator="{ props }">
      <v-card v-bind="props" height="350" class="d-flex flex-column">
        <v-card-title class="d-flex align-center justify-content-space-between">
          {{ title }}
          <v-spacer />
          <v-badge
            v-if="verified"
            inline
            icon="mdi-shield-check"
            color="success"
          />
        </v-card-title>
        <v-card-subtitle
          class="d-flex align-center justify-content-space-between"
        >
          <div>{{ author }}</div>
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
          <v-img v-if="img_path" :src="img_path" max-height="160" />
          <div
            :class="{
              'truncate-description': true,
              'truncate-2': !!img_path,
              'truncate-10': !img_path,
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
</style>
