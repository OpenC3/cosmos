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
  <v-card :style="computedStyle" min-width="400">
    <v-card-title class="d-flex align-center pa-2">
      <span class="text-caption text-medium-emphasis font-weight-regular">
        {{ files.length === 1 ? 'File Checksum' : 'File Checksum Comparison' }}
      </span>
      <v-spacer />
      <v-btn
        size="x-small"
        icon="mdi-refresh"
        variant="text"
        :loading="loading"
        @click="fetchChecksums"
      />
    </v-card-title>
    <v-divider />
    <v-card-text class="pa-3">
      <template v-for="(file, index) in files" :key="index">
        <div class="text-caption text-medium-emphasis mb-2">
          {{ files.length === 1 ? 'File:' : `File ${index + 1}:` }}
          <span class="ml-1 text-high-emphasis">{{ file.path }}</span>
        </div>
        <v-sheet
          :class="file.error ? 'text-error' : ''"
          class="d-flex align-center ga-2 px-2 py-1 mb-3 rounded text-caption"
          style="background-color: rgba(128, 128, 128, 0.2)"
        >
          <span class="flex-grow-1 overflow-wrap-anywhere">
            {{ getDisplayText(file) }}
          </span>
          <v-btn
            :icon="file.copied ? '$success' : 'mdi-content-copy'"
            :color="file.copied ? 'success' : undefined"
            :disabled="!file.checksum"
            size="x-small"
            variant="plain"
            density="compact"
            @click="copyChecksum(file)"
          />
        </v-sheet>
      </template>

      <template v-if="files.length > 1">
        <v-divider class="mb-3" />
        <v-chip
          :color="matchStatus.color"
          size="small"
          variant="tonal"
          label
          :prepend-icon="matchStatus.icon"
        >
          {{ matchStatus.text }}
        </v-chip>
      </template>
    </v-card-text>
  </v-card>
</template>

<script>
import { Api } from '@openc3/js-common/services'
import Widget from './Widget'

export default {
  mixins: [Widget],
  data() {
    return {
      files: [],
      loading: false,
    }
  },
  computed: {
    match() {
      if (this.files.some((f) => f.error)) return false
      if (this.files.some((f) => !f.checksum)) return null
      const first = this.files[0].checksum
      return this.files.every((f) => f.checksum === first)
    },
    matchStatus() {
      const states = {
        null: { icon: '$info', color: 'grey', text: 'Comparing...' },
        true: { icon: '$success', color: 'success', text: 'Checksums Match' },
        false: {
          icon: '$error',
          color: 'error',
          text: this.files.some((f) => f.error)
            ? 'Error loading file(s)'
            : 'Checksums Do Not Match',
        },
      }
      return states[this.match]
    },
  },
  created() {
    this.files = this.parameters
      .filter((p) => p)
      .map((path) => ({ path, checksum: null, error: null, copied: false }))
  },
  mounted() {
    if (this.files.length) {
      this.fetchChecksums()
    }
  },
  methods: {
    getDisplayText(file) {
      if (file.error) return `Error: ${file.error}`
      if (file.checksum) return file.checksum
      if (this.loading) return 'Loading...'
      return 'Not loaded'
    },
    async computeChecksum(content) {
      const encoder = new TextEncoder()
      const data = encoder.encode(content)
      const hashBuffer = await crypto.subtle.digest('SHA-256', data)
      const hashArray = Array.from(new Uint8Array(hashBuffer))
      return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('')
    },
    async fetchFile(filePath) {
      const scope = window.openc3Scope || 'DEFAULT'
      let objectPath = `${scope}/targets_modified/${filePath}`
      let response = await Api.get(
        `/openc3-api/storage/download_file/${encodeURIComponent(objectPath)}`,
        {
          params: { bucket: 'OPENC3_CONFIG_BUCKET' },
          headers: { 'Ignore-Errors': '404,500' },
        },
      ).catch(() => null)

      if (!response || response.status === 404) {
        objectPath = `${scope}/targets/${filePath}`
        response = await Api.get(
          `/openc3-api/storage/download_file/${encodeURIComponent(objectPath)}`,
          { params: { bucket: 'OPENC3_CONFIG_BUCKET' } },
        )
      }

      if (response?.data?.contents) {
        return atob(response.data.contents)
      }
      throw new Error('File not found')
    },
    async copyChecksum(file) {
      if (!file.checksum) return
      try {
        await navigator.clipboard.writeText(file.checksum)
        file.copied = true
        setTimeout(() => (file.copied = false), 2000)
      } catch (err) {
        // eslint-disable-next-line no-console
        console.error('Failed to copy checksum:', err)
      }
    },
    async fetchChecksums() {
      this.loading = true
      this.files.forEach((f) => {
        f.checksum = null
        f.error = null
      })

      const results = await Promise.all(
        this.files.map((file) =>
          this.fetchFile(file.path)
            .then((content) => this.computeChecksum(content))
            .catch((err) => ({ error: err.message || 'File not found' })),
        ),
      )

      results.forEach((result, i) => {
        if (result?.error) {
          this.files[i].error = result.error
        } else {
          this.files[i].checksum = result
        }
      })

      this.loading = false
    },
  },
}
</script>

<style scoped>
.overflow-wrap-anywhere {
  overflow-wrap: anywhere;
}
</style>
