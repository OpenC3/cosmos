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
  <slot name="activator" :props="{ onClick: openDialog }"></slot>
  <v-dialog v-model="isDialogOpen" max-width="500">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span v-text="title" />
        <v-spacer />
        <v-tooltip location="top">
          <template #activator="{ props }">
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
          <span> View at {{ formattedStoreLink }} </span>
        </v-tooltip>
        <v-btn
          icon="mdi-close-box"
          variant="text"
          density="compact"
          @click="closeDialog"
        />
      </v-toolbar>
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
      </v-card-subtitle>
      <!--
      <v-card-subtitle
        class="d-flex align-center justify-content-space-between"
      >
        <div>
          <v-icon icon="mdi-cloud-download" size="x-small" />
          {{ downloads }} downloads
        </div>
        <v-spacer />
        <div class="d-flex align-center">
          <v-rating
            :model-value="rating"
            density="compact"
            size="small"
            readonly
            half-increments
          />
        </div>
      </v-card-subtitle>
      -->
      <v-card-text>
        <div class="plugin-image-backdrop">
          <v-img v-if="image_url" :src="image_url" />
        </div>
        <v-img
          v-if="imageContentsWithMimeType"
          :src="imageContentsWithMimeType"
        />
        <div class="mt-3" v-text="description" />
        <div class="mt-3 text-caption font-italic">
          Keywords:
          <template v-if="keywords">
            <v-chip
              v-for="keyword in keywords"
              :key="keyword"
              variant="flat"
              color="primary"
              size="x-small"
              class="ml-1"
            >
              {{ keyword }}
            </v-chip>
          </template>
          <span v-else class="font-italic"> none </span>
        </div>
        <div class="mt-3 text-caption font-italic">
          Licenses:
          <v-chip
            v-for="license in licenses"
            :key="license"
            size="x-small"
            class="ml-1"
          >
            {{ license }}
          </v-chip>
        </div>
        <div class="mt-3">
          <span class="text-caption font-italic"> Minimum COSMOS version: </span>
          {{ minimum_cosmos_version }}
          <v-tooltip v-if="versionsAreCompatible !== null" :open-delay="600" location="top">
            <template #activator="{ props }">
              <span v-bind="props">
                <v-icon :icon="versionsAreCompatible ? 'mdi-check-circle' : 'mdi-alert'" size="small" />
              </span>
            </template>
            <span v-if="versionsAreCompatible"> Your version of COSMOS meets the requirements. </span>
            <span v-else> Your version of COSMOS is out of date. You can still install this plugin, but it might not work correctly. </span>
          </v-tooltip>
        </div>
        <v-text-field
          v-model="checksum"
          class="mt-3"
          label="SHA256"
          variant="solo"
          density="compact"
          hide-details
          readonly
        >
          <template #append>
            <v-tooltip
              v-model="showCopiedTooltip"
              location="top"
              :open-on-hover="false"
            >
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  icon="mdi-content-copy"
                  variant="text"
                  density="compact"
                  @click="copyChecksum"
                />
              </template>
              <span>Copied!</span>
            </v-tooltip>
          </template>
        </v-text-field>
      </v-card-text>

      <v-card-actions class="justify-start px-6">
        <v-btn
          v-if="isPluginInstalled"
          text="Uninstall"
          append-icon="mdi-puzzle-remove"
          variant="outlined"
          color="red"
          @click="uninstall"
        />
        <v-btn
          v-else
          text="Install"
          append-icon="mdi-puzzle-plus"
          variant="elevated"
          @click="install"
        />
        <v-btn
          v-if="repository"
          text="Repository"
          append-icon="mdi-open-in-new"
          variant="outlined"
          :href="repository"
          target="_blank"
        />
        <v-btn
          v-if="homepage"
          text="Homepage"
          append-icon="mdi-open-in-new"
          variant="outlined"
          :href="homepage"
          target="_blank"
        />
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import * as semver from 'semver'
import PluginProps from './PluginProps'

export default {
  mixins: [PluginProps],
  props: {
    modelValue: Boolean,
  },
  emits: ['triggerInstall', 'triggerUninstall', 'update:modelValue'],
  data() {
    return {
      showDialog: false,
      showCopiedTooltip: false,
      installedCosmosVersion: null,
    }
  },
  computed: {
    isDialogOpen: {
      get: function () {
        return this.modelValue || this.showDialog
      },
      set: function (val) {
        this.showDialog = val
        this.$emit('update:modelValue', val)
      },
    },
    formattedStoreLink: function () {
      return this._storeUrl.split('://').at(-1)
    },
    versionsAreCompatible: function () {
      if (!this.installedCosmosVersion || !this.minimum_cosmos_version) {
        return null
      }
      return semver.gte(this.installedCosmosVersion, this.minimum_cosmos_version)
    },
  },
  created: function () {
    Api.get('/openc3-api/info').then(({ data }) => {
      this.installedCosmosVersion = data.version
    })
  },
  methods: {
    openDialog: function () {
      this.isDialogOpen = true
    },
    closeDialog: function () {
      this.isDialogOpen = false
    },
    install: function () {
      this.$emit('triggerInstall', this.gemUrl)
    },
    uninstall: function () {
      this.$emit('triggerUninstall', this.gemUrl)
    },
    copyChecksum: function () {
      navigator.clipboard.writeText(this.checksum)
      this.showCopiedTooltip = true
      setTimeout(() => {
        this.showCopiedTooltip = false
      }, 1000)
    },
  },
}
</script>

<style scoped>
.plugin-image-backdrop {
  background-color: rgb(156, 163, 175);
}
</style>
