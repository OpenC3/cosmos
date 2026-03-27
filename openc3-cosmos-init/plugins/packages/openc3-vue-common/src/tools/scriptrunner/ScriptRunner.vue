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
  <div
    v-if="!inline"
    class="d-flex flex-column overflow-hidden"
    :style="{
      height: containerHeight,
    }"
  >
    <top-bar :menus="menus" :title="title" />
    <v-snackbar
      v-model="showAlert"
      absolute
      :color="alertType"
      :timeout="3000"
      class="apply-top"
      :style="classificationStyles"
    >
      <v-icon> mdi-{{ alertType }} </v-icon>
      {{ alertText }}
      <template #actions="{ attrs }">
        <v-btn
          variant="text"
          text="Close"
          v-bind="attrs"
          @click="showAlert = false"
        />
      </template>
    </v-snackbar>
    <v-snackbar
      v-model="showEditingToast"
      absolute
      class="apply-top"
      :style="classificationStyles"
      :timeout="-1"
      color="orange"
    >
      <v-icon> mdi-pencil-off </v-icon>
      {{ lockedBy }} is editing this script. Editor is in read-only mode
      <template #actions="{ attrs }">
        <v-btn
          variant="text"
          v-bind="attrs"
          color="danger"
          text="Unlock"
          data-test="unlock-button"
          @click="confirmLocalUnlock"
        />
        <v-btn
          variant="text"
          text="Dismiss"
          v-bind="attrs"
          @click="
            () => {
              showEditingToast = false
            }
          "
        />
      </template>
    </v-snackbar>
    <div class="grid">
      <div
        v-for="def in screens"
        :id="screenId(def.id)"
        :key="def.id"
        class="item"
      >
        <div class="item-content">
          <openc3-screen
            :target="def.target"
            :screen="def.screen"
            :definition="def.definition"
            :keywords="screenKeywords"
            :initial-floated="true"
            :initial-top="def.top"
            :initial-left="def.left"
            :initial-z="3"
            :min-z="3"
            :fix-floated="true"
            :count="def.count"
            @close-screen="closeScreen(def.id)"
            @delete-screen="closeScreen(def.id)"
          />
        </div>
      </div>
    </div>
    <v-card class="flex-shrink-0">
      <v-card-text>
        <suite-runner
          v-if="suiteRunner"
          class="suite-runner"
          :suite-map="suiteMap"
          :disable-buttons="disableSuiteButtons"
          :filename="fullFilename"
          @button="suiteRunnerButton"
          @loaded="doResize"
        />
        <script-control-bar
          v-model="filenameSelect"
          :show-disconnect="showDisconnect"
          :script-id="scriptId"
          :filename="filename"
          :new-filename="NEW_FILENAME"
          :file-list="fileList"
          :state="state"
          :start-or-go-button="startOrGoButton"
          :start-or-go-disabled="startOrGoDisabled"
          :env-disabled="envDisabled"
          :pause-or-retry-button="pauseOrRetryButton"
          :pause-or-retry-disabled="pauseOrRetryDisabled"
          :stop-disabled="stopDisabled"
          :overrides-count="overridesCount"
          :environment-modified="environmentModified"
          :execute-user="executeUser"
          :suite-runner="suiteRunner"
          :waiting-time="waitingTime"
          @reload-file="reloadFile"
          @back-to-new-script="backToNewScript"
          @file-name-changed="fileNameChanged"
          @toggle-overrides="showOverrides = !showOverrides"
          @toggle-environment="scriptEnvironment.show = !scriptEnvironment.show"
          @start="start"
          @go="go"
          @pause-or-retry="pauseOrRetry"
          @stop="stop"
        />
      </v-card-text>
    </v-card>
    <splitpanes
      horizontal
      class="flex-grow-1 overflow-hidden"
      @resize="({ prevPane }) => (editorBoxSize = prevPane.size)"
    >
      <pane class="editorbox" :size="editorBoxSize">
        <v-snackbar
          v-model="showSave"
          absolute
          location="right"
          :timeout="-1"
          class="saving apply-top"
          :style="classificationStyles"
        >
          Saving...
        </v-snackbar>
        <script-ace-editor
          ref="editor"
          v-model="editorContent"
          :filename-select="filenameSelect"
          :hide-cursor="readOnlyUser || inline"
          :language="editorLanguage"
          :read-only="readOnlyUser || inline"
          :script-id="scriptId"
          show-context-menu
          @change="onChange"
          @command-editor="handleCommandEditor"
          @ready="onEditorReady"
          @save="saveFile"
          @start="start(...$event)"
          @tokenizer-update="onChange"
        />
      </pane>
      <pane :size="100 - editorBoxSize">
        <script-debug-panel
          v-model:debug="debug"
          v-model:messages="messages"
          :show-debug="showDebug"
          :script-id="scriptId"
          @step="step"
          @execute-debug="executeDebug"
          @message-sort-order="messageSortOrder"
        />
      </pane>
    </splitpanes>
  </div>

  <script-runner-inline
    v-else
    ref="inlineEditor"
    v-model:filename-select="filenameSelect"
    v-model:messages="messages"
    :file-list="fileList"
    :start-or-go-button="startOrGoButton"
    :start-or-go-disabled="startOrGoDisabled"
    :execute-user="executeUser"
    :suite-runner="suiteRunner"
    :pause-or-retry-button="pauseOrRetryButton"
    :pause-or-retry-disabled="pauseOrRetryDisabled"
    :stop-disabled="stopDisabled"
    :messages-newest-on-top="messagesNewestOnTop"
    @show-execute-selection-menu="showExecuteSelectionMenu"
    @start="start"
    @go="go"
    @pause-or-retry="pauseOrRetry"
    @stop="stop"
    @message-order-changed="messageSortOrder"
  />

  <file-open-save-dialog
    v-if="fileOpen"
    v-model="fileOpen"
    type="open"
    api-url="/script-api/scripts"
    @file="setFile($event)"
    @error="setError($event)"
    @clear-temp="clearTemp($event)"
  />
  <file-open-save-dialog
    v-if="showSaveAs"
    v-model="showSaveAs"
    type="save"
    api-url="/script-api/scripts"
    require-target-parent-dir
    :input-filename="filenameOrBlank"
    @filename="saveAsFilename($event)"
    @error="setError($event)"
    @clear-temp="clearTemp($event)"
  />
  <environment-dialog v-if="showEnvironment" v-model="showEnvironment" />
  <ask-dialog
    v-if="ask.show"
    v-model="ask.show"
    :question="ask.question"
    :default="ask.default"
    :password="ask.password"
    :answer-required="ask.answerRequired"
    @response="ask.callback"
  />
  <file-dialog
    v-if="file.show"
    v-model="file.show"
    :title="file.title"
    :message="file.message"
    :multiple="file.multiple"
    :filter="file.filter"
    @response="(files) => fileDialogCallback(files, scriptId)"
  />
  <bucket-dialog
    v-if="bucket.show"
    v-model="bucket.show"
    :title="bucket.title"
    :message="bucket.message"
    @response="bucketDialogCallback"
  />
  <information-dialog
    v-if="information.show"
    v-model="information.show"
    :title="information.title"
    :text="information.text"
    :width="information.width"
  />
  <event-list-dialog
    v-if="inputMetadata.show"
    v-model="inputMetadata.show"
    :events="inputMetadata.events"
    :time-zone="timeZone"
    new-metadata
    @close="inputMetadata.callback"
  />
  <overrides-dialog v-if="showOverrides" v-model="showOverrides" />
  <prompt-dialog
    v-if="prompt.show"
    v-model="prompt.show"
    :title="prompt.title"
    :subtitle="prompt.subtitle"
    :message="prompt.message"
    :details="prompt.details"
    :buttons="prompt.buttons"
    :layout="prompt.layout"
    :multiple="prompt.multiple"
    @response="prompt.callback"
  />
  <results-dialog
    v-if="results.show"
    v-model="results.show"
    :text="results.text"
  />
  <script-environment-dialog
    v-if="scriptEnvironment.show"
    v-model="scriptEnvironment.show"
    :input-environment="scriptEnvironment.env"
    @environment="environmentHandler"
  />
  <simple-text-dialog
    v-model="showSuiteError"
    title="Suite Analysis Error"
    :text="suiteError"
    :width="1000"
  />
  <critical-cmd-dialog
    v-model="criticalCmd.display"
    :uuid="criticalCmd.uuid"
    :cmd-string="criticalCmd.string"
    :cmd-user="criticalCmd.user"
    :persistent="true"
    @status="(value) => promptDialogCallback(value, scriptId)"
  />
  <command-editor-dialog ref="commandEditorDialog" @insert="insertCommand" />
  <v-bottom-sheet v-model="showScripts">
    <v-sheet class="pb-11 pt-5 px-5">
      <running-scripts
        v-if="showScripts"
        :connect-in-new-tab="!!fileModified"
        @disconnect="scriptDisconnect"
        @close="
          () => {
            showScripts = false
          }
        "
      />
    </v-sheet>
  </v-bottom-sheet>
