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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div class="screen-editor-container">
    <v-row no-gutters align="center" class="mb-2">
      <v-btn
        :disabled="!file"
        color="primary"
        size="small"
        class="mr-3"
        data-test="screen-editor-load"
        @click="loadFile"
      >
        Load
      </v-btn>
      <v-file-input
        v-model="file"
        truncate-length="15"
        accept=".txt"
        label="Click to select .txt screen file."
        density="compact"
        hide-details
        style="max-width: 300px"
      />
      <v-spacer />
      <v-btn
        icon="mdi-download"
        variant="text"
        density="compact"
        title="Download"
        data-test="screen-editor-download"
        @click="downloadContent"
      />
    </v-row>
    <v-row no-gutters class="mb-2">
      <pre
        ref="editor"
        class="screen-editor"
        :style="{ height: height, width: '100%' }"
        @contextmenu.prevent="showContextMenu"
      ></pre>
      <v-menu v-model="contextMenu" :target="[menuX, menuY]">
        <v-list>
          <v-list-item link @click="openDocumentation">
            <v-list-item-title>
              {{ docsKeyword }} documentation
            </v-list-item-title>
          </v-list-item>
          <v-divider />
          <v-list-item
            title="Toggle Vim mode"
            prepend-icon="extras:vim"
            @click="toggleVimMode"
          />
        </v-list>
      </v-menu>
    </v-row>
    <v-row no-gutters>
      <span class="text-caption text-grey">
        Ctrl-space brings up autocomplete. Right click keywords for
        documentation.
      </span>
    </v-row>
  </div>
</template>

<script>
import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-text'
import 'ace-builds/src-min-noconflict/theme-twilight'
import 'ace-builds/src-min-noconflict/ext-language_tools'
import 'ace-builds/src-min-noconflict/ext-searchbox'
import { ScreenCompleter } from './autocomplete'
import { AceEditorUtils } from './ace'
import { Api } from '@openc3/js-common/services'

export default {
  props: {
    modelValue: {
      type: String,
      default: '',
    },
    keywords: {
      type: Array,
      default: () => [],
    },
    height: {
      type: String,
      default: '45vh',
    },
    filename: {
      type: String,
      default: 'screen.txt',
    },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      editor: null,
      file: null,
      loadedKeywords: [],
      docsKeyword: '',
      contextMenu: false,
      menuX: 0,
      menuY: 0,
    }
  },
  computed: {
    effectiveKeywords() {
      // Use prop keywords if provided, otherwise use loaded keywords
      return this.keywords.length > 0 ? this.keywords : this.loadedKeywords
    },
  },
  watch: {
    modelValue(newValue) {
      if (this.editor && this.editor.getValue() !== newValue) {
        this.editor.setValue(newValue)
        this.editor.clearSelection()
      }
    },
    effectiveKeywords() {
      if (this.editor) {
        const screenMode = this.buildScreenMode()
        this.editor.session.setMode(new screenMode())
      }
    },
  },
  created() {
    // Load keywords from API if not provided via prop
    if (this.keywords.length === 0) {
      this.loadKeywords()
    }
  },
  mounted() {
    this.initEditor()
  },
  beforeUnmount() {
    if (this.editor) {
      this.editor.destroy()
      this.editor.container.remove()
    }
  },
  methods: {
    async loadKeywords() {
      try {
        const response = await Api.get('/openc3-api/autocomplete/keywords/screen')
        this.loadedKeywords = response.data
      } catch (error) {
        console.error('Error loading screen keywords:', error)
      }
    },
    initEditor() {
      this.editor = ace.edit(this.$refs.editor)
      this.editor.setTheme('ace/theme/twilight')
      const screenMode = this.buildScreenMode()
      this.editor.session.setMode(new screenMode())
      this.editor.session.setTabSize(2)
      this.editor.session.setUseWrapMode(true)
      this.editor.$blockScrolling = Infinity
      this.editor.setOption('enableBasicAutocompletion', true)
      this.editor.setOption('enableLiveAutocompletion', true)
      this.editor.completers = [new ScreenCompleter()]
      this.editor.setHighlightActiveLine(false)
      this.editor.setValue(this.modelValue)
      this.editor.clearSelection()
      AceEditorUtils.applyVimModeIfEnabled(this.editor)
      this.editor.focus()

      this.editor.session.on('change', () => {
        this.$emit('update:modelValue', this.editor.getValue())
      })
    },
    getValue() {
      return this.editor ? this.editor.getValue() : this.modelValue
    },
    buildScreenMode() {
      let oop = ace.require('ace/lib/oop')
      let TextHighlightRules = ace.require(
        'ace/mode/text_highlight_rules',
      ).TextHighlightRules

      let list = this.effectiveKeywords.join('|')
      let OpenC3HighlightRules = function () {
        this.$rules = {
          start: [
            {
              token: 'comment',
              regex: '#.*$',
            },
            {
              token: 'string',
              regex: '".*?"',
            },
            {
              token: 'string',
              regex: "'.*?'",
            },
            {
              token: 'constant.numeric',
              regex: '\\b\\d+(?:\\.\\d+)?\\b',
            },
            {
              token: 'keyword',
              regex: list ? new RegExp(`^\\s*(${list})\\b`) : /(?!)/,
            },
          ],
        }
        this.normalizeRules()
      }
      oop.inherits(OpenC3HighlightRules, TextHighlightRules)
      let Mode = function () {
        this.HighlightRules = OpenC3HighlightRules
      }
      let TextMode = ace.require('ace/mode/text').Mode
      oop.inherits(Mode, TextMode)
      ;(function () {
        this.$id = 'ace/mode/openc3'
      }).call(Mode.prototype)
      return Mode
    },
    toggleVimMode() {
      AceEditorUtils.toggleVimMode(this.editor)
    },
    showContextMenu(event) {
      this.menuX = event.pageX
      this.menuY = event.pageY

      let position = this.editor.getCursorPosition()
      let token = this.editor.session.getTokenAt(position.row, position.column)
      if (token) {
        let value = token.value.trim()
        if (value.includes(' ')) {
          this.docsKeyword = value.split(' ')[0]
        } else {
          this.docsKeyword = value
        }
        this.contextMenu = true
      }
    },
    openDocumentation() {
      window.open(
        `${
          window.location.origin
        }/tools/staticdocs/docs/configuration/telemetry-screens#${this.docsKeyword.toLowerCase()}`,
        '_blank',
      )
    },
    downloadContent() {
      const blob = new Blob([this.editor.getValue()], {
        type: 'text/plain',
      })
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', this.filename)
      link.click()
    },
    loadFile() {
      const fileReader = new FileReader()
      fileReader.readAsText(this.file)
      const that = this
      fileReader.onload = function () {
        that.editor.setValue(fileReader.result)
        that.editor.clearSelection()
        that.file = null
      }
    },
  },
}
</script>

<style scoped>
.screen-editor-container {
  width: 100%;
}

.screen-editor {
  width: 100%;
  position: relative;
  font-size: 16px;
}
</style>

<style>
.ace_autocomplete {
  width: 60vw !important;
}
</style>
