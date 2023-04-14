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
  <v-dialog persistent v-model="show" width="80vw">
    <v-card>
      <v-card-text>
        <v-row class="mt-3">
          <v-col cols="12">
            <h3>{{ pluginName }}</h3>
          </v-col>
        </v-row>
        <v-row v-if="existingPluginTxt !== null" class="notice">
          The current plugin.txt is different from the plugin.txt found in the
          gem! See the diff on the plugin.txt tab and make whatever edits
          necessary before installing. You may want to update {{ pluginName }}'s
          plugin.txt going forward.
        </v-row>
        <v-row class="pb-3">
          <v-tabs v-model="tab" background-color="primary" dark>
            <v-tab :key="0"> Variables </v-tab>
            <v-tab v-if="existingPluginTxt === null" :key="1">
              plugin.txt
            </v-tab>
            <v-tab v-else :key="1"> plugin.txt </v-tab>
          </v-tabs>
        </v-row>
        <form v-on:submit.prevent="submit">
          <v-tabs-items v-model="tab">
            <v-tab-item :key="0">
              <div class="pa-3">
                <v-row class="mt-3">
                  <div v-for="(value, name) in localVariables" :key="name">
                    <v-col style="width: 220px">
                      <v-text-field
                        clearable
                        type="text"
                        :label="name"
                        v-model="localVariables[name]"
                      />
                    </v-col>
                  </div>
                </v-row>
              </div>
            </v-tab-item>
            <v-tab-item v-if="existingPluginTxt === null" :key="1">
              <pre id="editor"></pre>
            </v-tab-item>
            <v-tab-item v-else :key="1">
              <v-row
                ><v-col
                  >Existing plugin.txt. This can be edited and will be
                  installed.</v-col
                ><v-col
                  >Uneditable plugin.txt from the new plugin.</v-col
                ></v-row
              >
              <div id="acediff"></div>
            </v-tab-item>
          </v-tabs-items>

          <v-row class="pt-5">
            <v-spacer />
            <v-btn
              @click.prevent="close"
              outlined
              class="mx-2"
              data-test="edit-cancel"
            >
              Cancel
            </v-btn>
            <v-btn
              class="mx-2"
              color="primary"
              type="submit"
              data-test="edit-submit"
            >
              Install
            </v-btn>
          </v-row>
        </form>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-ruby'
import 'ace-builds/src-min-noconflict/theme-twilight'
import 'ace-builds/src-min-noconflict/ext-language_tools'
import 'ace-builds/src-min-noconflict/ext-searchbox'
import AceDiff from 'ace-diff'
import 'ace-diff/dist/ace-diff.min.css'
import 'ace-diff/dist/ace-diff-dark.min.css'

export default {
  props: {
    pluginName: {
      type: String,
      required: true,
    },
    variables: {
      type: Object,
      required: true,
    },
    pluginTxt: {
      type: String,
      required: true,
    },
    existingPluginTxt: {
      type: String,
      required: false,
    },
    value: Boolean, // value is the default prop when using v-model
  },
  data() {
    return {
      tab: 0,
      localVariables: [],
      localPluginTxt: '',
      localExistingPluginTxt: null,
      editor: null,
      differ: null,
    }
  },
  beforeDestroy() {
    if (this.editor) {
      this.editor.destroy()
    }
    if (this.differ) {
      this.differ.destroy()
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
  },
  watch: {
    value: {
      immediate: true,
      handler: function () {
        this.localVariables = JSON.parse(JSON.stringify(this.variables)) // deep copy
        this.localPluginTxt = this.pluginTxt.slice()
        if (this.existingPluginTxt !== null) {
          this.localExistingPluginTxt = this.existingPluginTxt.slice()
        }
      },
    },
    tab: async function (newVal, oldVal) {
      if (newVal === 1) {
        if (this.existingPluginTxt === null && !this.editor) {
          const openPluginMode = this.buildPluginMode()
          await new Promise((r) => setTimeout(r, 300))
          this.editor = ace.edit('editor')
          this.editor.setTheme('ace/theme/twilight')
          this.editor.session.setMode(new openPluginMode())
          this.editor.session.setTabSize(2)
          this.editor.session.setUseWrapMode(true)
          this.editor.$blockScrolling = Infinity
          this.editor.setHighlightActiveLine(false)
          this.editor.setValue(this.localPluginTxt)
          this.editor.clearSelection()
          this.editor.focus()
        } else if (this.existingPluginTxt !== null && !this.differ) {
          const pluginMode = this.buildPluginMode()
          await new Promise((r) => setTimeout(r, 300))
          this.differ = new AceDiff({
            element: '#acediff',
            mode: new pluginMode(),
            theme: 'ace/theme/twilight',
            left: {
              content: this.localExistingPluginTxt,
              copyLinkEnabled: false,
            },
            right: {
              content: this.localPluginTxt,
              editable: false,
            },
          })
          // Match our existing editors
          this.differ.getEditors().left.setFontSize(16)
          this.differ.getEditors().right.setFontSize(16)
        }
      }
    },
  },
  methods: {
    buildPluginMode() {
      var oop = ace.require('ace/lib/oop')
      var RubyHighlightRules = ace.require(
        'ace/mode/ruby_highlight_rules'
      ).RubyHighlightRules

      // TODO: Grab from code
      let keywords = ['VARIABLE']
      let regex = new RegExp(`(\\b${keywords.join('\\b|\\b')}\\b)`)
      var PluginHighlightRules = function () {
        RubyHighlightRules.call(this)
        // add openc3 rules to the ruby rules
        for (var rule in this.$rules) {
          this.$rules[rule].unshift({
            regex: regex,
            token: 'support.function',
          })
        }
      }
      oop.inherits(PluginHighlightRules, RubyHighlightRules)

      var MatchingBraceOutdent = ace.require(
        'ace/mode/matching_brace_outdent'
      ).MatchingBraceOutdent
      var CstyleBehaviour = ace.require(
        'ace/mode/behaviour/cstyle'
      ).CstyleBehaviour
      var FoldMode = ace.require('ace/mode/folding/ruby').FoldMode
      var Mode = function () {
        this.HighlightRules = PluginHighlightRules
        this.$outdent = new MatchingBraceOutdent()
        this.$behaviour = new CstyleBehaviour()
        this.foldingRules = new FoldMode()
        this.indentKeywords = this.foldingRules.indentKeywords
      }
      var RubyMode = ace.require('ace/mode/ruby').Mode
      oop.inherits(Mode, RubyMode)
      ;(function () {
        this.$id = 'ace/mode/openc3'
      }).call(Mode.prototype)
      return Mode
    },
    submit: function () {
      let lines = ''
      if (this.existingPluginTxt === null) {
        lines = this.editor.getValue().split('\n')
      } else {
        lines = this.differ.getEditors().left.getValue().split('\n')
      }
      let pluginHash = {
        name: this.pluginName,
        variables: this.localVariables,
        plugin_txt_lines: lines,
      }
      this.$emit('submit', pluginHash)
    },
    close: function () {
      this.show = !this.show
    },
  },
}
</script>

<style scoped>
#editor,
#acediff {
  height: 50vh;
  width: 75vw;
  position: relative;
  font-size: 16px;
}

.notice {
  font-size: 20px;
  margin: 10px;
}
.v-card {
  background-color: var(--v-tertiary-darken2);
}
.v-textarea :deep(textarea) {
  padding: 5px;
  background-color: var(--v-tertiary-darken1) !important;
}
</style>