</template>

<script>
import { format } from 'date-fns'
import { Splitpanes, Pane } from 'splitpanes'
import 'splitpanes/dist/splitpanes.css'

import { Api, Cable, OpenC3Api } from '@openc3/js-common/services'
import { useContainerHeight } from '@/composables/useContainerHeight'
import { ref, useTemplateRef } from 'vue'
import { useAsyncState } from '@vueuse/core'
import {
  CriticalCmdDialog,
  EnvironmentDialog,
  FileOpenSaveDialog,
  Openc3Screen,
  SimpleTextDialog,
  TopBar,
} from '@/components'
import { useClassificationBanner } from '@/tools/base'
import { fileIcon } from '@/util'
import { EventListDialog } from '@/tools/calendar'

import AskDialog from '@/tools/scriptrunner/Dialogs/AskDialog.vue'
import BucketDialog from '@/tools/scriptrunner/Dialogs/BucketDialog.vue'
import FileDialog from '@/tools/scriptrunner/Dialogs/FileDialog.vue'
import InformationDialog from '@/tools/scriptrunner/Dialogs/InformationDialog.vue'
import OverridesDialog from '@/tools/scriptrunner/Dialogs/OverridesDialog.vue'
import PromptDialog from '@/tools/scriptrunner/Dialogs/PromptDialog.vue'
import ResultsDialog from '@/tools/scriptrunner/Dialogs/ResultsDialog.vue'
import ScriptEnvironmentDialog from '@/tools/scriptrunner/Dialogs/ScriptEnvironmentDialog.vue'
import SuiteRunner from '@/tools/scriptrunner/SuiteRunner.vue'
import ScriptControlBar from '@/tools/scriptrunner/ScriptControlBar.vue'
import ScriptDebugPanel from '@/tools/scriptrunner/ScriptDebugPanel.vue'
import ScriptRunnerInline from '@/tools/scriptrunner/ScriptRunnerInline.vue'
import CommandEditorDialog from '@/tools/scriptrunner/Dialogs/CommandEditorDialog.vue'
import { MnemonicChecker } from '@/tools/scriptrunner/autocomplete'
import RunningScripts from '@/tools/scriptrunner/RunningScripts.vue'
import ScriptAceEditor from '@/tools/scriptrunner/ScriptAceEditor.vue'
import { useHandleWaiting } from '@/tools/scriptrunner/useHandleWaiting'
import { useScriptPrompts } from '@/tools/scriptrunner/useScriptPrompts'

import { detectLanguage, pythonTestSuiteText, rubyTestSuiteText } from './utils'

// Matches target_file.rb TEMP_FOLDER
const TEMP_FOLDER = '__TEMP__'
const NEW_FILENAME = '<Untitled>'
const START = 'Start'
const GO = 'Go'
const PAUSE = 'Pause'
const RETRY = 'Retry'

