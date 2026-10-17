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
  <v-dialog
    v-model="show"
    persistent
    width="80vw"
    @keydown.esc.stop="handleEsc"
  >
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
              <!-- Markdown from PLUGIN_TEXT_START / PLUGIN_TEXT_END in plugin.txt -->
              <!-- eslint-disable vue/no-v-html -->
              <div
                v-if="pluginTextHtml"
                class="plugin-text pa-3"
                data-test="plugin-text"
                v-html="pluginTextHtml"
              />
              <!-- eslint-enable vue/no-v-html -->
              <div
                v-if="Object.keys(localVariables).length === 0"
                class="text-body-1 text-medium-emphasis pa-3"
              >
                No variables defined for this plugin.
              </div>
              <v-row v-else class="pt-2">
                <v-col
                  v-for="[name, variable] in visibleVariables"
                  :key="name"
                  cols="12"
                  sm="6"
                  md="3"
                >
                  <!-- Combobox for variables with options -->
                  <v-combobox
                    v-if="hasOptions(variable)"
                    :model-value="variable.value"
                    :items="getOptionItems(name, variable)"
                    item-title="text"
                    item-value="value"
                    :return-object="false"
                    :label="name"
                    :hint="getHint(name, variable)"
                    :loading="discoveryLoading[name] || false"
                    persistent-hint
                    density="comfortable"
                    variant="outlined"
                    data-test="variable-combobox"
                    @update:model-value="setVariableValue(name, $event)"
                  >
                    <template v-if="variable.discovery" #append-inner>
                      <v-btn
                        icon="mdi-refresh"
                        size="x-small"
                        variant="text"
                        :disabled="discoveryLoading[name] || false"
                        data-test="variable-discover"
                        @click.stop="runDiscovery(name)"
                      />
                    </template>
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
import DOMPurify from 'dompurify'
import { marked } from 'marked'
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
    pluginText: {
      type: String,
      required: false,
      default: null,
    },
    existingPluginTxt: {
      type: String,
      required: false,
      default: null,
    },
    storePluginId: {
      type: Number,
      required: false,
      default: null,
    },
    storeVersionId: {
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
      // VARIABLE_DISCOVERY results, loading state and errors by variable name
      discoveryResults: {},
      discoveryLoading: {},
      discoveryErrors: {},
      discoveryRuns: {},
      // Available bridges for the VARIABLE_BRIDGE variable: [{ value, text }]
      bridges: [],
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
    pluginTextHtml() {
      if (!this.pluginText) return ''
      return DOMPurify.sanitize(marked.parse(this.pluginText))
    },
    // Variables not hidden by the currently selected VARIABLE_STATE of another
    // variable (see VARIABLE_STATE_SHOW)
    visibleVariables() {
      return Object.entries(this.localVariables).filter(([name]) =>
        this.isVariableVisible(name),
      )
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
    Api.get('/openc3-api/info')
      .then(({ data }) => {
        this.installedCosmosVersion = data.version
      })
      .catch(console.error)
    if (
      Object.values(this.localVariables).some((variable) => variable.bridge)
    ) {
      this.loadBridges()
    }
    this.runAllDiscovery()
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
      this.editor.session.$undoManager.markClean() // because setting the initial content made it "dirty"
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
      let keywords = [
        'VARIABLE',
        'VARIABLE_DESCRIPTION',
        'VARIABLE_STATE',
        'VARIABLE_STATE_SHOW',
        'VARIABLE_STATE_SET',
        'VARIABLE_DISCOVERY',
        'VARIABLE_DISCOVERY_SET',
        'VARIABLE_BRIDGE',
        'PLUGIN_TEXT_START',
        'PLUGIN_TEXT_END',
      ]
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
        plugin_text: this.pluginText,
        store_plugin_id: this.storePluginId,
        store_version_id: this.storeVersionId,
      }
      this.$emit('callback', pluginHash)
    },
    close: function () {
      this.show = !this.show
    },
    handleEsc: function () {
      const isClean = this.editor.session.$undoManager.isClean()
      if (isClean) {
        this.close()
      } else {
        this.$dialog
          .confirm(
            'You have unsaved changes. Are you sure you want to close?',
            {
              okText: 'Close without saving',
              cancelText: 'Cancel',
            },
          )
          .then(() => {
            this.close()
          })
          .catch(() => {
            this.editor?.focus()
          })
      }
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
    // Set a variable and, if the new value selects a state, apply that
    // state's VARIABLE_STATE_SET values (cascading into other states)
    setVariableValue(name, value, visiting = new Set()) {
      const variable = this.localVariables[name]
      if (variable.value === value || visiting.has(name)) return
      visiting.add(name)
      variable.value = value
      const selected = variable.options?.find((opt) => opt.value === value)
      for (const [target, defaultValue] of Object.entries(
        selected?.set || {},
      )) {
        this.setVariableValue(target, defaultValue, visiting)
      }
      // Apply the VARIABLE_DISCOVERY_SETs of the discovery that found the value
      const discovered = this.discoveryResults[name]?.find(
        (result) => result.value === value,
      )
      if (discovered) {
        const discovery = variable.discovery[discovered.discoveryIndex]
        for (const [target, setValue] of Object.entries(discovery.set || {})) {
          this.setVariableValue(target, setValue, visiting)
        }
      }
      // Discovered values depend on the host behind the selected bridge
      if (
        variable.bridge &&
        this.bridges.some((bridge) => bridge.value === value)
      ) {
        this.runAllDiscovery()
      }
    },
    // List the bridges for the VARIABLE_BRIDGE variable's dropdown
    async loadBridges() {
      try {
        const response = await Api.get('/openc3-api/bridges/ALL', {
          headers: {
            Accept: 'application/json',
            // An empty list just leaves the bridge to be typed in
            'Ignore-Errors': '403,500,502,503,504',
          },
        })
        this.bridges = Object.values(response.data || {}).map((bridge) => ({
          value: bridge.name,
          text: bridge.app_public_key
            ? bridge.name
            : `${bridge.name} (not paired with openc3-app)`,
        }))
      } catch (error) {
        this.bridges = []
      }
    },
    // The bridge selected by VARIABLE_BRIDGE (or DEFAULT) used for discovery
    selectedBridge() {
      const variable = Object.values(this.localVariables).find(
        (variable) => variable.bridge,
      )
      return variable?.value || 'DEFAULT'
    },
    runAllDiscovery() {
      for (const [name, variable] of Object.entries(this.localVariables)) {
        if (variable.discovery) {
          this.runDiscovery(name)
        }
      }
    },
    // Helper methods for variable display
    isVariableVisible(name, visiting = new Set()) {
      if (visiting.has(name)) return true // Guard against circular references
      visiting.add(name)
      try {
        for (const [controlName, control] of Object.entries(
          this.localVariables,
        )) {
          if (!control.options) continue
          // Variables listed by any VARIABLE_STATE_SHOW of this variable are
          // only visible when the selected state lists them
          if (!control.options.some((opt) => opt.show?.includes(name))) continue
          // A hidden variable can't be selected so nothing it shows is visible
          if (!this.isVariableVisible(controlName, visiting)) return false
          const selected = control.options.find(
            (opt) => opt.value === control.value,
          )
          // Custom values that don't match a state don't affect visibility
          if (!selected) continue
          if (!selected.show?.includes(name)) return false
        }
        return true
      } finally {
        visiting.delete(name)
      }
    },
    // Ask the host (through openc3-app and the DEFAULT bridge) for the
    // possible values of a VARIABLE_DISCOVERY variable
    // Each of the variable's VARIABLE_DISCOVERYs runs in parallel and their
    // results are combined, remembering which discovery found each value
    // so its VARIABLE_DISCOVERY_SETs can be applied when it's selected.
    async runDiscovery(name) {
      const variable = this.localVariables[name]
      // Ignore results from an older run (e.g. before the bridge changed)
      const run = (this.discoveryRuns[name] || 0) + 1
      this.discoveryRuns[name] = run
      this.discoveryLoading[name] = true
      this.discoveryErrors[name] = null
      const bridge = this.selectedBridge()
      const outcomes = await Promise.allSettled(
        variable.discovery.map((entry) =>
          Api.post('/openc3-api/discovery', {
            data: { bridge, discovery: entry.discovery },
            headers: {
              Accept: 'application/json',
              'Content-Type': 'application/json',
              // Reported in the variable's hint rather than the global banner
              'Ignore-Errors': '500,502,503,504',
            },
          }),
        ),
      )
      if (this.discoveryRuns[name] !== run) return
      const results = []
      const errors = []
      outcomes.forEach((outcome, index) => {
        if (outcome.status === 'fulfilled') {
          for (const result of outcome.value.data || []) {
            results.push({ ...result, discoveryIndex: index })
          }
        } else {
          errors.push(
            outcome.reason.response?.data?.message || outcome.reason.message,
          )
        }
      })
      this.discoveryResults[name] = results
      // Only report problems when nothing was found, e.g. one of several
      // discoveries finding no devices is expected
      if (results.length === 0) {
        this.discoveryErrors[name] = errors[0] || 'nothing found'
      }
      this.discoveryLoading[name] = false
    },
    hasOptions(variable) {
      return (
        (variable.options && variable.options.length > 0) ||
        !!variable.discovery ||
        !!variable.bridge
      )
    },
    getDescription(variable) {
      return variable.description || ''
    },
    getHint(name, variable) {
      const description = this.getDescription(variable)
      let discovery = ''
      if (this.discoveryLoading[name]) {
        discovery = 'Discovering...'
      } else if (this.discoveryErrors[name]) {
        discovery = `Discovery: ${this.discoveryErrors[name]}`
      }
      return [description, discovery].filter(Boolean).join(' - ')
    },
    getOptionItems(name, variable) {
      const items = (variable.options || []).map((opt) => ({
        text: opt.text || opt.value,
        value: opt.value,
      }))
      // Bridges and discovered values follow the VARIABLE_STATEs, skipping duplicates
      const extra = variable.bridge ? this.bridges : []
      for (const result of extra.concat(this.discoveryResults[name] || [])) {
        if (!items.some((item) => item.value === result.value)) {
          items.push({ text: result.text || result.value, value: result.value })
        }
      }
      return items
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
.plugin-text :deep(:first-child) {
  margin-top: 0;
}
.plugin-text :deep(:last-child) {
  margin-bottom: 0;
}
.plugin-text :deep(h1),
.plugin-text :deep(h2),
.plugin-text :deep(h3),
.plugin-text :deep(p),
.plugin-text :deep(ul),
.plugin-text :deep(ol),
.plugin-text :deep(pre),
.plugin-text :deep(table) {
  margin-bottom: 8px;
}
.plugin-text :deep(h1) {
  font-size: 1.5rem;
  font-weight: 500;
}
.plugin-text :deep(h2) {
  font-size: 1.25rem;
  font-weight: 500;
}
.plugin-text :deep(h3) {
  font-size: 1.1rem;
  font-weight: 500;
}
.plugin-text :deep(ul),
.plugin-text :deep(ol) {
  padding-left: 24px;
}
.plugin-text :deep(code) {
  padding: 0 4px;
  border-radius: 4px;
  background-color: rgba(var(--v-theme-on-surface), 0.08);
}
.plugin-text :deep(pre code) {
  display: block;
  padding: 8px;
}
.plugin-text :deep(a) {
  color: rgb(var(--v-theme-primary));
}
.plugin-text :deep(th),
.plugin-text :deep(td) {
  padding: 2px 8px;
  border: 1px solid rgba(var(--v-theme-on-surface), 0.2);
}
.v-textarea :deep(textarea) {
  padding: 5px;
}
</style>
