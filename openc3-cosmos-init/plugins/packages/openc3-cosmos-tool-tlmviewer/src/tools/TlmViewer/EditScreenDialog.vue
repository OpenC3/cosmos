<!--
# Copyright 2022 OpenC3, Inc.
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
  <v-dialog v-model="show" width="75vw">
    <v-card>
      <v-system-bar>
        <div class="mx-2">
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon data-test="delete-screen-icon" @click="deleteScreen">
                  mdi-delete
                </v-icon>
              </div>
            </template>
            <span> Delete Screen </span>
          </v-tooltip>
        </div>
        <v-spacer />
        <span> Edit Screen: {{ target }} {{ screen }} </span>
        <v-spacer />
        <div class="mx-2">
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon
                  data-test="download-screen-icon"
                  @click="downloadScreen"
                >
                  mdi-download
                </v-icon>
              </div>
            </template>
            <span> Download Screen </span>
          </v-tooltip>
        </div>
      </v-system-bar>
      <v-card-text>
        <v-row class="mt-3"> Upload a screen file. </v-row>
        <v-row no-gutters align="center">
          <v-btn
            @click="loadFile"
            :disabled="!file"
            color="primary"
            class="mr-3"
            data-test="edit-screen-load"
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
        <v-row> Edit the screen definition. </v-row>
        <v-row class="mb-2">
          <pre id="editor"></pre>
        </v-row>
        <v-row v-for="(error, index) in editErrors" :key="index" class="my-3">
          <span class="red--text" v-text="error"></span>
        </v-row>
        <v-row>
          <span>Ctrl-space brings up autocomplete</span>
          <v-spacer />
          <v-btn
            @click="$emit('cancel')"
            class="mx-2"
            outlined
            data-test="edit-screen-cancel"
          >
            Cancel
          </v-btn>
          <v-btn
            @click="$emit('save', editor.getValue())"
            class="mx-2"
            color="primary"
            data-test="edit-screen-save"
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
import { ScreenCompleter } from '@/tools/TlmViewer/autocomplete'

export default {
  props: {
    value: Boolean, // value is the default prop when using v-model
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
  data() {
    return {
      file: null,
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
        for (const error of this.errors) {
          if (messages.has(error.message)) {
            continue
          }
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
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
  },
  mounted: function () {
    this.editor = ace.edit('editor')
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
    this.editor.focus()
  },
  beforeDestroy() {
    this.editor.destroy()
    this.editor.container.remove()
  },
  methods: {
    buildScreenMode() {
      var oop = ace.require('ace/lib/oop')
      var TextHighlightRules = ace.require(
        'ace/mode/text_highlight_rules'
      ).TextHighlightRules

      let list = this.keywords.join('|')
      var OpenC3HighlightRules = function () {
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
      var Mode = function () {
        this.HighlightRules = OpenC3HighlightRules
      }
      var TextMode = ace.require('ace/mode/text').Mode
      oop.inherits(Mode, TextMode)
      ;(function () {
        this.$id = 'ace/mode/openc3'
      }.call(Mode.prototype))
      return Mode
    },
    downloadScreen: function () {
      const blob = new Blob([this.editor.getValue()], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', `${this.target}_${this.screen}.txt`)
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
#editor {
  height: 50vh;
  width: 75vw;
  font-size: 16px;
}
.v-card {
  background-color: var(--v-tertiary-darken2);
}
.v-textarea :deep(textarea) {
  padding: 5px;
  background-color: var(--v-tertiary-darken1) !important;
}
</style>
