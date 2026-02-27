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
  <v-dialog v-model="isDialogOpen" max-width="500">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span v-text="versionTitle" />
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
        class="d-flex align-center justify-space-between subtitle-with-version"
      >
        <div>
          By <strong>{{ author }}</strong>
          <span v-if="author_extra?.badge_text" class="ml-1 font-italic">
            {{ author_extra.badge_text }}
          </span>
          <v-icon
            v-if="author_extra?.badge_icon"
            :icon="author_extra.badge_icon"
            :size="18"
            class="ml-1"
          />
        </div>
        <v-select
          v-if="hasVersions"
          v-model="selectedVersionId"
          :items="versionOptions"
          item-title="title"
          item-value="value"
          label="Version"
          density="compact"
          variant="outlined"
          hide-details
          class="version-select"
        />
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
          <v-img
            v-if="imageContentsWithMimeType"
            :src="imageContentsWithMimeType"
          />
          <v-img v-else-if="versionImageUrl" :src="versionImageUrl" />
        </div>
        <div class="mt-3" v-text="versionDescription" />
        <div class="mt-3 text-caption font-italic">
          Keywords:
          <template v-if="versionKeywords">
            <v-chip
              v-for="keyword in versionKeywords"
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
            v-for="license in versionLicenses"
            :key="license"
            size="x-small"
            class="ml-1"
          >
            {{ license }}
          </v-chip>
        </div>
        <div class="mt-3">
          <span class="text-caption font-italic">
            Minimum COSMOS version:
          </span>
          {{ versionMinimumCosmosVersion }}
          <v-tooltip
            v-if="versionsAreCompatible !== null"
            :open-delay="600"
            location="top"
          >
            <template #activator="{ props }">
              <span v-bind="props">
                <v-icon
                  :icon="
                    versionsAreCompatible ? 'mdi-check-circle' : 'mdi-alert'
                  "
                  size="small"
                />
              </span>
            </template>
            <span v-if="versionsAreCompatible">
              Your version of COSMOS meets the requirements.
            </span>
            <span v-else>
              Your version of COSMOS is out of date. You can still install this
              plugin, but it might not work correctly.
            </span>
          </v-tooltip>
        </div>
        <v-text-field
          v-model="versionChecksum"
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
          v-if="versionRepository"
          text="Repository"
          append-icon="mdi-open-in-new"
          variant="outlined"
          :href="versionRepository"
          target="_blank"
        />
        <v-btn
          v-if="versionHomepage"
          text="Homepage"
          append-icon="mdi-open-in-new"
          variant="outlined"
          :href="versionHomepage"
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
      selectedVersionId: null,
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
    hasVersions: function () {
      return this.versions && this.versions.length > 0
    },
    selectedVersion: function () {
      if (!this.hasVersions) {
        return null
      }
      const versionId = this.selectedVersionId || this.current_version_id
      return this.versions.find((v) => v.id === versionId) || this.versions[0]
    },
    versionOptions: function () {
      if (!this.hasVersions) {
        return []
      }
      return this.versions.map((v) => ({
        title: v.version_number,
        value: v.id,
      }))
    },
    versionTitle: function () {
      return this.selectedVersion?.title || this.title
    },
    versionDescription: function () {
      return this.selectedVersion?.description || this.description
    },
    versionKeywords: function () {
      return this.selectedVersion?.keywords || this.keywords
    },
    versionLicenses: function () {
      return this.selectedVersion?.licenses || this.licenses
    },
    versionHomepage: function () {
      return this.selectedVersion?.homepage || this.homepage
    },
    versionRepository: function () {
      return this.selectedVersion?.repository || this.repository
    },
    versionGemUrl: function () {
      return this.selectedVersion?.gem_url || this.gem_url
    },
    versionMinimumCosmosVersion: function () {
      return (
        this.selectedVersion?.minimum_cosmos_version ||
        this.minimum_cosmos_version
      )
    },
    versionChecksum: function () {
      return this.selectedVersion?.checksum || this.checksum
    },
    versionImageUrl: function () {
      return this.selectedVersion?.image_url || this.image_url
    },
    formattedStoreLink: function () {
      return this._navigableStoreUrl.split('://').at(-1)
    },
    versionsAreCompatible: function () {
      if (!this.installedCosmosVersion || !this.versionMinimumCosmosVersion) {
        return null
      }
      return semver.gte(
        this.installedCosmosVersion,
        this.versionMinimumCosmosVersion,
      )
    },
  },
  created: function () {
    Api.get('/openc3-api/info').then(({ data }) => {
      this.installedCosmosVersion = data.version
    })
  },
  mounted: function () {
    this.selectedVersionId = this.current_version_id
  },
  methods: {
    openDialog: function () {
      this.isDialogOpen = true
    },
    closeDialog: function () {
      this.isDialogOpen = false
    },
    install: function () {
      this.$emit('triggerInstall', {
        id: this.id,
        version_id: this.selectedVersionId || this.current_version_id,
      })
    },
    uninstall: function () {
      this.$emit('triggerUninstall', {
        id: this.id,
        version_id: this.selectedVersionId || this.current_version_id,
      })
    },
    copyChecksum: function () {
      navigator.clipboard.writeText(this.versionChecksum)
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

.subtitle-with-version {
  width: 100%;
  min-height: 48px;
}

.version-select {
  max-width: 120px;
  min-width: 120px;
}
</style>
