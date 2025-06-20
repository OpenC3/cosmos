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
  <v-dialog max-width="500">
    <template v-slot:activator="{ props }">
      <v-card v-bind="props" height="350" class="d-flex flex-column">
        <v-card-title class="d-flex align-center justify-content-space-between">
          {{ title }}
          <v-spacer />
          <v-badge inline v-if="verified" icon="mdi-shield-check" color="success" />
        </v-card-title>
        <v-card-subtitle> Author: {{ author }} </v-card-subtitle>
        <v-card-text>
          <v-img v-if="image" :src="image" max-height="160" />
            <div
              :class="{
                'truncate-description': true,
                'truncate-2': !!image,
                'truncate-10': !image,
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

    <template v-slot:default="{ isActive }">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span v-text="title" />
          <v-spacer />
          <v-tooltip location="top">
            <template v-slot:activator="{ props }">
              <div v-bind="props">
                <v-btn
                  :href="storeLink"
                  target="_blank"
                  icon="mdi-open-in-new"
                  size="small"
                  variant="plain"
                />
              </div>
            </template>
            <span> View at plugins.openc3.com </span>
          </v-tooltip>
        </v-toolbar>
        <v-card-subtitle class="d-flex align-center justify-content-space-between">
          <div> Author: {{ author }} </div>
          <v-spacer />
          <div v-if="verified">
            Verified
            <v-badge inline icon="mdi-shield-check" color="success" />
          </div>
        </v-card-subtitle>
        <v-card-subtitle class="d-flex align-center justify-content-space-between">
          <div class="d-flex align-center">
            Rating:
            <v-rating
              :model-value="rating"
              density="compact"
              size="small"
              readonly
              half-increments
            />
          </div>
          <v-spacer />
          <div>
            <v-icon icon="mdi-cloud-download" size="x-small" />
            {{ downloads }} downloads
          </div>
        </v-card-subtitle>
        <v-card-text>
          <v-img v-if="image" :src="image" />
          <div v-text="description" />
          <div class="mt-3 text-caption font-italic"> License: {{ license }} </div>
          <div class="text-caption font-italic"> SHA256: {{ sha256 }} </div>
        </v-card-text>

        <v-card-actions class="justify-start px-6">
          <v-btn
            text="Install"
            append-icon="mdi-puzzle-plus"
            variant="elevated"
            @click="() => {
              isActive.value = false
              install()
            }"
          />
          <v-btn
            text="Repository"
            append-icon="mdi-open-in-new"
            variant="outlined"
            :href="repository"
            target="_blank"
          />
          <v-btn
            text="Homepage"
            append-icon="mdi-open-in-new"
            variant="outlined"
            :href="homepage"
            target="_blank"
          />
        </v-card-actions>
      </v-card>
    </template>
  </v-dialog>
</template>

<script>
export default {
  emits: ['triggerInstall'],
  props: {
    plugin: Object,
  },
  data() {
    return {
      ...this.plugin,
    }
  },
  computed: {
    storeLink: function () {
      return `https://plugins.openc3.com/${this.authorSlug}/${this.titleSlug}`
    },
  },
  methods: {
    install: function () {
      this.$emit('triggerInstall', this.gemUrl)
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
