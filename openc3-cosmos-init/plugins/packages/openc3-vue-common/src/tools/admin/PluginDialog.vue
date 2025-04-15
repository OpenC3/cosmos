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
  <v-dialog persistent v-model="show" width="80vw">
    <v-card>
      <v-card-text>
        <v-card-title>{{ pluginName }} </v-card-title>
        <v-row v-if="existingPluginTxt !== null" class="notice d-flex flex-row">
          <v-icon size="x-large" start color="yellow"> mdi-alert-box </v-icon>
          <div style="flex: 1">
            The existing plugin.txt is different from the {{ pluginName }}'s
            plugin.txt. Navigate the diffs making whatever edits you want before
            installing. You may want to update {{ pluginName }}'s plugin.txt
            going forward.
          </div>
        </v-row>
        <v-row class="pb-3 pr-3">
          <v-tabs v-model="tab" class="ml-3">
            <v-tab :key="0"> Variables </v-tab>
            <v-tab :key="1"> plugin.txt </v-tab>
          </v-tabs>
        </v-row>
        <form @submit.prevent="onSubmit">
          <v-window v-model="tab">
            <v-window-item :key="0" eager="true" class="tab">
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
            </v-window-item>
            <v-window-item
              v-if="existingPluginTxt === null"
              :key="1 + '-new'"
              eager="true"
              class="tab"
            >
              <v-row class="pa-3">
                <v-col> This can be edited before installation. </v-col>
              </v-row>
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
            </v-window-item>
            <v-window-item
              v-else
              :key="1 + '-existing'"
              eager="true"
              class="tab"
            >
              <v-row class="pa-3">
                <v-col>
                  Existing plugin.txt. This can be edited before installation.
                </v-col>
                <v-col class="ml-6">
                  Uneditable plugin.txt from the new plugin.
                </v-col>
              </v-row>
              <pre ref="editor" class="editor"></pre>
            </v-window-item>
          </v-window>

          <v-card-actions class="px-2 mt-2">
            <div v-if="existingPluginTxt !== null">
              <v-btn variant="text" @click="nextDiff"> Next Diff </v-btn>
              <v-btn variant="text" @click="previousDiff">
                Previous Diff
              </v-btn>
            </div>
            <v-spacer />
            <v-btn
              variant="outlined"
              @click.prevent="close"
              data-test="edit-cancel"
            >
              Cancel
            </v-btn>
            <v-btn variant="flat" @click="submit" data-test="edit-submit">
              Install
            </v-btn>
          </v-card-actions>
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
import AceDiff from '@openc3/ace-diff'
import '@openc3/ace-diff/dist/ace-diff-dark.min.css'
import { toRaw } from 'vue'
import { AceEditorUtils } from '../../components/ace'

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
    modelValue: Boolean, // modelValue is the default prop when using v-model
  },
  data() {
    return {
      tab: 0,
      localVariables: [],
      localPluginTxt: '',
      localExistingPluginTxt: null,
      editor: null,
      differ: null,
      contextMenu: false,
      menuX: 0,
      menuY: 0,
    }
  },
  mounted() {
    const pluginMode = this.buildPluginMode()
    if (this.existingPluginTxt === null) {
      this.editor = ace.edit(this.$refs.editor)
      this.editor.setTheme('ace/theme/twilight')
      this.editor.session.setMode(new pluginMode())
      this.editor.session.setTabSize(2)
      this.editor.session.setUseWrapMode(true)
      this.editor.$blockScrolling = Infinity
      this.editor.setHighlightActiveLine(false)
      this.editor.setValue(this.localPluginTxt)
      this.editor.clearSelection()
      AceEditorUtils.applyVimModeIfEnabled(this.editor)
      this.editor.focus()
    } else {
      this.tab = 1 // Show the diff right off the bat
      this.differ = new AceDiff({
        element: this.$refs.editor,
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
      
      // Apply vim mode if enabled to both editor instances
      AceEditorUtils.applyVimModeIfEnabled(this.differ.getEditors().left)
      AceEditorUtils.applyVimModeIfEnabled(this.differ.getEditors().right)
      
      this.curDiff = -1 // so the first will be 0
    }
  },
  beforeUnmount() {
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
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
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
  },
  methods: {
    previousDiff() {
      this.curDiff--
      if (this.curDiff < 0) {
        this.curDiff = this.differ.diffs.length - 1
      }
      this.scrollToCurDiff()
    },
    nextDiff() {
      this.curDiff++
      if (this.curDiff >= this.differ.diffs.length) {
        this.curDiff = 0
      }
      this.scrollToCurDiff()
    },
    scrollToCurDiff() {
      if (this.differ.diffs.length === 0) return
      let lrow = this.differ.diffs[this.curDiff].leftStartLine
      let rrow = this.differ.diffs[this.curDiff].rightStartLine
      // Give it a little breathing room
      if (lrow > 5) {
        lrow -= 5
      }
      if (rrow > 5) {
        rrow -= 5
      }
      this.differ.getEditors().left.scrollToLine(lrow)
      this.differ.getEditors().right.scrollToLine(rrow)
    },
    buildPluginMode() {
      let oop = ace.require('ace/lib/oop')
      let RubyHighlightRules = ace.require(
        'ace/mode/ruby_highlight_rules',
      ).RubyHighlightRules

      // TODO: Grab from code
      let keywords = ['VARIABLE']
      let regex = new RegExp(`(\\b${keywords.join('\\b|\\b')}\\b)`)
      let PluginHighlightRules = function () {
        RubyHighlightRules.call(this)
        // add openc3 rules to the ruby rules
        for (let rule in this.$rules) {
          this.$rules[rule].unshift({
            regex: regex,
            token: 'support.function',
          })
        }
      }
      oop.inherits(PluginHighlightRules, RubyHighlightRules)

      let MatchingBraceOutdent = ace.require(
        'ace/mode/matching_brace_outdent',
      ).MatchingBraceOutdent
      let CstyleBehaviour = ace.require(
        'ace/mode/behaviour/cstyle',
      ).CstyleBehaviour
      let FoldMode = ace.require('ace/mode/folding/ruby').FoldMode
      let Mode = function () {
        this.HighlightRules = PluginHighlightRules
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
    submit: function () {
      if (this.existingPluginTxt === null) {
        this.emitSubmit(this.editor.getValue().split('\n'))
      } else {
        // Existing plugin.txt with all diffs resolved
        if (this.differ.diffs.length === 0) {
          this.emitSubmit(this.differ.getEditors().left.getValue().split('\n'))
        } else {
          // Existing plugin.txt with unresolved diffs
          this.$dialog
            .confirm(
              `Diffs still detected! Install using 'Existing plugin.txt' (left) and ignore additional changes in the new plugin.txt (right)?`,
              {
                okText: 'Install',
                cancelText: 'Cancel',
              },
            )
            .then((dialog) => {
              this.emitSubmit(
                this.differ.getEditors().left.getValue().split('\n'),
              )
            })
            .catch((error) => {
              // Cancelled, do nothing
            })
        }
      }
    },
    emitSubmit(lines) {
      let pluginHash = {
        name: this.pluginName,
        variables: toRaw(this.localVariables),
        plugin_txt_lines: lines,
      }
      this.$emit('callback', pluginHash)
    },
    close: function () {
      this.show = !this.show
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
      if (this.editor) {
        AceEditorUtils.toggleVimMode(this.editor)
        // don't worry about this.differ since AceDiff replaces the editor anyway, and thus there's no context menu
      }
    },
  },
}
</script>

<style scoped>
.editor {
  height: 50vh;
  position: relative;
  font-size: 16px;
}

.notice {
  font-size: 20px;
  margin: 10px;
}
.tab {
  background-color: var(--color-background-surface-default);
}
.v-textarea :deep(textarea) {
  padding: 5px;
}
</style>
