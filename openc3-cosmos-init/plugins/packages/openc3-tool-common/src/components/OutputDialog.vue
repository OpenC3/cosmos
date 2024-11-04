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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" width="85vw">
    <v-card>
      <v-system-bar>
        <v-spacer />
        <span v-text="title" />
        <v-spacer />
        <div class="mx-2">
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon data-test="downloadIcon" @click="download">
                  mdi-download
                </v-icon>
              </div>
            </template>
            <span> Download </span>
          </v-tooltip>
        </div>
      </v-system-bar>
      <v-card-text>
        <pre class="editor" ref="editor"></pre>
      </v-card-text>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn variant="flat" @click="close"> Ok </v-btn>
      </v-card-actions>
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

export default {
  props: {
    content: {
      type: String,
      required: true,
    },
    type: String,
    name: String,
    value: Boolean, // value is the default prop when using v-model
    filename: {
      type: String,
      required: false,
    },
  },
  data() {
    return {
      editor: null,
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
    this.editor.focus()
    this.editor.setReadOnly(true)
  },
  beforeDestroy() {
    if (this.editor) {
      this.editor.destroy()
    }
  },
  computed: {
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
    title: function () {
      return `${this.type}: ${this.name}`
    },
  },
  methods: {
    close: function () {
      this.show = !this.show
    },
    download: function () {
      const blob = new Blob([this.editor.getValue()], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      let filename = `${this.type.toLowerCase()}_${this.name.toLowerCase()}.json`
      if (this.filename) {
        filename = this.filename
      }
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', filename)
      link.click()
    },
    buildPluginMode() {
      let oop = ace.require('ace/lib/oop')
      let JsonHighlightRules = ace.require(
        'ace/mode/json_highlight_rules'
      ).JsonHighlightRules

      let MatchingBraceOutdent = ace.require(
        'ace/mode/matching_brace_outdent'
      ).MatchingBraceOutdent
      let CstyleBehaviour = ace.require(
        'ace/mode/behaviour/cstyle'
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
  },
}
</script>

<style scoped>
.editor {
  height: 75vh;
  width: 80vw;
  position: relative;
  font-size: 16px;
}
.v-textarea :deep(textarea) {
  padding: 5px;
}
</style>
