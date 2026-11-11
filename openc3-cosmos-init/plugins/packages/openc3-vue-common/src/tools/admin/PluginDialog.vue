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
    scrollable
    width="80vw"
    @keydown.esc.stop="handleEsc"
  >
    <!-- The title, tabs and actions stay in place while the tab content scrolls -->
    <v-card class="plugin-dialog">
      <v-card-title>{{ pluginName }}</v-card-title>
      <div class="px-6 flex-shrink-0">
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
          <v-tab :key="2" data-test="plugin-preview-tab"> Preview </v-tab>
        </v-tabs>
      </div>
      <v-card-text ref="body" class="plugin-dialog-body pt-0">
        <v-window v-model="tab">
          <v-window-item :value="0" eager="true" class="tab">
            <!-- Markdown from PLUGIN_TEXT_START / PLUGIN_TEXT_END in plugin.txt, collapsible -->
            <template v-if="pluginTextHtml">
              <div
                v-if="pluginTextPanel"
                class="plugin-text-panel mb-2"
                data-test="plugin-text-panel"
              >
                <v-btn
                  icon="mdi-chevron-up"
                  size="small"
                  variant="text"
                  class="plugin-text-hide"
                  title="Hide the plugin description"
                  data-test="plugin-text-hide"
                  @click="pluginTextPanel = null"
                />
                <!-- eslint-disable vue/no-v-html -->
                <div
                  class="plugin-text pa-3 pr-12"
                  data-test="plugin-text"
                  v-html="pluginTextHtml"
                />
                <!-- eslint-enable vue/no-v-html -->
              </div>
              <v-btn
                v-else
                prepend-icon="mdi-chevron-down"
                variant="text"
                size="small"
                class="mb-2"
                data-test="plugin-text-show"
                @click="pluginTextPanel = 'text'"
              >
                Show plugin description
              </v-btn>
            </template>
            <div
              v-if="Object.keys(localVariables).length === 0"
              class="text-body-1 text-medium-emphasis pa-3"
            >
              No variables defined for this plugin.
            </div>
            <v-row v-else no-gutters>
              <v-col cols="12" :lg="sidePanel ? 8 : 12">
                <!-- Markdown from VARIABLE_TEXT_START / VARIABLE_TEXT_END of the selected states,
                     beside the variables on wide screens -->
                <template v-if="!sidePanel">
                  <!-- eslint-disable vue/no-v-html -->
                  <div
                    v-for="(html, index) in variableTextHtml"
                    :key="index"
                    class="plugin-text pa-3"
                    data-test="variable-text-markdown"
                    v-html="html"
                  />
                  <!-- eslint-enable vue/no-v-html -->
                </template>
                <template
                  v-for="section in variableSections"
                  :key="section.key"
                >
                  <!-- VARIABLE_ADVANCED variables are collapsed by default -->
                  <v-btn
                    v-if="section.advanced"
                    :prepend-icon="
                      showAdvanced ? 'mdi-chevron-down' : 'mdi-chevron-right'
                    "
                    variant="text"
                    class="mt-3"
                    data-test="variable-advanced"
                    @click="showAdvanced = !showAdvanced"
                  >
                    Advanced ({{ section.variables.length }})
                  </v-btn>
                  <!-- VARIABLE_GROUP title -->
                  <div
                    v-else-if="section.title"
                    class="variable-group text-subtitle-1 font-weight-medium mt-4 px-1"
                    data-test="variable-group"
                  >
                    {{ section.title }}
                  </div>
                  <v-row v-if="!section.advanced || showAdvanced" class="pt-2">
                    <v-col
                      v-for="[name, variable] in section.variables"
                      :key="name"
                      v-bind="fieldColumns(variable)"
                      :title="name"
                    >
                      <!-- Switch for VARIABLE_TYPE BOOLEAN, indeterminate while blank -->
                      <v-switch
                        v-if="variable.type === 'BOOLEAN'"
                        :model-value="variable.value === 'true'"
                        :indeterminate="
                          !['true', 'false'].includes(variable.value)
                        "
                        :label="fieldLabel(name, variable)"
                        :hint="getHint(name, variable)"
                        :error-messages="variableErrors[name]"
                        persistent-hint
                        color="primary"
                        density="comfortable"
                        data-test="variable-switch"
                        @update:model-value="
                          chooseVariableValue(name, $event ? 'true' : 'false')
                        "
                      >
                        <template
                          v-if="variable.value && !requiredVariables.has(name)"
                          #append
                        >
                          <v-btn
                            icon="mdi-close"
                            size="x-small"
                            variant="text"
                            title="Clear to use the default"
                            @click="chooseVariableValue(name, '')"
                          />
                        </template>
                      </v-switch>

                      <!-- File picker for VARIABLE_FILE, which uploads the
                           file as soon as it's chosen -->
                      <v-file-input
                        v-else-if="variable.type === 'FILE'"
                        :model-value="fileSelection(name, variable)"
                        :show-size="!!chosenFiles[name]"
                        :label="fieldLabel(name, variable)"
                        :hint="getHint(name, variable)"
                        :error-messages="
                          uploadErrors[name] || variableErrors[name]
                        "
                        :loading="uploading[name] || false"
                        persistent-hint
                        prepend-icon=""
                        prepend-inner-icon="mdi-paperclip"
                        density="comfortable"
                        variant="outlined"
                        data-test="variable-file"
                        @update:model-value="uploadFile(name, $event)"
                      />

                      <!-- Chips for VARIABLE_MULTIPLE, which selects any of its states -->
                      <v-autocomplete
                        v-else-if="variable.multiple"
                        :model-value="variable.value"
                        :items="getOptionItems(name, variable)"
                        item-title="text"
                        item-value="value"
                        :label="fieldLabel(name, variable)"
                        :hint="getHint(name, variable)"
                        :error-messages="variableErrors[name]"
                        multiple
                        chips
                        closable-chips
                        persistent-hint
                        density="comfortable"
                        variant="outlined"
                        data-test="variable-multiple"
                        @update:model-value="chooseVariableValue(name, $event)"
                      >
                        <template #item="{ item, props }">
                          <v-list-item
                            v-bind="props"
                            :subtitle="item.raw.description"
                          >
                            <template #prepend="{ isSelected }">
                              <v-checkbox-btn
                                :model-value="isSelected"
                                density="compact"
                                tabindex="-1"
                              />
                              <v-icon
                                v-if="item.raw.icon"
                                :icon="item.raw.icon"
                              />
                            </template>
                          </v-list-item>
                        </template>
                      </v-autocomplete>

                      <!-- Searchable combobox for variables with states, discovery, bridges or secrets -->
                      <v-combobox
                        v-else-if="hasOptions(variable)"
                        :ref="(el) => (comboboxRefs[name] = el)"
                        :model-value="
                          name in comboboxTyped
                            ? comboboxTyped[name]
                            : variable.value
                        "
                        :items="rankedOptionItems(name, variable)"
                        item-title="text"
                        item-value="value"
                        :return-object="false"
                        :custom-filter="tokenizedFilter"
                        :filter-keys="['title', 'raw.description']"
                        :auto-select-first="
                          isController(variable) ||
                          /\s/.test(searches[name] || '')
                        "
                        :label="fieldLabel(name, variable)"
                        :hint="getHint(name, variable)"
                        :error-messages="variableErrors[name]"
                        :loading="discoveryLoading[name] || false"
                        persistent-hint
                        density="comfortable"
                        variant="outlined"
                        data-test="variable-combobox"
                        @update:model-value="
                          comboboxModelChanged(name, variable, $event)
                        "
                        @update:search="searches[name] = $event"
                        @focus="comboboxFocused(name, $event)"
                        @blur="comboboxBlurred(name, variable, $event)"
                        @update:menu="
                          comboboxMenuChanged(name, variable, $event)
                        "
                        @keydown.enter="commitTyped(name, variable)"
                      >
                        <template
                          v-if="
                            variable.discovery || variable.type === 'SECRET'
                          "
                          #append-inner
                        >
                          <v-btn
                            v-if="variable.discovery"
                            icon="mdi-refresh"
                            size="x-small"
                            variant="text"
                            title="Discover again"
                            :disabled="discoveryLoading[name] || false"
                            data-test="variable-discover"
                            @click.stop="runDiscovery(name)"
                          />
                          <v-btn
                            v-if="variable.type === 'SECRET'"
                            icon="mdi-plus"
                            size="x-small"
                            variant="text"
                            title="Create a secret"
                            data-test="variable-secret-create"
                            @click.stop="openSecretDialog(name, variable)"
                          />
                        </template>
                        <template #item="{ item, props }">
                          <v-list-item
                            v-bind="props"
                            :subtitle="item.raw.description"
                            :prepend-icon="item.raw.icon"
                            @click="pickItem(name, item.raw)"
                          >
                            <template #title>
                              <span
                                v-for="(part, index) in highlightParts(
                                  item.raw.text,
                                  searches[name],
                                )"
                                :key="index"
                                :class="{ 'search-match': part.match }"
                                >{{ part.text }}</span
                              >
                            </template>
                          </v-list-item>
                        </template>
                      </v-combobox>

                      <!-- Full width monospace field for VARIABLE_TYPE JSON. Plugin
                           variable values are a single line. -->
                      <v-text-field
                        v-else-if="variable.type === 'JSON'"
                        v-model="variable.value"
                        :label="fieldLabel(name, variable)"
                        :hint="getHint(name, variable)"
                        :error-messages="variableErrors[name]"
                        persistent-hint
                        clearable
                        autocomplete="off"
                        spellcheck="false"
                        class="json-field"
                        density="comfortable"
                        variant="outlined"
                        data-test="variable-json"
                      />

                      <!-- Text field for other variables -->
                      <v-text-field
                        v-else
                        v-model="variable.value"
                        :type="
                          variable.type === 'PASSWORD' && !revealed[name]
                            ? 'password'
                            : 'text'
                        "
                        :inputmode="inputMode(variable)"
                        :append-inner-icon="
                          variable.type === 'PASSWORD'
                            ? revealed[name]
                              ? 'mdi-eye-off'
                              : 'mdi-eye'
                            : undefined
                        "
                        :autocomplete="
                          variable.type === 'PASSWORD' ? 'new-password' : 'off'
                        "
                        :label="fieldLabel(name, variable)"
                        :hint="getHint(name, variable)"
                        :error-messages="variableErrors[name]"
                        persistent-hint
                        clearable
                        density="comfortable"
                        variant="outlined"
                        data-test="variable-text"
                        @click:append-inner="revealed[name] = !revealed[name]"
                      />
                    </v-col>
                  </v-row>
                </template>
              </v-col>
              <!-- Directions for the selected states, kept in view while scrolling -->
              <v-col v-if="sidePanel" cols="12" lg="4" class="pl-4">
                <div class="side-panel" data-test="variable-text-panel">
                  <!-- eslint-disable vue/no-v-html -->
                  <div
                    v-for="(html, index) in variableTextHtml"
                    :key="index"
                    class="plugin-text pa-3"
                    data-test="variable-text-markdown"
                    v-html="html"
                  />
                  <!-- eslint-enable vue/no-v-html -->
                </div>
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
          <v-window-item :value="2" eager="true" class="tab">
            <v-row class="pa-3">
              <v-col>
                The plugin.txt that will be installed with the current
                variables.
              </v-col>
              <v-col cols="auto">
                <v-btn
                  prepend-icon="mdi-refresh"
                  variant="text"
                  :loading="previewLoading"
                  data-test="plugin-preview-refresh"
                  @click="loadPreview"
                >
                  Refresh
                </v-btn>
              </v-col>
            </v-row>
            <v-alert
              v-if="previewError"
              type="error"
              variant="tonal"
              class="mb-3"
              data-test="plugin-preview-error"
            >
              {{ previewError }}
            </v-alert>
            <pre
              v-show="!previewError"
              ref="preview"
              class="editor"
              data-test="plugin-preview"
            ></pre>
          </v-window-item>
        </v-window>
      </v-card-text>
      <div class="px-6 pb-2 flex-shrink-0">
        <v-alert
          v-if="showRequired && errorCount > 0"
          type="error"
          variant="tonal"
          density="compact"
          class="mt-3"
          data-test="variable-errors"
        >
          Fix the {{ errorCount }} highlighted variable{{
            errorCount === 1 ? '' : 's'
          }}
          before installing.
        </v-alert>

        <v-card-actions class="px-2 mt-2">
          <div v-if="existingPluginTxt !== null">
            <v-btn variant="text" @click="nextDiff"> Next Diff </v-btn>
            <v-btn variant="text" @click="previousDiff"> Previous Diff </v-btn>
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
            :disabled="uploadingFiles"
            @click="checkVersionAndSubmit"
          >
            Install
          </v-btn>
        </v-card-actions>
      </div>
    </v-card>
    <!-- Creates a COSMOS secret for a VARIABLE_TYPE SECRET variable -->
    <v-dialog v-model="secretDialog" width="500">
      <v-card>
        <v-card-title>Create Secret</v-card-title>
        <v-card-text>
          <v-text-field
            v-model="secretName"
            label="Secret name"
            density="comfortable"
            variant="outlined"
            data-test="secret-name"
          />
          <v-textarea
            v-model="secretValue"
            label="Secret value"
            :hint="secretHint"
            persistent-hint
            auto-grow
            rows="1"
            density="comfortable"
            variant="outlined"
            data-test="secret-value"
          />
          <v-alert
            v-if="secretError"
            type="error"
            variant="tonal"
            density="compact"
            class="mt-3"
          >
            {{ secretError }}
          </v-alert>
        </v-card-text>
        <v-card-actions>
          <v-spacer />
          <v-btn variant="outlined" @click="secretDialog = false">
            Cancel
          </v-btn>
          <v-btn
            variant="flat"
            :disabled="!secretName.trim() || !secretValue"
            :loading="secretSaving"
            data-test="secret-create"
            @click="createSecret"
          >
            Create
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
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
import { tokenizedFilter, tokenizedSort } from '@openc3/js-common/utils'
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
    // Installed plugin being upgraded or edited. Devices it already claims
    // are still offered by discovery.
    excludePlugin: {
      type: String,
      required: false,
      default: null,
    },
    // Upgrading or editing an installed plugin, so its existing values are
    // kept rather than replaced by discovered ones
    installed: {
      type: Boolean,
      default: false,
    },
    // Values to start with, e.g. for the device hardware discovery found
    presetVariables: {
      type: Object,
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
      // Discovered values hidden because other plugins claim them
      discoveryClaimed: {},
      // Variables the user picked a value for, so discovery leaves them alone
      discoveryChosen: {},
      // Available bridges for the VARIABLE_BRIDGE variable: [{ value, text }]
      bridges: [],
      // Expand the VARIABLE_ADVANCED section
      showAdvanced: false,
      // Report blank required variables, set when Install is pressed
      showRequired: false,
      // PASSWORD variables shown in plain text
      revealed: {},
      // Target names in use, and each TARGET_NAME variable's value when the
      // dialog opened (its own target when the plugin is being changed)
      takenTargetNames: new Set(),
      originalTargetNames: {},
      // VARIABLE_FILE uploads in progress and their errors by variable name
      uploading: {},
      uploadErrors: {},
      // The file chosen for each VARIABLE_FILE since the dialog opened
      chosenFiles: {},
      previewEditor: null,
      previewLoading: false,
      previewError: null,
      // Text typed into each combobox, used to rank and highlight its items
      searches: {},
      // Comboboxes being typed in. Typed text is a search until an item is
      // picked or the combobox loses focus, so it is shown in the combobox
      // but isn't applied as the value (and doesn't select states) on every
      // keystroke.
      comboboxTyping: {},
      comboboxTyped: {},
      comboboxRefs: {},
      // The PLUGIN_TEXT is shown unless the user hid it for this plugin
      pluginTextPanel: this.loadPluginTextPanel(),
      // VARIABLE_TYPE SECRET: the scope's secret names and the create dialog
      secrets: [],
      secretDialog: false,
      secretVariable: null,
      secretName: '',
      secretValue: '',
      secretSaving: false,
      secretError: null,
    }
  },
  computed: {
    uploadingFiles() {
      return Object.values(this.uploading).some(Boolean)
    },
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
    // Markdown of the selected VARIABLE_STATE of each shown variable
    variableTextHtml() {
      const html = []
      for (const [, variable] of this.visibleVariables) {
        for (const option of this.selectedOptions(variable)) {
          if (option.markdown) {
            html.push(DOMPurify.sanitize(marked.parse(option.markdown)))
          }
        }
      }
      return html
    },
    // VARIABLE_STATE_SHOW lookups: the variables whose states list each
    // variable, and each such variable's state values and what they show.
    // Only depends on the options so typing values doesn't rebuild it, which
    // matters for plugins with hundreds of variables and states.
    showIndex() {
      const controllers = {}
      const states = {}
      for (const [controlName, control] of Object.entries(
        this.localVariables,
      )) {
        if (!control.options) continue
        const shows = new Map()
        for (const opt of control.options) {
          shows.set(opt.value, new Set(opt.show || []))
          for (const name of opt.show || []) {
            controllers[name] ||= []
            controllers[name].push(controlName)
          }
        }
        states[controlName] = shows
      }
      return { controllers, states }
    },
    // Variables not hidden by the currently selected VARIABLE_STATE of another
    // variable (see VARIABLE_STATE_SHOW)
    visibleVariables() {
      return Object.entries(this.localVariables).filter(([name]) =>
        this.isVariableVisible(name),
      )
    },
    // Variables required by VARIABLE_REQUIRED or the VARIABLE_STATE_REQUIRED
    // of a selected state
    requiredVariables() {
      const required = new Set()
      for (const [name, variable] of Object.entries(this.localVariables)) {
        if (variable.required) required.add(name)
        if (!variable.hidden && !this.isVariableVisible(name)) continue
        for (const selected of this.selectedOptions(variable)) {
          for (const target of selected.required || []) required.add(target)
        }
      }
      return required
    },
    // Error messages of the shown variables by name. Blank required variables
    // are only reported once Install is pressed.
    variableErrors() {
      const errors = {}
      for (const [name, variable] of this.visibleVariables) {
        const error = this.validateVariable(name, variable)
        if (error && (error !== 'Required' || this.showRequired)) {
          errors[name] = error
        }
      }
      return errors
    },
    errorCount() {
      return Object.keys(this.variableErrors).length
    },
    // Visible variables split into the normal ones and the collapsed
    // VARIABLE_ADVANCED ones, leaving out a section with no variables
    variableSections() {
      // Ungrouped variables, then each VARIABLE_GROUP in the order it is first
      // used, then the collapsed VARIABLE_ADVANCED variables
      const ungrouped = { key: '', title: null, variables: [] }
      const groups = new Map()
      const advanced = { key: 'advanced', advanced: true, variables: [] }
      for (const entry of this.visibleVariables) {
        const variable = entry[1]
        if (variable.advanced) {
          advanced.variables.push(entry)
        } else if (variable.group) {
          if (!groups.has(variable.group)) {
            groups.set(variable.group, {
              key: `group-${variable.group}`,
              title: variable.group,
              variables: [],
            })
          }
          groups.get(variable.group).variables.push(entry)
        } else {
          ungrouped.variables.push(entry)
        }
      }
      return [ungrouped, ...groups.values(), advanced].filter(
        (section) => section.variables.length > 0,
      )
    },
    // Directions for the selected states go beside the variables when there
    // is room
    sidePanel() {
      return this.variableTextHtml.length > 0 && this.$vuetify.display.lgAndUp
    },
    secretHint() {
      const variable = this.localVariables[this.secretVariable]
      const description = variable?.description
      return description
        ? `Stored as a COSMOS secret. ${description}`
        : 'Stored as a COSMOS secret'
    },
  },
  watch: {
    tab(value) {
      if (value === 2) this.loadPreview()
    },
    pluginTextPanel(value) {
      try {
        localStorage[this.pluginTextStorageKey()] = value ? 'open' : 'closed'
      } catch {
        // Storage can be unavailable, e.g. in private browsing
      }
    },
    // Variables shown by a VARIABLE_STATE_SHOW get a discovered value then,
    // so hidden variables don't claim devices they won't use
    visibleVariables(visible, previous) {
      const before = new Set(previous.map(([name]) => name))
      for (const [name] of visible) {
        if (!before.has(name)) this.autoSelectDiscovered(name)
      }
    },
    value: {
      immediate: true,
      handler: function () {
        // Deep copy and normalize variables to new format
        // Handles both old format (string values) and new format (hash with value/description/options)
        const rawVariables = JSON.parse(JSON.stringify(this.variables))
        this.localVariables = {}
        this.chosenFiles = {}
        for (const [name, variable] of Object.entries(rawVariables)) {
          if (typeof variable === 'string') {
            // Old format: convert to new format
            this.localVariables[name] = { value: variable }
          } else {
            // New format: use as-is
            this.localVariables[name] = variable
          }
          if (this.localVariables[name].multiple) {
            this.localVariables[name].value = this.multipleValues(
              this.localVariables[name],
              this.localVariables[name].value,
            )
          }
        }
        this.originalTargetNames = {}
        for (const [name, variable] of Object.entries(this.localVariables)) {
          if (variable.type === 'TARGET_NAME') {
            this.originalTargetNames[name] = String(variable.value ?? '')
              .trim()
              .toUpperCase()
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
    if (
      Object.values(this.localVariables).some(
        (variable) => variable.type === 'TARGET_NAME',
      )
    ) {
      Api.get('/openc3-api/targets')
        .then(({ data }) => {
          this.takenTargetNames = new Set(
            (data || []).map((target) => String(target).toUpperCase()),
          )
        })
        .catch(console.error)
    }
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
    this.applyPresetVariables()
    this.runAllDiscovery()
    if (
      Object.values(this.localVariables).some(
        (variable) => variable.type === 'SECRET',
      )
    ) {
      this.loadSecrets()
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
    if (this.previewEditor) {
      this.previewEditor.destroy()
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
        'VARIABLE_LABEL',
        'VARIABLE_TYPE',
        'VARIABLE_GROUP',
        'VARIABLE_REQUIRED',
        'VARIABLE_PATTERN',
        'VARIABLE_HIDDEN',
        'VARIABLE_ADVANCED',
        'VARIABLE_MULTIPLE',
        'VARIABLE_STATE',
        'VARIABLE_STATE_SHOW',
        'VARIABLE_STATE_SET',
        'VARIABLE_STATE_REQUIRED',
        'VARIABLE_STATE_DESCRIPTION',
        'VARIABLE_STATE_ICON',
        'VARIABLE_DISCOVERY',
        'VARIABLE_DISCOVERY_SET',
        'VARIABLE_BRIDGE',
        'VARIABLE_FILE',
        'PRE_INSTALL_SCRIPT',
        'POST_INSTALL_SCRIPT',
        'PLUGIN_TEXT_START',
        'PLUGIN_TEXT_END',
        'VARIABLE_TEXT_START',
        'VARIABLE_TEXT_END',
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
    // Variables with errors stop the install and are shown on the Variables tab
    validate() {
      this.showRequired = true
      const names = Object.keys(this.variableErrors)
      if (names.length === 0) return true
      this.tab = 0
      if (names.some((name) => this.localVariables[name].advanced)) {
        this.showAdvanced = true
      }
      // Bring the first problem into view in the scrolling content
      this.$nextTick(() => {
        this.$refs.body?.$el
          .querySelector('.v-input--error')
          ?.scrollIntoView({ block: 'center', behavior: 'smooth' })
      })
      return false
    },
    validateVariable(name, variable) {
      if (variable.multiple) {
        const empty = !this.multipleValues(variable, variable.value).length
        return empty && this.requiredVariables.has(name) ? 'Required' : null
      }
      const value = String(variable.value ?? '').trim()
      if (!value) {
        return this.requiredVariables.has(name) ? 'Required' : null
      }
      switch (variable.type) {
        case 'BOOLEAN':
          if (!['true', 'false'].includes(value)) return 'Must be true or false'
          break
        case 'INTEGER':
          if (!/^[-+]?\d+$/.test(value)) return 'Must be a whole number'
          break
        case 'NUMBER':
          if (!Number.isFinite(Number(value))) return 'Must be a number'
          break
        case 'TARGET_NAME': {
          if (!/^[A-Za-z0-9]+(?:_[A-Za-z0-9]+)*$/.test(value)) {
            return 'Use letters, numbers and single underscores, not starting or ending with an underscore'
          }
          const target = value.toUpperCase()
          const sameName = Object.entries(this.localVariables).some(
            ([other, otherVariable]) =>
              other !== name &&
              otherVariable.type === 'TARGET_NAME' &&
              String(otherVariable.value ?? '')
                .trim()
                .toUpperCase() === target,
          )
          if (sameName)
            return `Another target of this plugin is named ${target}`
          // The plugin's own targets when it's being changed or upgraded
          if (
            this.takenTargetNames.has(target) &&
            target !== this.originalTargetNames[name]
          ) {
            return `Target ${target} already exists`
          }
          break
        }
        case 'JSON':
          try {
            JSON.parse(value)
          } catch (error) {
            return `Invalid JSON: ${error.message}`
          }
          break
      }
      if (variable.pattern) {
        let regex = null
        try {
          regex = new RegExp(`^(?:${variable.pattern})$`)
        } catch {
          // A Ruby only regular expression can't be checked here
        }
        if (regex && !regex.test(value)) {
          return variable.pattern_message || `Must match ${variable.pattern}`
        }
      }
      return null
    },
    // The name of the file uploaded for a VARIABLE_FILE variable, whose value
    // is "<upload id>/<file name>"
    uploadedFilename(variable) {
      const value = variable.value || ''
      return value.includes('/') ? value.slice(value.indexOf('/') + 1) : ''
    },
    // What a VARIABLE_FILE's file input shows: the file chosen in this dialog,
    // or the file uploaded when the plugin was last installed. A file input
    // can't show a placeholder, so the earlier file is shown by name like a
    // chosen one (without a size, which isn't known here).
    fileSelection(name, variable) {
      if (this.chosenFiles[name]) return [this.chosenFiles[name]]
      const filename = this.uploadedFilename(variable)
      return filename ? [{ name: filename }] : []
    },
    async uploadFile(name, files) {
      const file = Array.isArray(files) ? files[0] : files
      this.uploadErrors[name] = null
      if (!file) {
        // Cleared: install without a file
        delete this.chosenFiles[name]
        this.localVariables[name].value = ''
        return
      }
      this.chosenFiles[name] = file
      const formData = new FormData()
      formData.append('file', file, file.name)
      this.uploading[name] = true
      try {
        const { data } = await Api.post('/openc3-api/plugins/files', {
          data: formData,
          headers: { 'Content-Type': 'multipart/form-data' },
        })
        this.localVariables[name].value = data.value
      } catch (error) {
        this.localVariables[name].value = ''
        this.uploadErrors[name] =
          `Upload failed: ${error.response?.data?.message || error.message}`
      } finally {
        this.uploading[name] = false
      }
    },
    fieldLabel(name, variable) {
      const label = variable.label || name
      return this.requiredVariables.has(name) ? `${label} *` : label
    },
    inputMode(variable) {
      if (variable.type === 'INTEGER') return 'numeric'
      if (variable.type === 'NUMBER') return 'decimal'
      return undefined
    },
    // The plugin.txt lines that would be installed, including edits
    currentPluginTxtLines() {
      if (this.existingPluginTxt === null) {
        return this.editor.getValue().split('\n')
      }
      return this.differ.getEditors().left.getValue().split('\n')
    },
    async loadPreview() {
      this.previewLoading = true
      try {
        const { data } = await Api.post('/openc3-api/plugins/preview', {
          data: {
            plugin_hash: JSON.stringify({
              variables: toRaw(this.localVariables),
              plugin_txt_lines: this.currentPluginTxtLines(),
            }),
          },
        })
        this.previewError = data.error || null
        if (!this.previewEditor) {
          this.previewEditor = ace.edit(this.$refs.preview)
          this.previewEditor.setTheme('ace/theme/twilight')
          this.previewEditor.session.setMode(new (this.buildPluginMode())())
          this.previewEditor.session.setTabSize(2)
          this.previewEditor.setReadOnly(true)
          this.previewEditor.setHighlightActiveLine(false)
          this.previewEditor.$blockScrolling = Infinity
        }
        this.previewEditor.setValue(data.plugin_txt || '')
        this.previewEditor.clearSelection()
      } catch (error) {
        this.previewError = `Preview failed: ${error.message}`
      } finally {
        this.previewLoading = false
      }
    },
    checkVersionAndSubmit: function () {
      if (!this.validate()) return
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
        this.emitSubmit(this.currentPluginTxtLines())
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
    // Set the presetVariables the plugin defines. Variables whose states set
    // others go first, so a state's defaults don't replace a preset value.
    applyPresetVariables() {
      const presets = Object.entries(this.presetVariables || {}).filter(
        ([name]) => name in this.localVariables,
      )
      const controls = (name) => this.isController(this.localVariables[name])
      for (const [name, value] of [
        ...presets.filter(([name]) => controls(name)),
        ...presets.filter(([name]) => !controls(name)),
      ]) {
        this.chooseVariableValue(name, String(value))
      }
    },
    // A value chosen in the dialog, which discovery won't replace
    chooseVariableValue(name, value) {
      this.discoveryChosen[name] = true
      this.setVariableValue(name, value)
    },
    tokenizedFilter,
    // A combobox's items, closest matches to what was typed first
    rankedOptionItems(name, variable) {
      return tokenizedSort(
        this.getOptionItems(name, variable),
        this.searches[name],
        'text',
      )
    },
    // An item's text split into the parts that match the search, to highlight
    highlightParts(text, search) {
      const ranges = search ? tokenizedFilter(text, search) : false
      if (!Array.isArray(ranges)) return [{ text, match: false }]
      const parts = []
      let index = 0
      for (const [start, end] of ranges) {
        if (start > index) {
          parts.push({ text: text.slice(index, start), match: false })
        }
        parts.push({ text: text.slice(start, end), match: true })
        index = end
      }
      if (index < text.length) {
        parts.push({ text: text.slice(index), match: false })
      }
      return parts
    },
    // The item a typed value names, by value or by its text ignoring case
    matchingItem(name, variable, value) {
      const items = this.getOptionItems(name, variable)
      const text = String(value).trim().toLowerCase()
      return (
        items.find((item) => item.value === value) ||
        items.find(
          (item) =>
            String(item.value).toLowerCase() === text ||
            String(item.text).toLowerCase() === text,
        )
      )
    },
    // Whether choosing a state of this variable does something (shows or sets
    // variables, has directions), so it is a choice rather than a suggestion
    isController(variable) {
      return (variable.options || []).some(
        (option) =>
          option.show || option.set || option.required || option.markdown,
      )
    },
    comboboxModelChanged(name, variable, value) {
      const text = value ?? ''
      if (this.comboboxTyping[name]) {
        // Typing, or Vuetify selecting the first match on Enter or Tab, which
        // is applied by commitTyped() or when focus leaves
        if (text === variable.value) {
          delete this.comboboxTyped[name]
        } else {
          this.comboboxTyped[name] = text
        }
      } else {
        this.chooseVariableValue(name, text)
      }
    },
    pickItem(name, item) {
      delete this.comboboxTyped[name]
      this.chooseVariableValue(name, item.value)
    },
    comboboxFocused(name, event) {
      this.comboboxTyping[name] = true
      // Show the whole list in its usual order until something is typed
      this.searches[name] = ''
      // Select the text so typing replaces it with a search, after the
      // combobox has handled the focus itself (as TargetPacketItemChooser does)
      const input = event?.target
      this.$nextTick(() => input?.select?.())
    },
    // Focus can leave through the dropdown without the input blurring, e.g.
    // arrowing into the list then clicking elsewhere
    comboboxMenuChanged(name, variable, open) {
      if (open || !this.comboboxTyping[name]) return
      this.$nextTick(() => {
        const element = this.comboboxRefs[name]?.$el
        if (element && !element.contains(document.activeElement)) {
          this.comboboxBlurred(name, variable)
        }
      })
    },
    comboboxBlurred(name, variable, event) {
      // Focus moving into the dropdown, e.g. to click an item, isn't leaving
      if (event?.relatedTarget?.closest?.('.v-overlay__content')) return
      this.comboboxTyping[name] = false
      this.commitTyped(name, variable, true)
    },
    // Apply what was typed into a combobox. Text naming an item selects it.
    // Otherwise it is a custom value, unless it was a search for items that
    // wasn't picked from: text with spaces (as in the packet chooser), or any
    // search of a variable whose states choose what is shown.
    commitTyped(name, variable, leaving = false) {
      if (!(name in this.comboboxTyped)) return
      const typed = this.comboboxTyped[name]
      const item = this.matchingItem(name, variable, typed)
      if (item) {
        delete this.comboboxTyped[name]
        this.chooseVariableValue(name, item.value)
        return
      }
      if (!leaving) return // Enter without a match keeps typing
      delete this.comboboxTyped[name]
      const searched = this.getOptionItems(name, variable).some((option) =>
        tokenizedFilter(option.text, typed),
      )
      // Throwing the search away shows the variable's value again
      if (!searched || !(/\s/.test(typed) || this.isController(variable))) {
        this.chooseVariableValue(name, typed)
      }
    },
    // Columns for a variable's field, narrower beside the directions panel
    fieldColumns(variable) {
      if (variable.type === 'JSON') return { cols: 12 }
      // Room for the chips of several states
      if (variable.multiple) return { cols: 12, md: 6 }
      return { cols: 12, sm: 6, md: this.sidePanel ? 4 : 3 }
    },
    pluginTextStorageKey() {
      // Remembered across versions of the plugin
      const plugin = this.pluginName.replace(/-\d[\w.]*(\.gem)?$/, '')
      return `PluginDialog__pluginText__${plugin}`
    },
    loadPluginTextPanel() {
      try {
        if (localStorage[this.pluginTextStorageKey()] === 'closed') {
          return null
        }
      } catch {
        // Storage can be unavailable, e.g. in private browsing
      }
      return 'text'
    },
    async loadSecrets() {
      try {
        const { data } = await Api.get('/openc3-api/secrets')
        this.secrets = data || []
      } catch (error) {
        // The dropdown just has no secrets to offer
        this.secrets = []
      }
    },
    openSecretDialog(name, variable) {
      this.secretVariable = name
      this.secretName = variable.value || ''
      this.secretValue = ''
      this.secretError = null
      this.secretDialog = true
    },
    async createSecret() {
      this.secretSaving = true
      this.secretError = null
      const secretName = this.secretName.trim()
      try {
        await Api.post(
          `/openc3-api/secrets/${encodeURIComponent(secretName)}`,
          { data: { value: this.secretValue } },
        )
        await this.loadSecrets()
        this.chooseVariableValue(this.secretVariable, secretName)
        this.secretDialog = false
      } catch (error) {
        this.secretError =
          error.response?.data?.message || error.message || String(error)
      } finally {
        this.secretSaving = false
        this.secretValue = ''
      }
    },
    // Set a variable and, if the new value selects a state, apply that
    // state's VARIABLE_STATE_SET values (cascading into other states)
    setVariableValue(name, value, visiting = new Set()) {
      const variable = this.localVariables[name]
      if (variable.multiple) {
        // Apply the VARIABLE_STATE_SETs of the states just selected
        const values = this.multipleValues(variable, value)
        const previous = this.multipleValues(variable, variable.value)
        if (visiting.has(name)) return
        if (values.join('\n') === previous.join('\n')) return
        visiting.add(name)
        variable.value = values
        for (const option of this.selectedOptions(variable)) {
          if (previous.includes(option.value)) continue
          for (const [target, setValue] of Object.entries(option.set || {})) {
            this.setVariableValue(target, setValue, visiting)
          }
        }
        return
      }
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
      // and on the variables their parameters reference as ${name}
      for (const [other, otherVariable] of Object.entries(
        this.localVariables,
      )) {
        if (
          otherVariable.discovery?.some((entry) =>
            entry.discovery.some((param) => param.includes(`\${${name}}`)),
          )
        ) {
          this.scheduleDiscovery(other)
        }
      }
    },
    // Run a variable's discovery once after the current changes, which can
    // set several of the variables it references
    scheduleDiscovery(name) {
      this.pendingDiscovery ||= new Set()
      if (this.pendingDiscovery.size === 0) {
        queueMicrotask(() => {
          const names = [...this.pendingDiscovery]
          this.pendingDiscovery.clear()
          names.forEach((pending) => this.runDiscovery(pending))
        })
      }
      this.pendingDiscovery.add(name)
    },
    // The discovery class and parameters to request, with ${name} replaced by
    // the value of variable name (which may hold several space separated
    // parameters). Null when every referenced variable is blank, e.g. a
    // discovery that doesn't apply to the selected state.
    discoveryRequest(entry) {
      let references = 0
      let filled = 0
      const params = entry.discovery.slice(1).flatMap((param) => {
        if (!/\$\{\w+\}/.test(param)) return [param]
        const replaced = param.replace(/\$\{(\w+)\}/g, (match, ref) => {
          references++
          const value = String(this.localVariables[ref]?.value ?? '').trim()
          if (value) filled++
          return value
        })
        return replaced.split(/\s+/).filter(Boolean)
      })
      if (references > 0 && filled === 0) return null
      return [entry.discovery[0], ...params]
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
            : `${bridge.name} (not paired with openc3-cosmos-app)`,
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
      if (this.localVariables[name]?.hidden) return false // VARIABLE_HIDDEN
      visiting.add(name)
      try {
        const { controllers, states } = this.showIndex
        // Variables listed by any VARIABLE_STATE_SHOW of a variable are only
        // visible when its selected state lists them
        for (const controlName of new Set(controllers[name] || [])) {
          // A hidden variable can't be selected so nothing it shows is visible,
          // unless it is VARIABLE_HIDDEN and so only set by other states
          if (
            !this.localVariables[controlName].hidden &&
            !this.isVariableVisible(controlName, visiting)
          )
            return false
          const control = this.localVariables[controlName]
          if (control.multiple) {
            // Shown while any selected state lists it
            const selected = this.selectedOptions(control)
            if (!selected.some((option) => option.show?.includes(name)))
              return false
            continue
          }
          const shows = states[controlName].get(control.value)
          // Custom values that don't match a state don't affect visibility
          if (!shows) continue
          if (!shows.has(name)) return false
        }
        return true
      } finally {
        visiting.delete(name)
      }
    },
    // Ask the host (through openc3-cosmos-app and the DEFAULT bridge) for the
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
      const requests = variable.discovery.map((entry) =>
        this.discoveryRequest(entry),
      )
      const outcomes = await Promise.allSettled(
        requests.map((discovery) =>
          // Discoveries that don't apply are skipped (and not an error)
          discovery === null
            ? Promise.resolve({ data: { results: [], claimed: [] } })
            : Api.post('/openc3-api/discovery', {
                data: {
                  bridge,
                  discovery,
                  exclude_plugin: this.excludePlugin,
                },
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
      const claimed = []
      const errors = []
      outcomes.forEach((outcome, index) => {
        if (outcome.status === 'fulfilled') {
          for (const result of outcome.value.data.results || []) {
            results.push({ ...result, discoveryIndex: index })
          }
          claimed.push(...(outcome.value.data.claimed || []))
        } else {
          errors.push(
            outcome.reason.response?.data?.message || outcome.reason.message,
          )
        }
      })
      this.discoveryResults[name] = results
      this.discoveryClaimed[name] = claimed
      this.autoSelectDiscovered(name)
      // Only report problems when nothing was found, e.g. one of several
      // discoveries finding no devices is expected
      const applicable = requests.some((discovery) => discovery !== null)
      if (applicable && results.length === 0 && claimed.length === 0) {
        this.discoveryErrors[name] = errors[0] || 'nothing found'
      }
      this.discoveryLoading[name] = false
    },
    // Select the first available discovered value for a new install unless
    // the user already picked a value or the current one is still available
    autoSelectDiscovered(name) {
      const variable = this.localVariables[name]
      if (this.installed || this.discoveryChosen[name] || !variable?.discovery)
        return
      if (!this.isVariableVisible(name)) return
      const items = this.getOptionItems(name, variable)
      const available = (this.discoveryResults[name] || []).filter((result) =>
        items.some((item) => item.value === result.value),
      )
      if (available.some((result) => result.value === variable.value)) return
      if (available.length > 0) {
        this.setVariableValue(name, available[0].value)
      }
    },
    // The values of a VARIABLE_MULTIPLE that are its states, in state order.
    // A value can also be given as a comma separated string, e.g. by a
    // VARIABLE_STATE_SET or VARIABLE_DISCOVERY_SET of another variable.
    multipleValues(variable, value) {
      const values = (
        Array.isArray(value) ? value : String(value ?? '').split(',')
      ).map((item) => String(item).trim())
      return (variable.options || [])
        .map((option) => option.value)
        .filter((stateValue) => values.includes(stateValue))
    },
    // The selected VARIABLE_STATEs of a variable: the one matching its value,
    // or each one a VARIABLE_MULTIPLE has selected
    selectedOptions(variable) {
      const options = variable.options || []
      if (variable.multiple) {
        const values = this.multipleValues(variable, variable.value)
        return options.filter((option) => values.includes(option.value))
      }
      const selected = options.find((option) => option.value === variable.value)
      return selected ? [selected] : []
    },
    hasOptions(variable) {
      return (
        (variable.options && variable.options.length > 0) ||
        !!variable.discovery ||
        !!variable.bridge ||
        variable.type === 'SECRET'
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
      } else if (this.discoveryClaimed[name]?.length) {
        discovery = this.discoveryClaimed[name]
          .map(
            (claim) => `${claim.text || claim.value} in use by ${claim.plugin}`,
          )
          .join(', ')
      }
      let secret = ''
      if (
        variable.type === 'SECRET' &&
        variable.value &&
        !this.secrets.includes(variable.value)
      ) {
        // Not an error: secrets can also be set outside COSMOS, e.g. in Kubernetes
        secret = `No secret named ${variable.value} was found`
      }
      return [description, discovery, secret].filter(Boolean).join(' - ')
    },
    // Values already chosen by this plugin's other variables that discover
    // with the same class, e.g. so two serial port variables can't both use
    // the same port. Mirrors the claims of installed plugins on the server.
    claimedInDialog(name, variable) {
      const classKey = (discovery) =>
        discovery.discovery[0].replace(/\.py$/, '').replaceAll('/', '.')
      const classes = new Set((variable.discovery || []).map(classKey))
      const claimed = new Set()
      for (const [otherName, other] of Object.entries(this.localVariables)) {
        if (otherName === name || !other.discovery) continue
        if (other.discovery.some((entry) => classes.has(classKey(entry)))) {
          claimed.add(other.value)
        }
      }
      return claimed
    },
    getOptionItems(name, variable) {
      const items = (variable.options || []).map((opt) => ({
        text: opt.text || opt.value,
        value: opt.value,
        description: opt.description,
        icon: opt.icon,
      }))
      // Bridges, secrets and discovered values follow the VARIABLE_STATEs,
      // skipping duplicates
      const extra = variable.bridge ? [...this.bridges] : []
      if (variable.type === 'SECRET') {
        extra.push(...this.secrets.map((secret) => ({ value: secret })))
      }
      const claimed = this.claimedInDialog(name, variable)
      for (const result of extra.concat(this.discoveryResults[name] || [])) {
        if (
          !items.some((item) => item.value === result.value) &&
          !claimed.has(result.value)
        ) {
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
.json-field :deep(input) {
  font-family: monospace;
}
.variable-group {
  border-bottom: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
}
.search-match {
  font-weight: bold;
  text-decoration: underline;
}
/* Fit the dialog to the window and scroll the content between the header
   (title and tabs) and footer (errors and buttons). Set here rather than
   relying on the v-dialog scrollable layout reaching the card. */
.plugin-dialog {
  display: flex;
  flex-direction: column;
  max-height: calc(100vh - 48px);
  max-height: calc(100dvh - 48px);
}
.plugin-dialog-body {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
}
.side-panel {
  position: sticky;
  top: 0;
  /* Long directions scroll within the panel so its end stays reachable */
  max-height: 60vh;
  overflow-y: auto;
  border-left: thin solid rgba(var(--v-border-color), var(--v-border-opacity));
}
.plugin-text-panel {
  position: relative;
}
.plugin-text-hide {
  position: absolute;
  top: 4px;
  right: 4px;
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
