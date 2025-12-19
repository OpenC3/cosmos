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
      <div ref="editor" :style="contentStyle"></div>
    </v-card-text>
  </v-card>
</template>

<script>
import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-json'
import 'ace-builds/src-min-noconflict/mode-ruby'
import 'ace-builds/src-min-noconflict/mode-python'
import 'ace-builds/src-min-noconflict/mode-text'
import 'ace-builds/src-min-noconflict/theme-twilight'
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
      editor: null,
    }
  },
  computed: {
    contentStyle() {
      return {
        width: this.width + 'px',
        height: this.height + 'px',
      }
    },
    aceMode() {
      const ext = this.filePath.split('.').pop()?.toLowerCase()
      const modeMap = {
        json: 'ace/mode/json',
        rb: 'ace/mode/ruby',
        py: 'ace/mode/python',
        txt: 'ace/mode/text',
      }
      return modeMap[ext] || 'ace/mode/text'
    },
  },
  created() {
    // Parameter 0: File path (required) e.g. "INST/procedures/test.txt"
    // Parameter 1: Width (optional, default 600)
    // Parameter 2: Height (optional, default 300)
    if (this.parameters[0]) {
      this.filePath = this.parameters[0]
    }
    if (this.parameters[1]) {
      this.width = parseInt(this.parameters[1])
    }
    if (this.parameters[2]) {
      this.height = parseInt(this.parameters[2])
    }
  },
  mounted() {
    this.editor = ace.edit(this.$refs.editor)
    this.editor.setTheme('ace/theme/twilight')
    this.editor.setReadOnly(true)
    this.editor.setShowPrintMargin(false)
    this.editor.setHighlightActiveLine(false)
    this.editor.renderer.setShowGutter(false)
    this.editor.renderer.setScrollMargin(8, 8, 0, 0)
    this.editor.renderer.setPadding(8)
    this.editor.setValue(this.fileContent, -1)

    if (this.filePath) {
      this.fetchFile()
    }
  },
  beforeUnmount() {
    if (this.editor) {
      this.editor.destroy()
      this.editor.container.remove()
    }
  },
  methods: {
    updateEditor() {
      if (this.editor) {
        this.editor.session.setMode(this.aceMode)
        this.editor.setValue(this.fileContent, -1)
      }
    },
    async fetchFile() {
      if (!this.filePath) {
        this.fileContent =
          'Error: No file path specified. Usage: FILEDISPLAY "TARGET/path/to/file.txt"'
        this.updateEditor()
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
        this.updateEditor()
      }
    },
  },
}
</script>

