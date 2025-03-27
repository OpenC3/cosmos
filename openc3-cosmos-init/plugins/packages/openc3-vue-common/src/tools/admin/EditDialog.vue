<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog :persistent="!readonly" v-model="show" width="80vw">
    <v-card>
      <form v-on:submit.prevent="submit">
        <v-toolbar height="24">
          <v-spacer />
          <span v-text="title" />
          <v-spacer />
          <div class="mx-2">
            <v-tooltip location="top">
              <template v-slot:activator="{ props }">
                <div v-bind="props">
                  <v-icon data-test="downloadIcon" @click="download">
                    mdi-download
                  </v-icon>
                </div>
              </template>
              <span> Download </span>
            </v-tooltip>
          </div>
        </v-toolbar>

        <v-card-text>
          <div class="pa-3">
            <div v-if="!readonly">
              <v-row class="mt-3"> Upload a file. </v-row>
              <v-row no-gutters align="center">
                <v-col cols="3">
                  <v-btn
                    block
                    color="success"
                    @click="loadFile"
                    :disabled="!file || loadingFile || readonly"
                    :loading="loadingFile"
                    data-test="editScreenLoadBtn"
                  >
                    Load
                    <template v-slot:loader>
                      <span>Loading...</span>
                    </template>
                  </v-btn>
                </v-col>
                <v-col cols="9">
                  <v-file-input
                    v-model="file"
                    accept=".json"
                    label="Click to select .json file."
                    :disabled="readonly"
                  />
                </v-col>
              </v-row>
            </div>
            <v-row no-gutters>
              <pre
                class="editor"
                ref="editor"
                @contextmenu.prevent="showContextMenu"
              ></pre>
              <v-menu v-model="contextMenu" :target="[menuX, menuY]">
                <v-list>
                  <v-list-item
                    title="Toggle Vim mode"
                    prepend-icon="extras:vim"
                    @click="toggleVimMode"
                  />
                </v-list>
              </v-menu>
            </v-row>
            <v-row class="my-3">
              <span class="text-red" v-show="error" v-text="error" />
            </v-row>
            <v-row>
              <v-spacer />
              <v-btn
                @click.prevent="close"
                variant="outlined"
                class="mx-2"
                data-test="editCancelBtn"
              >
                Cancel
              </v-btn>
              <v-btn
                v-if="!readonly"
                class="mx-2"
                color="primary"
                type="submit"
                data-test="editSubmitBtn"
                :disabled="!!error || readonly"
              >
                Save
              </v-btn>
            </v-row>
          </div>
        </v-card-text>
      </form>
    </v-card>
  </v-dialog>
</template>

<script>
import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-ruby'
import 'ace-builds/src-min-noconflict/mode-json'
import 'ace-builds/src-min-noconflict/theme-twilight'
import 'ace-builds/src-min-noconflict/ext-language_tools'
import 'ace-builds/src-min-noconflict/ext-searchbox'
import { AceEditorUtils } from '../../components/ace'

export default {
  props: {
    content: {
      type: String,
      required: true,
    },
    type: String,
    name: String,
    modelValue: Boolean,
    readonly: Boolean,
  },
  data() {
    return {
      editor: null,
      contextMenu: false,
      menuX: 0,
      menuY: 0,
    }
  },
  mounted() {
    const openPluginMode = this.buildPluginMode()
    this.editor = ace.edit(this.$refs.editor)
    this.editor.setTheme('ace/theme/twilight')
    this.editor.session.setMode(new openPluginMode())
    this.editor.session.setTabSize(2)
    this.editor.session.setUseWrapMode(true)
    this.editor.$blockScrolling = Infinity
    this.editor.setHighlightActiveLine(false)
    this.editor.setValue(this.content)
    this.editor.clearSelection()
    AceEditorUtils.applyVimModeIfEnabled(this.editor)
    this.editor.focus()
    if (this.readonly) {
      this.editor.setReadOnly(true)
    }
  },
  beforeUnmount() {
    if (this.editor) {
      this.editor.destroy()
    }
  },
  computed: {
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
    title: function () {
      return `${this.type}: ${this.name}`
    },
    error: function () {
      if (this.editor && this.editor.getValue() === '' && !this.file) {
        return 'Input can not be blank.'
      }
      return null
    },
  },
  methods: {
    submit: function () {
      this.$emit('submit', this.editor.getValue())
      this.show = !this.show
    },
    close: function () {
      this.show = !this.show
    },
    download: function () {
      const blob = new Blob([this.editor.getValue()], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute(
        'download',
        `${this.type.toLowerCase()}_${this.name.toLowerCase()}.json`,
      )
      link.click()
    },
    buildPluginMode() {
      let oop = ace.require('ace/lib/oop')
      let JsonHighlightRules = ace.require(
        'ace/mode/json_highlight_rules',
      ).JsonHighlightRules

      let MatchingBraceOutdent = ace.require(
        'ace/mode/matching_brace_outdent',
      ).MatchingBraceOutdent
      let CstyleBehaviour = ace.require(
        'ace/mode/behaviour/cstyle',
      ).CstyleBehaviour
      let FoldMode = ace.require('ace/mode/folding/ruby').FoldMode
      let Mode = function () {
        this.HighlightRules = JsonHighlightRules
        this.$outdent = new MatchingBraceOutdent()
        this.$behaviour = new CstyleBehaviour()
        this.foldingRules = new FoldMode()
        this.indentKeywords = this.foldingRules.indentKeywords
      }
      let RubyMode = ace.require('ace/mode/ruby').Mode
      oop.inherits(Mode, RubyMode)
      ;(function () {
        this.$id = 'ace/mode/openc3'
      }).call(Mode.prototype)
      return Mode
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
    toggleVimMode: function () {
      AceEditorUtils.toggleVimMode(this.editor)
    },
  },
}
</script>

<style scoped>
.editor {
  height: 50vh;
  width: 75vw;
  position: relative;
  font-size: 16px;
}
.v-textarea :deep(textarea) {
  padding: 5px;
}
</style>
