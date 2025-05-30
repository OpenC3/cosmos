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
  <!-- Edit dialog -->
  <v-dialog v-model="show" persistent width="75vw">
    <v-card>
      <v-toolbar height="24">
        <v-btn
          class="mx-2"
          icon="mdi-delete"
          variant="text"
          density="compact"
          data-test="delete-screen-icon"
          @click="deleteScreen"
        />
        <v-spacer />
        <span> Edit Screen: {{ target }} {{ screen }} </span>
        <v-spacer />
        <v-btn
          class="mx-2"
          icon="mdi-download"
          variant="text"
          density="compact"
          data-test="download-screen-icon"
          @click="downloadScreen"
        />
      </v-toolbar>
      <v-card-text style="max-height: 90vh">
        <v-row class="mt-3"> Upload a screen file. </v-row>
        <v-row no-gutters align="center">
          <v-btn
            :disabled="!file"
            color="primary"
            class="mr-3"
            data-test="edit-screen-load"
            @click="loadFile"
          >
            Load
          </v-btn>
          <v-file-input
            v-model="file"
            truncate-length="15"
            accept=".txt"
            label="Click to select .txt screen file."
          />
        </v-row>
        <v-row class="mb-2"> Edit the screen definition. </v-row>
        <v-row class="mb-2">
          <pre
            ref="editor"
            class="editor"
            @contextmenu.prevent="showContextMenu"
          ></pre>
          <v-menu v-model="contextMenu" :target="[menuX, menuY]">
            <v-list>
              <v-list-item link>
                <v-list-item-title @click="openDocumentation">
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
        <!-- Make the error messages a max height and scrollable -->
        <v-row style="max-height: 120px; overflow-y: auto">
          <div v-for="(error, index) in editErrors" :key="index">
            <span class="text-red" v-text="error" />
          </div>
        </v-row>
        <v-row class="mt-5">
          <span>
            Ctrl-space brings up autocomplete. Right click keywords for
            documentation.
          </span>
          <v-spacer />
          <v-btn
            class="mx-2"
            variant="outlined"
            data-test="edit-screen-cancel"
            @click="$emit('cancel')"
          >
            Cancel
          </v-btn>
          <v-btn
            class="mx-2"
            color="primary"
            data-test="edit-screen-save"
            @click="$emit('save', editor.getValue())"
          >
            Save
          </v-btn>
        </v-row>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-text'
import 'ace-builds/src-min-noconflict/theme-twilight'
import 'ace-builds/src-min-noconflict/ext-language_tools'
import 'ace-builds/src-min-noconflict/ext-searchbox'
import { ScreenCompleter } from './autocomplete'
import { AceEditorUtils } from './ace'

export default {
  props: {
    modelValue: Boolean,
    target: {
      type: String,
      default: '',
    },
    screen: {
      type: String,
      default: '',
    },
    definition: {
      type: String,
      default: '',
    },
    keywords: {
      type: Array,
      default: () => [],
    },
    errors: {
      type: Array,
      default: () => [],
    },
  },
  emits: ['cancel', 'delete', 'save', 'update:modelValue'],
  data() {
    return {
      file: null,
      docsKeyword: '',
      contextMenu: false,
      menuX: 0,
      menuY: 0,
    }
  },
  computed: {
    editErrors: function () {
      if (this.definition === '' && !this.file) {
        return ['Input can not be blank.']
      }
      if (this.errors.length !== 0) {
        let messages = new Set()
        let result = []
        const sortedErrors = this.errors.toSorted(
          (a, b) => a.lineNumber - b.lineNumber,
        )
        for (const error of sortedErrors) {
          let msg = `At ${error.lineNumber}: (${error.line}) ${error.message}.`
          if (error.usage) {
            msg += ` Usage: ${error.usage}`
          }
          result.push(msg)
          messages.add(error.message)
        }
        return result
      }
      return []
    },
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
  },
  mounted: function () {
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
    this.editor.setValue(this.definition)
    this.editor.clearSelection()
    AceEditorUtils.applyVimModeIfEnabled(this.editor)
    this.editor.focus()
  },
  beforeUnmount() {
    this.editor.destroy()
    this.editor.container.remove()
  },
  methods: {
    toggleVimMode: function () {
      AceEditorUtils.toggleVimMode(this.editor)
    },
    showContextMenu: function (event) {
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
    buildScreenMode() {
      let oop = ace.require('ace/lib/oop')
      let TextHighlightRules = ace.require(
        'ace/mode/text_highlight_rules',
      ).TextHighlightRules

      let list = this.keywords.join('|')
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
              regex: new RegExp(`^\\s*(${list})\\b`),
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
    downloadScreen: function () {
      const blob = new Blob([this.editor.getValue()], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', `${this.screen.toLowerCase()}.txt`)
      link.click()
    },
    loadFile: function () {
      const fileReader = new FileReader()
      fileReader.readAsText(this.file)
      const that = this
      fileReader.onload = function () {
        that.editor.setValue(fileReader.result)
        that.file = null
      }
    },
    deleteScreen: function () {
      this.$dialog
        .confirm(`Are you sure you want to delete this screen?!`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          this.$emit('delete')
        })
    },
  },
}
</script>

<style>
.ace_autocomplete {
  width: 60vw !important;
}
</style>
<style scoped>
.editor {
  height: 45vh;
  width: 75vw;
  position: relative;
  font-size: 16px;
}

.v-textarea :deep(textarea) {
  padding: 5px;
}
</style>