export default {
  components: {
    ScriptAceEditor,
    FileOpenSaveDialog,
    Openc3Screen,
    EnvironmentDialog,
    Splitpanes,
    Pane,
    TopBar,
    AskDialog,
    BucketDialog,
    FileDialog,
    InformationDialog,
    EventListDialog,
    OverridesDialog,
    PromptDialog,
    ResultsDialog,
    ScriptEnvironmentDialog,
    SimpleTextDialog,
    SuiteRunner,
    RunningScripts,
    CriticalCmdDialog,
    CommandEditorDialog,
    ScriptControlBar,
    ScriptDebugPanel,
    ScriptRunnerInline,
  },
  beforeRouteUpdate: async function (to, from, next) {
    if (to.params.id) {
      await this.tryLoadRunningScript(to.params.id)
      next()
    } else {
      next()
    }
  },
  props: {
    inline: {
      type: Boolean,
      default: false,
    },
    body: {
      type: String,
      default: null,
    },
    // Optional filename to use when running inline scripts
    // This allows relative path resolution to work correctly
    initialFilename: {
      type: String,
      default: null,
    },
  },
  emits: ['alert', 'script-id'],
  setup() {
    const containerHeight = useContainerHeight()

    const state = ref(null)
    const { handleWaiting, waitingTime } = useHandleWaiting(state)

    // Template refs
    const editorRef = useTemplateRef('editor')
    const editor = editorRef?.value?.editor || null

    // Script prompts and dialogs
    const {
      activePromptId,
      ask,
      bucket,
      file,
      prompt,
      information,
      inputMetadata,
      results,
      criticalCmd,
      bucketDialogCallback,
      fileDialogCallback,
      handleScript,
      promptDialogCallback,
    } = useScriptPrompts()

    const { classificationStyles } = useClassificationBanner()

    const cable = new Cable('/script-api/cable')

    const api = new OpenC3Api()
    const { state: screenKeywords } = useAsyncState(async () => {
      const response = await Api.get('/openc3-api/autocomplete/keywords/screen')
      return response.data
    }, null)

    const { state: timeZone } = useAsyncState(async () => {
      try {
        return await api.get_setting('time_zone')
      } catch {
        return 'local'
      }
    }, 'local')

    return {
      api,
      cable,
      containerHeight,
      editor,
      editorRef,
      // Make NEW_FILENAME available to the template
      NEW_FILENAME,
      screenKeywords,
      state,
      timeZone,
      handleWaiting,
      waitingTime,
      // Script prompts
      activePromptId,
      ask,
      bucket,
      file,
      prompt,
      information,
      inputMetadata,
      results,
      criticalCmd,
      bucketDialogCallback,
      fileDialogCallback,
      handleScript,
      promptDialogCallback,
      classificationStyles,
    }
  },
  data() {
    return {
      title: 'Script Runner',
      suiteRunner: false, // Whether to display the SuiteRunner GUI
      disableSuiteButtons: false,
      suiteMap: {
        // Useful for testing the various options in the SuiteRunner GUI
        // Suite: {
        //   teardown: true,
        //   groups: {
        //     Group: {
        //       setup: true,
        //       cases: ['case1', 'case2', 'really_long_test_case_name3'],
        //     },
        //     ReallyLongGroupName: {
        //       cases: ['case1', 'case2', 'case3'],
        //     },
        //   },
        // },
      },
      filenameSelect: null,
      currentFilename: null, // This is the currently shown filename while running
      showSave: false,
      showAlert: false,
      alertType: null,
      alertText: '',
      scriptId: null,
      startOrGoButton: START,
      startOrGoDisabled: false,
      envDisabled: false,
      pauseOrRetryButton: PAUSE,
      pauseOrRetryDisabled: false,
      stopDisabled: false,
      showEnvironment: false,
      showDebug: false,
      debug: '',
      showDisconnect: false,
      files: {},
      breakpoints: {},
      enableStackTraces: false,
      filename: NEW_FILENAME,
      readOnlyUser: false,
      executeUser: true,
      saveAllowed: true,
      tempFilename: null,
      fileModified: '',
      fileOpen: false,
      lockedBy: null,
      showEditingToast: false,
      showSaveAs: false,
      subscription: null,
      updateInterval: null,
      receivedEvents: [],
      messages: [],
      messagesNewestOnTop: true,
      maxArrayLength: 200,
      Range: ace.require('ace/range').Range,
      scriptEnvironment: {
        show: false,
        env: [],
      },
      showSuiteError: false,
      suiteError: '',
      mnemonicChecker: new MnemonicChecker(),
      showScripts: false,
      showOverrides: false,
      overridesCount: 0,
      screens: [],
      idCounter: 0,
      updateCounter: 0,
      recent: [],
      editorBoxSize: 50,
      editorContent: '',
      editorLanguage: 'ruby',
    }
  },
  computed: {
    // This is the list of files shown in the select dropdown
    fileList: function () {
      // this.files is the list of all files seen while running
      const filenames = Object.keys(this.files)
      filenames.push(this.fullFilename) // Make sure the currently shown filename is last
      return [...new Set(filenames)] // ensure unique
    },
    environmentModified: function () {
      return this.scriptEnvironment.env.length > 0
    },
    isLocked: function () {
      return !!this.lockedBy
    },
    // Returns the currently shown filename
    fullFilename: function () {
      if (this.currentFilename) return this.currentFilename
      // New filenames should not indicate modified
      if (this.filename === NEW_FILENAME) return NEW_FILENAME
      return `${this.filename} ${this.fileModified}`.trim()
    },
    // It's annoying for people (and tests) to clear the <Untitled>
    // when saving a new file so replace with blank
    // This makes sure that string doesn't show up in the dialog
    filenameOrBlank: function () {
      return this.filename === NEW_FILENAME ? '' : this.filename
    },
    menus: function () {
      return [
        {
          label: 'File',
          items: [
            {
              label: 'New File',
              icon: 'mdi-file-plus',
              disabled: this.scriptId || this.readOnlyUser,
              command: () => {
                this.newFileWithConfirm()
              },
            },
            {
              label: 'New Suite',
              icon: 'mdi-file-document-plus',
              disabled: this.scriptId || this.readOnlyUser,
              subMenu: [
                {
                  label: 'Ruby',
                  icon: 'mdi-language-ruby',
                  command: () => {
                    this.newTestSuite('ruby')
                  },
                },
                {
                  label: 'Python',
                  icon: 'mdi-language-python',
                  command: () => {
                    this.newTestSuite('python')
                  },
                },
              ],
            },
            {
              label: 'Open File',
              icon: 'mdi-folder-open',
              disabled: this.scriptId,
              command: () => {
                this.openFileWithConfirm()
              },
            },
            {
              label: 'Open Recent',
              icon: 'mdi-folder-open',
              disabled: this.scriptId,
              subMenu: this.recent,
            },
            {
              divider: true,
            },
            {
              label: 'Save File',
              icon: 'mdi-content-save',
              disabled: this.scriptId || this.readOnlyUser,
              command: () => {
                this.saveFile()
              },
            },
            {
              label: 'Save As...',
              icon: 'mdi-content-save',
              disabled: this.scriptId || this.readOnlyUser,
              command: () => {
                this.saveAs()
              },
            },
            {
              divider: true,
            },
            {
              label: 'Download',
              icon: 'mdi-cloud-download',
              disabled: this.scriptId,
              command: () => {
                this.download()
              },
            },
            {
              divider: true,
            },
            {
              label: 'Delete File',
              icon: 'mdi-delete',
              disabled: this.scriptId || this.readOnlyUser,
              command: () => {
                this.delete()
              },
            },
          ],
        },
        {
          label: 'Edit',
          items: [
            {
              label: 'Find',
              icon: 'mdi-magnify',
              command: () => {
                this.editor.execCommand('find')
              },
            },
            {
              label: 'Replace',
              icon: 'mdi-find-replace',
              disabled: this.scriptId,
              command: () => {
                this.editor.execCommand('replace')
              },
            },
            {
              label: 'Set Line Delay',
              icon: 'mdi-invoice-text-clock',
              disabled: this.scriptId,
              command: () => {
                this.$dialog.open({
                  title: 'Info',
                  text:
                    'You can set the line delay in seconds using the api method set_line_delay().<br/><br/>' +
                    'The default line delay is 0.1 seconds between lines. ' +
                    'Adding set_line_delay(0) to the top of your script will execute the script at maximum speed. ' +
                    'However, this can make it difficult to see and pause the script. ' +
                    'Executing set_line_delay(1) will cause a 1 second delay between lines.',
                  okText: 'OK',
                  okClass: 'primary',
                  validateText: null,
                  cancelText: null,
                  html: true,
                })
              },
            },
          ],
        },
        {
          label: 'Script',
          items: [
            {
              label: 'Execution Status',
              icon: 'mdi-run',
              command: () => {
                this.showScripts = true
              },
            },
            {
              divider: true,
            },
            {
              label: 'Global Environment',
              icon: 'mdi-library',
              disabled: this.scriptId,
              command: () => {
                this.showEnvironment = !this.showEnvironment
              },
            },
            {
              label: 'Metadata',
              icon: 'mdi-calendar',
              disabled: this.scriptId,
              command: () => {
                this.inputMetadata.callback = () => {}
                this.showMetadata()
              },
            },
            {
              label: 'Overrides',
              icon: 'mdi-swap-horizontal',
              command: () => {
                this.showOverrides = true
              },
            },
            {
              divider: true,
            },
            {
              label: 'Syntax Check',
              icon: 'mdi-file-check',
              disabled: this.scriptId,
              command: () => {
                this.syntaxCheck()
              },
            },
            {
              label: 'Mnemonic Check',
              icon: 'mdi-spellcheck',
              disabled: this.scriptId,
              command: () => {
                this.checkMnemonics()
              },
            },
            {
              label: 'Instrumented Script',
              icon: 'mdi-code-braces-box',
              disabled: this.scriptId,
              command: () => {
                this.showInstrumented()
              },
            },
            {
              label: 'Call Stack',
              icon: 'mdi-format-list-numbered',
              disabled: !this.scriptId,
              command: () => {
                this.showCallStack()
              },
            },
            {
              divider: true,
            },
            {
              label: 'Toggle Debug',
              icon: 'mdi-bug',
              command: () => {
                this.toggleDebug()
              },
            },
            {
              label: 'Toggle Disconnect',
              icon: 'mdi-connection',
              disabled: this.scriptId,
              command: () => {
                this.toggleDisconnect()
              },
            },
            {
              label: 'Enable Stack Traces',
              checkbox: true,
              checked: this.enableStackTraces,
              disabled: this.scriptId,
              command: () => {
                // Toggling the checkbox closes the menu so no need
                // to check state, just toggle existing value
                this.enableStackTraces = !this.enableStackTraces
              },
            },
            {
              divider: true,
            },
            {
              label: 'Delete All Breakpoints',
              icon: 'mdi-delete-circle-outline',
              disabled: this.scriptId,
              command: () => {
                this.deleteAllBreakpoints()
              },
            },
          ],
        },
      ]
    },
  },
  watch: {
    isLocked: function (val) {
      this.showEditingToast = val
      if (!this.suiteRunner) {
        this.startOrGoDisabled = val
      }
      if (this.readOnlyUser == false && val == false && !this.inline) {
        this.editor.setReadOnly(val)
      } else {
        this.editor.setReadOnly(true)
      }
    },
    fullFilename: function (filename) {
      this.filenameSelect = filename
      if (!this.inline) {
        if (filename === NEW_FILENAME) {
          localStorage.removeItem('script_runner__filename')
        } else {
          localStorage['script_runner__filename'] = filename
        }
      }
    },
    readOnlyUser: function (val) {
      if (this.editor) {
        if (val) {
          this.editor.setReadOnly(true)
          this.editor.renderer.$cursorLayer.element.style.display = 'none'
        } else {
          if (!this.inline) {
            this.editor.setReadOnly(false)
          }
          this.editor.renderer.$cursorLayer.element.style.display = null
        }
      }
    },
    showOverrides: async function (newVal, oldVal) {
      if (oldVal && !newVal) {
        await this.updateOverridesCount()
      }
    },
  },
  created: async function () {
    // Ensure Offline Access Is Setup For the Current User
    this.api.ensure_offline_access()

    await this.updateOverridesCount()
    let user = OpenC3Auth.user()
    let roles = OpenC3Auth.userroles()
    this.readOnlyUser = true
    this.executeUser = false
    for (let role of roles) {
      if (role == 'viewer') {
        continue
      }
      if (role == 'admin' || role == 'operator') {
        this.readOnlyUser = false
        this.executeUser = true
      } else if (role == 'runner') {
        this.executeUser = true
      } else {
        const response = await Api.get(`/openc3-api/roles/${role}`)
        if (response.data !== null && response.data.permissions !== undefined) {
          if (
            response.data.permissions.some((i) => i.permission == 'script_edit')
          ) {
            this.readOnlyUser = false
          }
          if (
            response.data.permissions.some((i) => i.permission == 'script_run')
          ) {
            this.executeUser = true
          }
        }
      }
    }
    // Output the userinfo for use in the SuiteRunner component
    if (!this.inline) {
      localStorage['script_runner__userinfo'] = JSON.stringify({
        name: user['preferred_username'],
        readOnly: this.readOnlyUser,
        execute: this.executeUser,
      })
    }
    if (this.readOnlyUser == true) {
      this.alertType = 'info'
      let text = `User ${user['preferred_username']} is read only`
      if (this.executeUser) {
        text += ' but can execute scripts'
      }
      this.alertText = text
      this.showAlert = true
    }
  },
  mounted: async function () {
    if (!this.inline && localStorage['script_runner__recent']) {
      this.recent = JSON.parse(localStorage['script_runner__recent'])
      // Rebuild the command since that doesn't get stringified
      this.recent = this.recent.map((item) => ({
        ...item,
        command: async (event) => {
          this.filename = event.label
          await this.reloadFile()
        },
      }))
    }
    if (!this.inline) {
      if (this.$route.query?.file) {
        this.filename = this.$route.query.file
        await this.reloadFile()
      } else if (this.$route.params?.id) {
        await this.tryLoadRunningScript(this.$route.params.id)
      } else {
        this.scriptId = sessionStorage.getItem('script_runner__script_id')
        if (this.scriptId) {
          await this.tryLoadRunningScript(this.scriptId)
        } else if (localStorage['script_runner__filename']) {
          this.filename = localStorage['script_runner__filename']
          await this.reloadFile(false)
        }
      }
    } else {
      if (this.body) {
        this.editorContent = this.body
        // If initialFilename is provided, use it for path resolution
        if (this.initialFilename) {
          this.filename = this.initialFilename
        }
      }
    }
    this.updateInterval = setInterval(async () => {
      this.processReceived()
    }, 100) // Every 100ms
  },
  beforeUnmount() {
    if (this.scriptId && !this.inline) {
      sessionStorage.setItem('script_runner__script_id', this.scriptId)
    }
  },
  unmounted() {
    this.unlockFile()
    if (this.updateInterval != null) {
      clearInterval(this.updateInterval)
    }
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
    this.cable.disconnect()
  },
  methods: {
    updateOverridesCount: async function () {
      const result = await this.api.get_overrides()
      this.overridesCount = result.length
    },
    handleCommandEditor({ cmdString, isEditing, editLine }) {
      this.$refs.commandEditorDialog.open({
        cmdString,
        isEditing,
        editLine,
      })
    },
    insertCommand({ commandString, isEditing, editLine }) {
      if (!this.editor) return

      if (isEditing && editLine !== null) {
        // Replace the existing line
        const line = this.editor.session.getLine(editLine)
        const indent = line.match(/^\s*/)[0] // Preserve indentation
        // Extract trailing comment if present
        const commentMatch = line.match(/\s+#.*$/)
        const trailingComment = commentMatch ? commentMatch[0] : ''
        const newLine = `${indent}cmd("${commandString}")${trailingComment}`
        const Range = this.Range
        this.editor.session.replace(
          new Range(editLine, 0, editLine, line.length),
          newLine,
        )
      } else {
        // Insert a new command at the cursor position
        const position = this.editor.getCursorPosition()
        this.editor.session.insert(position, `cmd("${commandString}")\n`)
      }

      this.fileModified = true
    },
    doResize() {
      this.editorRef?.resize()
    },
    scriptDisconnect() {
      if (this.subscription) {
        this.subscription.unsubscribe()
        this.subscription = null
      }
      this.receivedEvents.length = 0 // Clear any unprocessed events
    },
    showMetadata: async function () {
      const response = await Api.get('/openc3-api/metadata')
      // TODO: This is how Calendar creates new metadata items via makeMetadataEvent
      this.inputMetadata.events = response.data.map((event) => {
        return {
          name: 'Metadata',
          start: new Date(event.start * 1000),
          end: new Date(event.start * 1000),
          color: event.color,
          type: event.type,
          timed: true,
          metadata: event,
        }
      })
      this.inputMetadata.show = true
    },
    messageSortOrder(order) {
      // See ScriptLogMessages for these strings
      if (order === 'Newest on Top' && this.messagesNewestOnTop === false) {
        this.messagesNewestOnTop = true
        this.messages.reverse()
      } else if (
        order === 'Newest on Bottom' &&
        this.messagesNewestOnTop === true
      ) {
        this.messagesNewestOnTop = false
        this.messages.reverse()
      }
    },
    // This only gets called when the user changes the filename dropdown
    // Or when a user hits Go
    fileNameChanged(filename) {
      // Split off the '*' which indicates modified
      filename = filename.split('*')[0]
      this.editorContent = this.files[filename].content
      this.restoreBreakpoints(filename)
      this.editorRef?.clearSelection()
      this.removeAllMarkers()
      this.editor.session.addMarker(
        new this.Range(
          this.files[filename].lineNo - 1,
          0,
          this.files[filename].lineNo - 1,
          1,
        ),
        `${this.state}Marker`,
        'fullLine',
      )
      this.editor.gotoLine(this.files[filename].lineNo)
    },
    tryLoadRunningScript: async function (id) {
      try {
        const response = await Api.get(`/script-api/running-script/${id}`)
        if (response.data) {
          let state = response.data.state
          // Check for all the completed states, see is_complete in script_status_model
          if (
            state !== 'completed' &&
            state !== 'completed_errors' &&
            state !== 'stopped' &&
            state !== 'crashed' &&
            state !== 'killed'
          ) {
            this.filename = response.data.filename
            this.tryLoadSuites(response)
            this.initScriptStart()
            this.scriptStart(id)
          } else {
            this.$notify.caution({
              title: `Script ${id} has already completed`,
              body: 'Check the Completed Scripts below ...',
            })
            this.scriptComplete()
            this.showScripts = true
          }
        } else {
          throw new Error(`Unable to load state for running script ${id}`) // Get into the following catch block because this should be handled the same as an error like 404
        }
      } catch (error) {
        // TODO: This is appearing on the main page which is blurred from the presence of the bottom sheet
        // We should probably not allow the bottom sheet to blur the screen
        this.$notify.caution({
          title: `Running Script ${id} not found`,
          body: 'Check the Completed Scripts below ...',
        })
        this.scriptComplete()
        this.showScripts = true
      }
    },
    tryLoadSuites: function (response) {
      if (response.data.suites) {
        this.startOrGoDisabled = true
        this.suiteRunner = true
        this.suiteMap = JSON.parse(response.data.suites)
      }
      this.doResize()
    },
    getBreakpointRows: function () {
      return this.editorRef?.getBreakpointRows() || []
    },
    restoreBreakpoints: function (filename) {
      this.editorRef?.restoreBreakpoints(this.breakpoints[filename])
    },
    deleteAllBreakpoints: async function () {
      await this.$dialog.confirm(
        'Permanently delete all breakpoints for ALL scripts?',
        {
          okText: 'Delete',
          cancelText: 'Cancel',
        },
      )
      await Api.delete('/script-api/breakpoints/delete/all')
      this.editorRef?.clearBreakpoints()
    },
    suiteRunnerButton(event) {
      if (this.startOrGoButton === START) {
        this.start(event, 'suiteRunner')
      } else {
        this.go(event, 'suiteRunner')
      }
    },
    async keydown(event) {
      // Don't ever save if running or readonly
      if (this.scriptId || this.editor?.getReadOnly()) {
        return
      }
      // NOTE: Chrome does not allow overriding Ctrl-N, Ctrl-Shift-N, Ctrl-T, Ctrl-Shift-T, Ctrl-W
      // NOTE: metaKey == Command on Mac
      if (
        (event.metaKey || event.ctrlKey) &&
        event.keyCode === 'S'.charCodeAt(0)
      ) {
        if (event.shiftKey) {
          event.preventDefault()
          this.saveAs()
        } else {
          event.preventDefault()
          await this.saveFile()
        }
      }
    },
    onChange() {
      // Don't track changes when we're running or read-only (locked)
      if (this.scriptId || this.editor?.getReadOnly()) {
        return
      }
      if (this.editor?.session.getUndoManager().canUndo()) {
        this.fileModified = '*'
      } else {
        this.fileModified = ''
      }
    },
    checkMnemonics: async function () {
      let filename = this.filename
      // Check if the extension is not .rb or .py
      if (
        this.filename !== NEW_FILENAME &&
        !(filename.endsWith('.rb') || filename.endsWith('.py'))
      ) {
        const response = await Api.post(
          `/script-api/scripts/${this.filename}/mnemonics`,
          {
            data: this.editorContent,
            headers: {
              Accept: 'application/json',
              'Content-Type': 'plain/text',
            },
          },
        )
        let alertText = ''
        alertText += `<strong>${response.data.title}</strong><br/><br/>`
        alertText += JSON.parse(response.data.description)
        this.$dialog.alert(alertText.trim(), { html: true })
      } else {
        const { skipped, problems } = await this.mnemonicChecker.checkText(
          this.editorContent,
        )
        let alertText = ''
        if (problems.length) {
          const problemText = problems
            .map((problem) => `${problem.lineNumber}: ${problem.error}`)
            .join('<br/>')
          alertText += `<strong>The following lines have problems:</strong><br/>${problemText}<br/><br/>`
        }
        if (skipped.length) {
          alertText +=
            '<strong>Mnemonics with string interpolation were not checked.</strong>'
        }
        if (alertText === '') {
          alertText = '<strong>Everything looks good!</strong>'
        }
        this.$dialog.alert(alertText.trim(), { html: true })
      }
    },
    initScriptStart() {
      this.disableSuiteButtons = true
      this.startOrGoDisabled = true
      this.envDisabled = true
      this.pauseOrRetryDisabled = true
      this.stopDisabled = true
      this.state = 'Connecting...'
      this.startOrGoButton = GO
      this.editor.setReadOnly(true)
    },
    scriptStart: async function (id) {
      this.$emit('script-id', id)
      this.scriptId = id
      const subscription = await this.cable.createSubscription(
        'RunningScriptChannel',
        window.openc3Scope,
        {
          received: (data) => this.received(data),
        },
        {
          id: this.scriptId,
        },
      )
      this.subscription = subscription
    },
    async scriptComplete() {
      // Make sure we process no more events
      if (this.subscription) {
        await this.subscription.unsubscribe()
        this.subscription = null
      }
      this.receivedEvents.length = 0 // Clear any unprocessed events

      await this.reloadFile() // Make sure the right file is shown
      // We may have changed the contents (if there were sub-scripts)
      // so don't let the undo manager think this is a change
      this.editor.session.getUndoManager().reset()
      if (this.readOnlyUser == false && !this.inline) {
        this.editor.setReadOnly(false)
      }

      this.scriptId = null // No current scriptId
      sessionStorage.removeItem('script_runner__script_id')

      // Lastly enable the buttons so another script can start
      this.disableSuiteButtons = false
      this.startOrGoButton = START
      this.pauseOrRetryButton = PAUSE
      // Disable start if suiteRunner
      this.startOrGoDisabled = this.suiteRunner
      this.envDisabled = false
      this.pauseOrRetryDisabled = true
      this.stopDisabled = true
      // Overrides can be set from a script
      await this.updateOverridesCount()
    },
    environmentHandler: function (event) {
      this.scriptEnvironment.env = event
    },
    async start(
      event = null,
      suiteRunner = null,
      line_no = null,
      end_line_no = null,
    ) {
      // Initialize variables and disable buttons before actually posting.
      // This prevents delays in the backend from delaying frontend changes
      // like disabling start which could allow users to click start twice.
      this.initScriptStart()
      await this.saveFile('start')
      this.saveAllowed = false
      let filename = this.filename
      if (this.filename === NEW_FILENAME) {
        // NEW_FILENAME so use tempFilename created by saveFile()
        filename = this.tempFilename
      }
      let url = `/script-api/scripts/${filename}/run`
      if (this.showDisconnect) {
        url += '/disconnect'
      }
      let env = this.scriptEnvironment.env
      if (this.enableStackTraces) {
        env = env.concat({
          key: 'OPENC3_FULL_BACKTRACE',
          value: '1',
        })
      }
      let data = {
        environment: env,
      }
      if (suiteRunner) {
        // TODO 7.0: Should suiteRunner be snake case?
        data['suiteRunner'] = event
      }
      if (line_no !== null) {
        data['line_no'] = line_no
      }
      if (end_line_no !== null) {
        data['end_line_no'] = end_line_no
      }
      try {
        const response = await Api.post(url, { data })
        this.scriptStart(response.data)
      } catch (error) {
        this.scriptComplete()
      }
    },
    go() {
      // Ensure we're on the correct filename when we hit go
      // They may have changed it using the drop down
      this.filenameSelect = this.currentFilename
      this.fileNameChanged(this.currentFilename)
      Api.post(`/script-api/running-script/${this.scriptId}/go`)
    },
    pauseOrRetry() {
      if (this.pauseOrRetryButton === PAUSE) {
        Api.post(`/script-api/running-script/${this.scriptId}/pause`)
      } else {
        this.pauseOrRetryButton = PAUSE
        Api.post(`/script-api/running-script/${this.scriptId}/retry`)
      }
    },
    stop() {
      Api.post(`/script-api/running-script/${this.scriptId}/stop`)
    },
    step() {
      Api.post(`/script-api/running-script/${this.scriptId}/step`)
    },
    processLine(data) {
      if (data.filename && data.filename !== this.currentFilename) {
        if (!this.files[data.filename]) {
          // We don't have the contents of the running file (probably because connected to running script)
          // Set the contents initially to an empty string so we don't start slamming the API
          this.files[data.filename] = { content: '', lineNo: 0 }

          // Request the script we need
          Api.get(`/script-api/scripts/${data.filename}`)
            .then((response) => {
              // Success - Save the script text and mark the currentFilename as null
              // so it will get loaded in on the next line executed
              this.files[data.filename] = {
                content: response.data.contents,
                lineNo: 0,
              }
              this.breakpoints[data.filename] = response.data.breakpoints
              this.restoreBreakpoints(data.filename)
              this.currentFilename = null
            })
            .catch((err) => {
              // Error - Restore the file contents to null so we'll try the API again on the next line
              this.files[data.filename] = null
            })
        } else {
          this.currentFilename = data.filename
          this.editorContent = this.files[data.filename].content
          this.restoreBreakpoints(data.filename)
          this.editorRef?.clearSelection()
        }
      }
      this.state = data.state
      const markers = this.editor?.session.getMarkers() || {}
      switch (this.state) {
        // Handle all the script states, see script_status_model for details
        // spawning, init, running, paused, waiting, breakpoint, error, crashed, stopped, completed, completed_errors, killed
        case 'running':
          this.handleWaiting()
          this.startOrGoDisabled = false
          this.pauseOrRetryDisabled = false
          this.stopDisabled = false
          this.pauseOrRetryButton = PAUSE

          this.removeAllMarkers()
          if (this.editor) {
            this.editor.session.addMarker(
              new this.Range(data.line_no - 1, 0, data.line_no - 1, 1),
              'runningMarker',
              'fullLine',
            )
            this.editor.gotoLine(data.line_no)
          }
          this.files[data.filename].lineNo = data.line_no
          break
        case 'error':
          this.pauseOrRetryButton = RETRY
        // Deliberate fall through (no break)
        case 'spawning': // wait for script to be spawned
        case 'init': // wait for script to initialize
        case 'paused':
        case 'waiting':
        case 'breakpoint':
          this.handleWaiting()
          this.startOrGoDisabled = false
          this.pauseOrRetryDisabled = false
          this.stopDisabled = false
          let existing = Object.keys(markers).filter(
            (key) => markers[key].clazz === `${this.state}Marker`,
          )
          if (existing.length === 0) {
            this.removeAllMarkers()
            let line = data.line_no > 0 ? data.line_no : 1
            if (this.editor) {
              this.editor.session.addMarker(
                new this.Range(line - 1, 0, line - 1, 1),
                `${this.state}Marker`,
                'fullLine',
              )
              this.editor.gotoLine(line)
            }
            // Fatal errors don't always have a filename set
            if (data.filename) {
              this.files[data.filename].lineNo = line
            }
          }
          break
        case 'completed':
        case 'completed_errors':
        case 'stopped':
        case 'crashed':
        case 'killed':
          // Only remove markers here - full cleanup is handled by the
          // 'complete' message in processReceived() which always follows.
          // Calling scriptComplete() here would unsubscribe the channel
          // before the 'complete' message (with suite report) arrives.
          this.removeAllMarkers()
          break

        default:
          break
      }
    },
    processReceived() {
      let count = 0
      for (let data of this.receivedEvents) {
        count += 1
        // console.log(data) // Uncomment for debugging
        let index = 0
        switch (data.type) {
          case 'file':
            this.files[data.filename] = { content: data.text, lineNo: 0 }
            this.breakpoints[data.filename] = data.breakpoints
            if (this.currentFilename === data.filename) {
              this.restoreBreakpoints(data.filename)
            }
            break
          case 'line':
            // A further optimization would be to only process the last line of a batch
            // However with some testing this did not seem to make much difference
            // and was preventing the highlighting of the final line of a script because
            // the last line of the final batch was line_number 0 with state stopped
            // and that would never highlight the actual final line
            this.processLine(data)
            break
          case 'output':
            // data.line can consist of multiple lines split by newlines,
            // thus we split and only output if the content is not empty.
            // We also need to ensure it's properly serialized as a string.
            let dataLine = data.line
            if (dataLine === null || dataLine === undefined) {
              dataLine = ''
            } else if (typeof dataLine === 'object') {
              dataLine = JSON.stringify(dataLine)
            } else {
              dataLine = String(dataLine)
            }
            for (const line of dataLine.split('\n')) {
              if (line) {
                if (this.messagesNewestOnTop) {
                  this.messages.unshift({ message: line })
                } else {
                  this.messages.push({ message: line })
                }
              }
            }
            while (this.messages.length > this.maxArrayLength) {
              this.messages.pop()
            }
            break
          case 'script':
            this.handleScript(data, this.scriptId, this.showMetadata)
            break
          // DEPRECATED because the 'complete' message now includes the report
          case 'report':
            this.results.text = data.report
            this.results.show = true
            break
          case 'complete':
            if (data.report) {
              this.results.text = data.report
              this.results.show = true
            }
            this.removeAllMarkers()
            this.scriptComplete()
            break
          case 'step':
            this.showDebug = true
            break
          case 'screen':
            let found = false
            let definition = {}
            for (screen of this.screens) {
              if (
                screen.target == data.target_name &&
                screen.screen == data.screen_name
              ) {
                definition = screen
                found = true
                break
              }
              index += 1
            }
            definition.target = data.target_name
            definition.screen = data.screen_name
            definition.definition = data.definition
            if (data.x) {
              definition.left = data.x
            } else {
              definition.left = 0
            }
            if (data.y) {
              definition.top = data.y
            } else {
              definition.top = 0
            }
            definition.count = this.updateCounter++
            if (!found) {
              definition.id = this.idCounter++
              this.screens[this.screens.length] = definition
            } else {
              this.screens[index] = definition
            }
            break
          case 'clearscreen':
            for (screen of this.screens) {
              if (
                screen.target == data.target_name &&
                screen.screen == data.screen_name
              ) {
                this.screens.splice(index, 1)
                break
              }
              index += 1
            }
            break
          case 'clearallscreens':
            this.screens = []
            break
          case 'downloadfile':
            const url = window.location.origin + data.url
            this.downloadFile(url, data.filename)
            break
          case 'opentab':
            window.open(data.url, '_blank')
            break
          default:
            // console.log('Unexpected ActionCable message')
            // console.log(data)
            break
        }
      }

      // Remove all the events we processed
      this.receivedEvents.splice(0, count)
    },
    received(data) {
      this.cable.recordPing()
      this.receivedEvents.push(data)
    },
    setError(event) {
      this.alertType = 'error'
      this.alertText = `Error: ${event}`
      this.showAlert = true
    },
    // ScriptRunner File menu actions
    async confirmUnsavedChanges() {
      if (this.fileModified === '*') {
        return await this.$dialog.confirm(
          'You have unsaved changes. Are you sure you want to continue?',
          {
            okText: 'Continue',
            cancelText: 'Cancel',
          },
        )
      }
      return true
    },
    async newFileWithConfirm() {
      const confirmed = await this.confirmUnsavedChanges()
      if (confirmed) {
        this.newFile()
      }
    },
    newFile() {
      this.unlockFile()
      this.filename = NEW_FILENAME
      this.currentFilename = null
      this.tempFilename = null
      this.files = {} // Clear the cached file list
      this.editorContent = ''
      this.saveAllowed = true
      this.fileModified = ''
      this.suiteRunner = false
      this.startOrGoDisabled = false
      this.envDisabled = false
      if (!this.inline) {
        this.$router
          .replace({
            name: 'ScriptRunner',
          })
          // catch the error in case we route to where we already are
          .catch((err) => {})
        document.title = 'Script Runner'
      }
      this.doResize()
    },
    async newTestSuite(language) {
      const confirmed = await this.confirmUnsavedChanges()
      if (!confirmed) return
      this.newFile()
      if (language === 'ruby') {
        this.editorContent = rubyTestSuiteText
      } else if (language === 'python') {
        this.editorContent = pythonTestSuiteText
      }
      await this.saveFile('auto')
    },
    addToRecent(filename) {
      // See if this filename is already in the recent ... if so remove it
      let index = this.recent.findIndex((i) => i.label === filename)
      if (index !== -1) {
        this.recent.splice(index, 1)
      }
      // Push this filename to the front of the recently used
      this.recent.unshift({
        label: filename,
        icon: fileIcon(filename),
        command: async (event) => {
          const confirmed = await this.confirmUnsavedChanges()
          if (!confirmed) return
          this.filename = event.label
          await this.reloadFile()
        },
      })
      if (this.recent.length > 8) {
        this.recent.pop()
      }
      // This only stringifies the label and icon ... not the command
      if (!this.inline) {
        localStorage['script_runner__recent'] = JSON.stringify(this.recent)
      }
    },
    removeFromRecent(filename) {
      this.recent = this.recent.filter((entry) => entry.label !== filename)
      if (!this.inline) {
        localStorage['script_runner__recent'] = JSON.stringify(this.recent)
        if (localStorage['script_runner__filename'] === filename) {
          localStorage.removeItem('script_runner__filename')
        }
      }
    },
    async openFileWithConfirm() {
      const confirmed = await this.confirmUnsavedChanges()
      if (confirmed) {
        this.openFile()
      }
    },
    openFile() {
      this.fileOpen = true
    },
    async reloadFile(showError = true) {
      // Disable start while we're loading the file so we don't hit Start
      // before it's fully loaded and then save over it with a blank file
      this.saveAllowed = false
      this.startOrGoDisabled = true
      try {
        const response = await Api.get(`/script-api/scripts/${this.filename}`, {
          headers: {
            Accept: 'application/json',
            'Ignore-Errors': '404',
          },
        })
        const file = {
          name: this.filename,
          contents: response.data.contents,
        }
        if (response.data.suites) {
          file['suites'] = JSON.parse(response.data.suites)
        }
        if (response.data.error) {
          file['error'] = response.data.error
        }
        if (response.data.success) {
          file['success'] = response.data.success
        }
        const locked = response.data.locked
        const breakpoints = response.data.breakpoints
        this.setFile({ file, locked, breakpoints }, true)
        this.saveAllowed = true
      } catch (error) {
        if (showError === true) {
          this.$notify.caution({
            title: 'File Open Error',
            body: `Failed to open ${this.filename} due to ${error}`,
          })
        }
        this.removeFromRecent(this.filename)
        this.newFile() // Reset the GUI
      }
    },
    // Called by the FileOpenDialog to set the file contents
    setFile({ file, locked, breakpoints }, local = false) {
      this.files = {} // Clear the cached file list
      // Split off the ' *' which indicates a file is modified on the server
      let newFilename = file.name.split('*')[0]
      if (local === false) {
        // We only need to unlock if the file is different
        if (this.filename !== newFilename) {
          this.unlockFile() // first unlock what was just being edited
          this.lockedBy = locked
        }
      }
      this.filename = newFilename
      if (!this.inline) {
        // Update the URL with the filename
        this.$router
          .replace({
            name: 'ScriptRunner',
            query: {
              file: this.filename,
            },
          })
          // catch the error in case we route to where we already are
          .catch((err) => {})

        // Update the browser tab with the name of the file first
        // so squished tabs are still useful, followed by the rest
        // of the path for context. Target name will be first which
        // is probably the most useful part of the path.
        let parts = this.filename.split('/')
        document.title = `${parts.pop()} (${parts.join('/')})`
      }

      if (this.filename.split('.').pop() === 'py') {
        this.editorLanguage = 'python'
      } else {
        this.editorLanguage = 'ruby'
      }
      this.currentFilename = null
      this.editorContent = file.contents
      this.breakpoints[this.filename] = breakpoints
      this.restoreBreakpoints(this.filename)
      this.fileModified = ''
      this.envDisabled = false
      this.addToRecent(this.filename)

      if (file.suites) {
        this.suiteRunner = true
        this.suiteMap = file.suites
        this.startOrGoDisabled = true
      } else {
        this.suiteRunner = false
        this.startOrGoDisabled = false
      }
      if (file.error) {
        this.suiteError = file.error
        this.showSuiteError = true
      }
      // Disable suite buttons if we didn't successfully parse the suite
      this.disableSuiteButtons = file.success == false
      this.doResize()
    },
    clearTemp() {
      this.recent = this.recent.filter(
        (entry) => !entry.label.includes('__TEMP__'),
      )
      if (!this.inline) {
        localStorage['script_runner__recent'] = JSON.stringify(this.recent)
      }
    },
    // saveFile takes a type to indicate if it was called by the Menu
    // or automatically by 'Start' (to ensure a consistent backend file) or autoSave
    async saveFile(type = 'menu') {
      if (this.readOnlyUser) {
        return
      }
      if (this.saveAllowed) {
        const breakpoints = this.getBreakpointRows()
        if (this.filename === NEW_FILENAME) {
          if (type === 'menu') {
            // Menu driven saves on a new file should prompt SaveAs
            this.saveAs()
            return
          } else {
            // start or auto with NEW_FILENAME
            if (this.tempFilename === null) {
              let language = detectLanguage(this.editorContent)
              if (language === 'unknown') {
                language = AceEditorUtils.getDefaultScriptingLanguage()
              }
              const uuid = crypto.randomUUID().split('-')[0]
              let postfix
              if (language === 'ruby') {
                postfix = '_temp.rb'
              } else if (language === 'python') {
                postfix = '_temp.py'
              } else {
                // No autosave for unknown language
                return
              }
              this.tempFilename = `${TEMP_FOLDER}/${format(Date.now(), 'yyyy_MM_dd_HH_mm_ss_SSS')}_${uuid}${postfix}`
              this.filename = this.tempFilename
              this.addToRecent(this.filename)
            }
          }
        }
        this.showSave = true
        try {
          const response = await Api.post(
            `/script-api/scripts/${this.filename}`,
            {
              data: {
                text: this.editorContent, // Pass in the raw file text
                breakpoints,
              },
            },
          )
          if (response.status == 200) {
            if (response.data.suites) {
              this.startOrGoDisabled = true
              this.suiteRunner = true
              this.suiteMap = JSON.parse(response.data.suites)
            } else {
              this.startOrGoDisabled = false
              this.suiteRunner = false
              this.suiteMap = {}
            }
            if (response.data.error) {
              this.suiteError = response.data.error
              this.showSuiteError = true
            }
            this.fileModified = ''
            setTimeout(() => {
              this.showSave = false
            }, 2000)
          } else {
            this.showSave = false
            this.alertType = 'error'
            this.alertText = `Error saving file. Code: ${response.status} Text: ${response.statusText}`
            this.showAlert = true
          }
          this.lockFile() // Ensure this file is locked for editing
          this.doResize()
        } catch ({ response }) {
          this.showSave = false
          // 422 error means we couldn't parse the script file into Suites
          // response.data.suites holds the parse result
          if (response.status == 422) {
            this.alertType = 'error'
            this.alertText = response.data.suites
          } else {
            this.alertType = 'error'
            this.alertText = `Error saving file. Code: ${response.status} Text: ${response.statusText}`
          }
          this.showAlert = true
        }
      } else {
        this.setError('Attempt to save file when not allowed')
      }
    },
    saveAs() {
      this.showSaveAs = true
    },
    async saveAsFilename(filename) {
      this.filename = filename.split('*')[0]
      this.currentFilename = null
      if (this.tempFilename) {
        Api.post(`/script-api/scripts/${this.tempFilename}/delete`)
        this.tempFilename = null
      }
      await this.saveFile('menu')
    },
    delete: async function () {
      let filename = this.filename
      if (this.tempFilename) {
        filename = this.tempFilename
      }
      try {
        await this.$dialog.confirm(`Permanently delete file: ${filename}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        await Api.post(`/script-api/scripts/${filename}/delete`, {
          data: {},
        })
        this.removeFromRecent(filename)
        this.newFile()
      } catch (error) {
        if (error !== true) {
          const alertObject = {
            text: `Failed Multi-Delete. ${error}`,
            type: 'error',
          }
          this.$emit('alert', alertObject)
        }
      }
    },
    downloadFile(href, filename) {
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = href
      link.setAttribute('download', filename)
      link.click()
    },
    download() {
      const blob = new Blob([this.editorContent], {
        type: 'text/plain',
      })
      const url = URL.createObjectURL(blob)
      this.downloadFile(url, this.filename)
    },
    fetchInformation: async function (path) {
      const response = await Api.post(
        `/script-api/scripts/${this.filename}/${path}`,
        {
          data: this.editorContent,
          headers: {
            Accept: 'application/json',
            'Content-Type': 'plain/text',
          },
        },
      )
      this.information.title = response.data.title
      this.information.text = JSON.parse(response.data.description)
      this.information.show = true
    },
    // ScriptRunner Script menu actions
    syntaxCheck: async function () {
      await this.fetchInformation('syntax')
      this.information.width = '600'
    },
    showInstrumented: async function () {
      await this.fetchInformation('instrumented')
      this.information.width = '90vw'
    },
    showCallStack() {
      Api.post(`/script-api/running-script/${this.scriptId}/backtrace`)
    },
    toggleDebug() {
      this.showDebug = !this.showDebug
      if (this.showDebug) {
        this.$nextTick(() => {
          this.$refs.debug.focus()
        })
      }
    },
    toggleDisconnect() {
      this.showDisconnect = !this.showDisconnect
    },
    executeDebug(debugCommand) {
      // Post the debug command to the API, output is processed by receive()
      Api.post(`/script-api/running-script/${this.scriptId}/debug`, {
        data: {
          args: debugCommand,
        },
      })
    },
    removeAllMarkers: function () {
      if (!this.editor) return
      const allMarkers = this.editor.session.getMarkers()
      Object.keys(allMarkers)
        .filter((key) => allMarkers[key].type === 'fullLine')
        .forEach((marker) => this.editor.session.removeMarker(marker))
    },
    confirmLocalUnlock: async function () {
      await this.$dialog.confirm(
        'Are you sure you want to unlock this script for editing? If another user is editing this script, your changes might conflict with each other.',
        {
          okText: 'Force Unlock',
          cancelText: 'Cancel',
        },
      )
      this.lockedBy = null
      this.lockFile() // Re-lock it as this user so it's locked for anyone else who opens it
    },
    lockFile: function () {
      if (!this.readOnlyUser) {
        return Api.post(`/script-api/scripts/${this.filename}/lock`)
      }
    },
    unlockFile: function () {
      if (this.filename !== NEW_FILENAME && !this.readOnlyUser) {
        Api.post(`/script-api/scripts/${this.filename}/unlock`)
      }
    },
    backToNewScript: async function () {
      // Disconnect from the current script
      this.scriptDisconnect()
      // Clear script-related state
      this.removeAllMarkers()
      await this.scriptComplete()
      // Create a new blank script
      this.newFile()
    },
    screenId(id) {
      return 'scriptRunnerScreen' + id
    },
    closeScreen(id) {
      let index = 0
      for (screen of this.screens) {
        if (screen.id == id) {
          this.screens.splice(index, 1)
          break
        }
        index += 1
      }
    },
    // ACE Editor event handlers
    onEditorReady() {
      // Editor is ready and initialized
      // Get the editor instance and add event listeners
      if (this.editor) {
        this.editor.container.addEventListener('resize', this.doResize)
        this.editor.container.addEventListener('keydown', this.keydown)
      }
    },
  },
}
</script>

<style scoped>
hr {
  color: white;
  height: 3px;
}

.editor {
  height: 100%;
  width: 100%;
  position: relative;
  font-size: 16px;
}
</style>
<style>
.splitpanes--horizontal > .splitpanes__splitter {
  min-height: 4px;
  position: relative;
  top: 4px;
  background-color: grey;
  width: 5%;
  margin: auto;
  cursor: row-resize;
}

.runningMarker {
  position: absolute;
  background: rgba(0, 255, 0, 0.5);
  z-index: 20;
}

.waitingMarker {
  position: absolute;
  background: rgba(0, 155, 0, 1);
  z-index: 20;
}

.breakpointMarker {
  position: absolute;
  border-style: solid;
  border-color: red;
  background: rgba(0, 255, 0, 0.5);
  z-index: 20;
}

.pausedMarker {
  position: absolute;
  background: rgba(0, 140, 255, 0.5);
  z-index: 20;
}

.errorMarker {
  position: absolute;
  background: rgba(255, 0, 119, 0.5);
  z-index: 20;
}

.saving {
  z-index: 20;
  opacity: 0.35;
}

.ace_gutter {
  /* Screens have a default z-index of 3 so get below that */
  z-index: 2;
}

.ace_gutter-cell.ace_breakpoint {
  border-radius: 20px 0px 0px 20px;
  box-shadow: 0px 0px 1px 1px red inset;
}

.grid {
  position: relative;
}

.item {
  /* TODO: this non-scoped generic class name conflicts with other things and should be scoped or renamed. */
  position: absolute;
  display: block;
  margin: 5px;
  z-index: 1;
}

.item-content {
  position: relative;
  cursor: pointer;
  border-radius: 6px;
}

.apply-top .v-snackbar__wrapper {
  top: var(--classification-height-top);
}
</style>
