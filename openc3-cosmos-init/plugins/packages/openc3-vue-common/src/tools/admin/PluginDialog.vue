<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" persistent width="80vw" @keydown.esc="close">
    <v-card>
      <v-card-title>{{ pluginName }}</v-card-title>
      <v-card-text class="pt-0">
        <v-alert
          v-if="existingPluginTxt !== null"
          type="warning"
          variant="tonal"
          class="mb-3"
        >
          The existing plugin.txt is different from the {{ pluginName }}'s
          plugin.txt. Navigate the diffs making whatever edits you want before
          installing. You may want to update {{ pluginName }}'s plugin.txt going
          forward.
        </v-alert>
        <v-tabs v-model="tab" class="mb-3">
          <v-tab :key="0"> Variables </v-tab>
          <v-tab :key="1"> plugin.txt </v-tab>
        </v-tabs>
        <form @submit.prevent="onSubmit">
          <v-window v-model="tab">
            <v-window-item :value="0" eager="true" class="tab">
              <div
                v-if="Object.keys(localVariables).length === 0"
                class="text-body-1 text-medium-emphasis pa-3"
              >
                No variables defined for this plugin.
              </div>
              <v-row v-else class="pt-2">
                <v-col
                  v-for="(variable, name) in localVariables"
                  :key="name"
                  cols="12"
                  sm="6"
                  md="3"
                >
                  <!-- Combobox for variables with options -->
                  <v-combobox
                    v-if="hasOptions(variable)"
                    v-model="variable.value"
                    :items="getOptionItems(variable)"
                    item-title="text"
                    item-value="value"
                    :return-object="false"
                    :label="name"
                    :hint="getDescription(variable)"
                    persistent-hint
                    density="comfortable"
                    variant="outlined"
                    data-test="variable-combobox"
                  >
                    <template #item="{ item, props }">
                      <v-list-item v-bind="props">
                        <template #title>
                          {{ item.raw.text }}
                        </template>
                      </v-list-item>
                    </template>
                  </v-combobox>

                  <!-- Text field for variables without options -->
                  <v-text-field
                    v-else
                    v-model="variable.value"
                    :label="name"
                    :hint="getDescription(variable)"
                    persistent-hint
                    clearable
                    density="comfortable"
                    variant="outlined"
                    data-test="variable-text"
                  />
                </v-col>
              </v-row>
            </v-window-item>
            <v-window-item
              v-if="existingPluginTxt === null"
              :value="1"
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
            <v-window-item v-else :value="1" eager="true" class="tab">
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
              data-test="edit-cancel"
              @click.prevent="close"
            >
              Cancel
            </v-btn>
            <v-btn
              variant="flat"
              data-test="edit-submit"
              @click="checkVersionAndSubmit"
            >
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
import AceDiff from 'ace-diff'
import 'ace-diff/styles.css'
import 'ace-diff/styles-twilight.css'
import { Api } from '@openc3/js-common/services'
import { toRaw } from 'vue'
import * as semver from 'semver'
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
      default: null,
    },
    storeId: {
      type: Number,
      required: false,
      default: null,
    },
    minCosmosVersion: {
      type: String,
      required: false,
      default: undefined,
    },
    modelValue: Boolean, // modelValue is the default prop when using v-model
  },
  emits: ['callback', 'update:modelValue'],
  data() {
    return {
      installedCosmosVersion: null,
      tab: 0,
      localVariables: {},
      localPluginTxt: '',
      localExistingPluginTxt: null,
      editor: null,
      differ: null,
      contextMenu: false,
      menuX: 0,
      menuY: 0,
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
        // Deep copy and normalize variables to new format
        // Handles both old format (string values) and new format (hash with value/description/options)
        const rawVariables = JSON.parse(JSON.stringify(this.variables))
        this.localVariables = {}
        for (const [name, variable] of Object.entries(rawVariables)) {
          if (typeof variable === 'string') {
            // Old format: convert to new format
            this.localVariables[name] = { value: variable }
          } else {
            // New format: use as-is
            this.localVariables[name] = variable
          }
        }
        this.localPluginTxt = this.pluginTxt.slice()
        if (this.existingPluginTxt !== null) {
          this.localExistingPluginTxt = this.existingPluginTxt.slice()
        }
      },
    },
  },
  created() {
    Api.get('/openc3-api/info').then(({ data }) => {
      this.installedCosmosVersion = data.version
    })
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
      let keywords = ['VARIABLE', 'VARIABLE_DESCRIPTION', 'VARIABLE_STATE']
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
    checkVersionAndSubmit: function () {
      const versionsAreCompatible =
        !this.installedCosmosVersion ||
        !this.minCosmosVersion ||
        semver.gte(this.installedCosmosVersion, this.minCosmosVersion)
      if (versionsAreCompatible) {
        this.submit()
      } else {
        this.$dialog
          .confirm(
            `This plugin requires a minimum COSMOS version of ${this.minCosmosVersion}, which is greater than your installed version (${this.installedCosmosVersion}). Install anyway?`,
            {
              okText: 'Install',
              cancelText: 'Cancel',
            },
          )
          .then((dialog) => {
            this.submit()
          })
          .catch((error) => {
            this.close()
          })
      }
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
        store_id: this.storeId,
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
    // Helper methods for variable display
    hasOptions(variable) {
      return variable.options && variable.options.length > 0
    },
    getDescription(variable) {
      return variable.description || ''
    },
    getOptionItems(variable) {
      if (!variable.options) return []
      return variable.options.map((opt) => ({
        text: opt.text || opt.value,
        value: opt.value,
      }))
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
.tab {
  background-color: var(--color-background-surface-default);
}
.v-textarea :deep(textarea) {
  padding: 5px;
}
</style>
