<!--
# Copyright 2025 OpenC3, Inc.
# All Rights Reserved.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card :style="computedStyle">
    <v-card-title class="d-flex align-center pa-2">
      <span class="text-caption text-medium-emphasis font-weight-regular">
        {{ filePath }}
      </span>
      <v-spacer />
      <v-btn
        size="x-small"
        icon="mdi-refresh"
        variant="text"
        :loading="loading"
        @click="fetchFile"
      />
    </v-card-title>
    <v-divider />
    <v-card-text class="pa-0">
      <v-checkbox
        v-model="prettyPrint"
        label="Pretty print"
        density="compact"
        hide-details
        class="ml-2"
      />
      <pre class="ma-0 pa-2" :style="contentStyle">{{ formattedContent }}</pre>
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
      filePath: '',
      fileContent: 'Loading...',
      loading: false,
      width: 600,
      height: 300,
      prettyPrint: false,
    }
  },
  computed: {
    contentStyle() {
      return {
        width: this.width + 'px',
        height: this.height + 'px',
        overflow: 'auto',
        fontFamily: 'monospace',
        fontSize: '12px',
        whiteSpace: 'pre',
      }
    },
    formattedContent() {
      if (!this.prettyPrint) {
        return this.fileContent
      }
      try {
        const parsed = JSON.parse(this.fileContent)
        return JSON.stringify(parsed, null, 2)
      } catch {
        // Not valid JSON, return as-is
        return this.fileContent
      }
    },
  },
  created() {
    // Parameter 0: File path (required) e.g. "INST/procedures/test.txt"
    // Parameter 1: Width (optional, default 600)
    // Parameter 2: Height (optional, default 300)
    // Parameter 3: Pretty print (optional, default false) - "TRUE" or "FALSE"
    if (this.parameters[0]) {
      this.filePath = this.parameters[0]
    }
    if (this.parameters[1]) {
      this.width = parseInt(this.parameters[1])
    }
    if (this.parameters[2]) {
      this.height = parseInt(this.parameters[2])
    }
    if (this.parameters[3]) {
      this.prettyPrint = this.parameters[3].toUpperCase() === 'TRUE'
    }
  },
  mounted() {
    if (this.filePath) {
      this.fetchFile()
    }
  },
  methods: {
    async fetchFile() {
      if (!this.filePath) {
        this.fileContent =
          'Error: No file path specified. Usage: FILEDISPLAY "TARGET/path/to/file.txt"'
        return
      }
      this.loading = true
      try {
        const scope = window.openc3Scope || 'DEFAULT'
        // Try targets_modified first, then fall back to targets
        // Use Ignore-Errors header to suppress toast for expected 404/500
        let objectPath = `${scope}/targets_modified/${this.filePath}`
        let response = await Api.get(
          `/openc3-api/storage/download_file/${encodeURIComponent(objectPath)}`,
          {
            params: { bucket: 'OPENC3_CONFIG_BUCKET' },
            headers: { 'Ignore-Errors': '404,500' },
          },
        ).catch(() => null)

        if (!response || response.status === 404) {
          objectPath = `${scope}/targets/${this.filePath}`
          response = await Api.get(
            `/openc3-api/storage/download_file/${encodeURIComponent(objectPath)}`,
            { params: { bucket: 'OPENC3_CONFIG_BUCKET' } },
          )
        }

        if (response?.data?.contents) {
          this.fileContent = atob(response.data.contents)
        } else {
          this.fileContent = 'Error: Could not load file'
        }
      } catch (error) {
        this.fileContent = `Error: ${error.message || error}`
      } finally {
        this.loading = false
      }
    },
  },
}
</script>

