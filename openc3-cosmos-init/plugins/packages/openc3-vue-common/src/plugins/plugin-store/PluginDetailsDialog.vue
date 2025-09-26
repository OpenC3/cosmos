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
          <span> View at store.openc3.com </span>
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
        <div>{{ author }}</div>
        <v-spacer />
        <div v-if="verified">
          Verified
          <v-badge inline icon="mdi-shield-check" color="success" />
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
        <v-img v-if="img_path" :src="img_path" />
        <div v-text="description" />
        <div class="mt-3 text-caption font-italic">License: {{ license }}</div>
        <v-text-field
          v-model="checksum"
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
  </v-dialog>
</template>

<script>
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
