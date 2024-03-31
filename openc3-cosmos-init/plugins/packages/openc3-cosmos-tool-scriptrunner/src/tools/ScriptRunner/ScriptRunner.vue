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
# All changes Copyright 2023, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <top-bar :menus="menus" :title="title" />
    <v-snackbar v-model="showAlert" top :color="alertType" :timeout="3000">
      <v-icon> mdi-{{ alertType }} </v-icon>
      {{ alertText }}
      <template v-slot:action="{ attrs }">
        <v-btn text v-bind="attrs" @click="showAlert = false"> Close </v-btn>
      </template>
    </v-snackbar>
    <v-snackbar v-model="showReadOnlyToast" top :timeout="-1" color="orange">
      <v-icon> mdi-pencil-off </v-icon>
      {{ lockedBy }} is editing this script. Editor is in read-only mode
      <template v-slot:action="{ attrs }">
        <v-btn
          text
          v-bind="attrs"
          color="danger"
          @click="confirmLocalUnlock"
          data-test="unlock-button"
        >
          Unlock
        </v-btn>
        <v-btn
          text
          v-bind="attrs"
          @click="
            () => {
              showReadOnlyToast = false
            }
          "
        >
          dismiss
        </v-btn>
      </template>
    </v-snackbar>
    <div class="grid">
      <div
        class="item"
        v-for="def in screens"
        :key="def.id"
        :id="screenId(def.id)"
        ref="gridItem"
      >
        <div class="item-content">
          <openc3-screen
            :target="def.target"
            :screen="def.screen"
            :definition="def.definition"
            :keywords="screenKeywords"
            :initialFloated="true"
            :initialTop="def.top"
            :initialLeft="def.left"
            :initialZ="3"
            :minZ="3"
            :fixFloated="true"
            :count="def.count"
            @close-screen="closeScreen(def.id)"
            @delete-screen="closeScreen(def.id)"
          />
        </div>
      </div>
    </div>
    <v-card style="padding: 10px">
      <suite-runner
        v-if="suiteRunner"
        :suite-map="suiteMap"
        :disable-buttons="disableSuiteButtons"
        @button="suiteRunnerButton"
      />
      <div id="sr-controls">
        <v-row no-gutters justify="space-between">
          <v-icon v-if="showDisconnect" class="mr-2" color="red">
            mdi-connection
          </v-icon>
          <v-tooltip bottom>
            <template v-slot:activator="{ on, attrs }">
              <v-btn
                v-on="on"
                v-bind="attrs"
                icon
                @click="reloadFile"
                :disabled="filename === NEW_FILENAME"
              >
                <v-icon>mdi-cached</v-icon>
              </v-btn>
            </template>
            <span> Reload File </span>
          </v-tooltip>
          <v-select
            v-model="filenameSelect"
            @change="fileNameChanged"
            :items="fileList"
            :disabled="fileList.length <= 1"
            label="Filename"
            id="filename"
            data-test="filename"
            style="width: 300px"
            dense
            outlined
            hide-details
          />
          <v-text-field
            v-model="scriptId"
            label="Script ID"
            data-test="id"
            class="shrink ml-2 script-state"
            style="width: 100px"
            dense
            outlined
            readonly
            hide-details
          />
          <v-text-field
            v-model="state"
            label="Script State"
            data-test="state"
            class="shrink ml-2 script-state"
            style="width: 120px"
            dense
            outlined
            readonly
            hide-details
          />
          <v-progress-circular
            v-if="state === 'Connecting...'"
            :size="40"
            class="ml-2 mr-2"
            indeterminate
            color="primary"
          />
          <div v-else style="width: 40px; height: 40px" class="ml-2 mr-2"></div>

          <!-- Disable the Start button when Suite Runner controls are showing -->
          <v-spacer />
          <div v-if="startOrGoButton === 'Start'">
            <v-btn
              @click="startHandler"
              class="mx-1"
              color="primary"
              data-test="start-button"
              :disabled="startOrGoDisabled"
            >
              <span> Start </span>
            </v-btn>
            <v-tooltip bottom>
              <template v-slot:activator="{ on, attrs }">
                <v-btn
                  v-on="on"
                  v-bind="attrs"
                  @click="scriptEnvironment.show = !scriptEnvironment.show"
                  class="mx-1"
                  data-test="env-button"
                  :color="environmentIconColor"
                  :disabled="envDisabled"
                >
                  <v-icon> {{ environmentIcon }} </v-icon>
                </v-btn>
              </template>
              <span>Script Environment</span>
            </v-tooltip>
          </div>
          <div v-else>
            <v-btn
              @click="go"
              color="primary"
              class="mr-2"
              :disabled="startOrGoDisabled"
              data-test="go-button"
            >
              Go
            </v-btn>
            <v-btn
              color="primary"
              @click="pauseOrRetry"
              class="mr-2"
              :disabled="pauseOrRetryDisabled"
              data-test="pause-retry-button"
            >
              {{ pauseOrRetryButton }}
            </v-btn>

            <v-btn
              color="primary"
              @click="stop"
              data-test="stop-button"
              :disabled="stopDisabled"
            >
              Stop
            </v-btn>
          </div>
        </v-row>
      </div>
    </v-card>
    <!-- Create Multipane container to support resizing.
         NOTE: We listen to paneResize event and call editor.resize() to prevent weird sizing issues,
         The event must be paneResize and not pane-resize -->
    <multipane
      class="horizontal-panes"
      layout="horizontal"
      @paneResize="editor.resize()"
    >
      <div class="editorbox pane">
        <v-snackbar
          v-model="showSave"
          absolute
          top
          right
          :timeout="-1"
          class="saving"
        >
          Saving...
        </v-snackbar>
        <pre
          ref="editor"
          class="editor"
          @contextmenu.prevent="showExecuteSelectionMenu"
        ></pre>
        <v-menu
          v-model="executeSelectionMenu"
          :position-x="menuX"
          :position-y="menuY"
          absolute
          offset-y
        >
          <v-list>
            <v-list-item
              v-for="item in executeSelectionMenuItems"
              link
              :key="item.label"
              :disabled="scriptId"
            >
              <v-list-item-title @click="item.command">
                {{ item.label }}
              </v-list-item-title>
            </v-list-item>
          </v-list>
        </v-menu>
      </div>
      <multipane-resizer><hr /></multipane-resizer>
      <div id="messages" class="mt-2 pane" ref="messagesDiv">
        <div id="debug" class="pa-0" v-if="showDebug">
          <v-row no-gutters>
            <v-btn
              color="primary"
              @click="step"
              style="width: 100px"
              class="mr-4"
              :disabled="!scriptId"
              data-test="step-button"
            >
              Step
              <v-icon right> mdi-step-forward </v-icon>
            </v-btn>
            <v-text-field
              class="mb-2"
              outlined
              dense
              hide-details
              label="Debug"
              v-model="debug"
              @keydown="debugKeydown"
              data-test="debug-text"
            />
          </v-row>
        </div>
        <script-log-messages v-model="messages" @sort="messageSortOrder" />
      </div>
    </multipane>
    <!--- MENUS --->
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
      @response="fileDialogCallback"
    />
    <information-dialog
      v-if="information.show"
      v-model="information.show"
      :title="information.title"
      :text="information.text"
    />
    <event-list-dialog
      v-if="inputMetadata.show"
      v-model="inputMetadata.show"
      :events="inputMetadata.events"
      :utc="false"
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
    <v-bottom-sheet v-model="showScripts">
      <v-sheet class="pb-11 pt-5 px-5">
        <running-scripts
          v-if="showScripts"
          :connect-in-new-tab="!!fileModified"
          @close="
            () => {
              showScripts = false
            }
          "
        />
      </v-sheet>
    </v-bottom-sheet>
  </div>
</template>

<script>
import axios from 'axios'
import Cable from '@openc3/tool-common/src/services/cable.js'
import Api from '@openc3/tool-common/src/services/api'
import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-ruby'
import 'ace-builds/src-min-noconflict/mode-python'
import 'ace-builds/src-min-noconflict/theme-twilight'
import 'ace-builds/src-min-noconflict/ext-language_tools'
import 'ace-builds/src-min-noconflict/ext-searchbox'
import { format } from 'date-fns'
import { Multipane, MultipaneResizer } from 'vue-multipane'
import FileOpenSaveDialog from '@openc3/tool-common/src/components/FileOpenSaveDialog'
import EnvironmentDialog from '@openc3/tool-common/src/components/EnvironmentDialog'
import SimpleTextDialog from '@openc3/tool-common/src/components/SimpleTextDialog'
import TopBar from '@openc3/tool-common/src/components/TopBar'
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'
import { fileIcon } from '@openc3/tool-common/src/tools/base/util/fileIcon'

import AskDialog from '@/tools/ScriptRunner/Dialogs/AskDialog'
import FileDialog from '@/tools/ScriptRunner/Dialogs/FileDialog'
import InformationDialog from '@/tools/ScriptRunner/Dialogs/InformationDialog'
import EventListDialog from '@openc3/tool-common/src/tools/calendar/Dialogs/EventListDialog'
import OverridesDialog from '@/tools/ScriptRunner/Dialogs/OverridesDialog'
import PromptDialog from '@/tools/ScriptRunner/Dialogs/PromptDialog'
import ResultsDialog from '@/tools/ScriptRunner/Dialogs/ResultsDialog'
import ScriptEnvironmentDialog from '@/tools/ScriptRunner/Dialogs/ScriptEnvironmentDialog'
import SuiteRunner from '@/tools/ScriptRunner/SuiteRunner'
import ScriptLogMessages from '@/tools/ScriptRunner/ScriptLogMessages'
import Openc3Screen from '@openc3/tool-common/src/components/Openc3Screen'
import {
  CmdCompleter,
  TlmCompleter,
  MnemonicChecker,
} from '@/tools/ScriptRunner/autocomplete'
import { SleepAnnotator } from '@/tools/ScriptRunner/annotations'
import RunningScripts from './RunningScripts.vue'

// Matches target_file.rb TEMP_FOLDER
const TEMP_FOLDER = '__TEMP__'
const NEW_FILENAME = '<Untitled>'
const START = 'Start'
const GO = 'Go'
const PAUSE = 'Pause'
const RETRY = 'Retry'

export default {
  components: {
    FileOpenSaveDialog,
    Openc3Screen,
    EnvironmentDialog,
    Multipane,
    MultipaneResizer,
    TopBar,
    AskDialog,
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
    ScriptLogMessages,
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
      state: null,
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
      debugHistory: [],
      debugHistoryIndex: 0,
      showDisconnect: false,
      files: {},
      breakpoints: {},
      filename: NEW_FILENAME,
      saveAllowed: true,
      tempFilename: null,
      fileModified: '',
      fileOpen: false,
      lockedBy: null,
      showReadOnlyToast: false,
      showSaveAs: false,
      areYouSure: false,
      subscription: null,
      cable: null,
      fatal: false,
      updateInterval: null,
      receivedEvents: [],
      messages: [],
      messagesNewestOnTop: true,
      maxArrayLength: 200,
      Range: ace.require('ace/range').Range,
      ask: {
        show: false,
        question: '',
        default: null,
        password: false,
        answerRequired: true,
        callback: () => {},
      },
      file: {
        show: false,
        message: '',
        directory: null,
        filter: '*',
        multiple: false,
        callback: () => {},
      },
      prompt: {
        show: false,
        title: '',
        subtitle: '',
        message: '',
        details: '',
        buttons: null,
        layout: 'horizontal',
        callback: () => {},
      },
      information: {
        show: false,
        title: '',
        text: [],
      },
      inputMetadata: {
        show: false,
        events: [],
        callback: () => {},
      },
      results: {
        show: false,
        text: '',
      },
      scriptEnvironment: {
        show: false,
        env: [],
      },
      showSuiteError: false,
      suiteError: '',
      executeSelectionMenu: false,
      menuX: 0,
      menuY: 0,
      mnemonicChecker: new MnemonicChecker(),
      showScripts: false,
      showOverrides: false,
      activePromptId: '',
      api: null,
      screens: [],
      screenKeywords: null,
      idCounter: 0,
      updateCounter: 0,
      recent: [],
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
    environmentIcon: function () {
      return this.scriptEnvironment.env.length > 0
        ? 'mdi-bookmark'
        : 'mdi-bookmark-outline'
    },
    environmentIconColor: function () {
      return this.scriptEnvironment.env.length > 0 ? 'primary' : ''
    },
    readOnly: function () {
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
              disabled: this.scriptId,
              command: () => {
                this.newFile()
              },
            },
            {
              label: 'New Test Suite',
              icon: 'mdi-file-plus',
              disabled: this.scriptId,
              subMenu: [
                {
                  label: 'Ruby',
                  icon: 'mdi-language-ruby',
                  command: () => {
                    this.newRubyTestSuite()
                  },
                },
                {
                  label: 'Python',
                  icon: 'mdi-language-python',
                  command: () => {
                    this.newPythonTestSuite()
                  },
                },
              ],
            },
            {
              label: 'Open File',
              icon: 'mdi-folder-open',
              disabled: this.scriptId,
              command: () => {
                this.openFile()
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
              disabled: this.scriptId,
              command: () => {
                this.saveFile()
              },
            },
            {
              label: 'Save As...',
              icon: 'mdi-content-save',
              disabled: this.scriptId,
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
              disabled: this.scriptId,
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
    executeSelectionMenuItems: function () {
      return [
        {
          label: 'Execute selection',
          command: this.executeSelection,
        },
        {
          label: 'Run from here',
          command: this.runFromCursor,
        },
        {
          label: 'Clear local breakpoints',
          command: this.clearBreakpoints,
        },
      ]
    },
  },
  watch: {
    readOnly: function (val) {
      this.showReadOnlyToast = val
      if (!this.suiteRunner) {
        this.startOrGoDisabled = val
      }
      this.editor.setReadOnly(val)
    },
    fullFilename: function (filename) {
      this.filenameSelect = filename
      if (filename === NEW_FILENAME) {
        localStorage.removeItem('script_runner__filename')
      } else {
        localStorage['script_runner__filename'] = filename
      }
    },
  },
  created: function () {
    // Ensure Offline Access Is Setup For the Current User
    this.api = new OpenC3Api()
    this.api.ensure_offline_access()

    // Make NEW_FILENAME available to the template
    this.NEW_FILENAME = NEW_FILENAME
    window.onbeforeunload = this.unlockFile

    Api.get('/openc3-api/autocomplete/keywords/screen').then((response) => {
      this.screenKeywords = response.data
    })
  },
  mounted: async function () {
    this.editor = ace.edit(this.$refs.editor)
    this.editor.setTheme('ace/theme/twilight')
    // Public apis in api_shared but not in OpenC3Api
    const api_shared = [
      'check',
      'check_raw',
      'check_formatted',
      'check_with_units',
      'check_exception',
      'check_tolerance',
      'check_expression',
      'wait',
      'wait_tolerance',
      'wait_expression',
      'wait_check',
      'wait_check_tolerance',
      'wait_check_expression',
      'wait_packet',
      'wait_check_packet',
      'disable_instrumentation',
      'set_line_delay',
      'get_line_delay',
      'set_max_output',
      'get_max_output',
    ]
    const openC3RubyMode = this.buildOpenC3RubyMode(api_shared)
    const openC3PythonMode = this.buildOpenC3PythonMode(api_shared)
    this.openC3RubyMode = new openC3RubyMode()
    this.openC3PythonMode = new openC3PythonMode()
    this.editor.session.setMode(this.openC3RubyMode)
    this.editor.session.setTabSize(2)
    this.editor.session.setUseWrapMode(true)
    this.editor.$blockScrolling = Infinity
    this.editor.setOption('enableBasicAutocompletion', true)
    this.editor.setOption('enableLiveAutocompletion', true)
    this.editor.completers = [new CmdCompleter(), new TlmCompleter()]
    this.editor.setHighlightActiveLine(false)
    this.editor.focus()
    this.editor.on('guttermousedown', this.toggleBreakpoint)
    // We listen to tokenizerUpdate rather than change because this
    // is the background process that updates as changes are processed
    // while change fires immediately before the UndoManager is updated.
    this.editor.session.on('tokenizerUpdate', this.onChange)

    const sleepAnnotator = new SleepAnnotator(this.editor)
    this.editor.session.on('change', ($event, session) => {
      sleepAnnotator.annotate($event, session)
      this.updateBreakpoints($event, session)
    })

    window.addEventListener('keydown', this.keydown)
    this.cable = new Cable('/script-api/cable')

    if (localStorage['script_runner__recent']) {
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
    if (this.$route.query?.file) {
      this.filename = this.$route.query.file
      await this.reloadFile()
    } else if (this.$route.params?.id) {
      await this.tryLoadRunningScript(this.$route.params.id)
    } else {
      if (localStorage['script_runner__filename']) {
        this.filename = localStorage['script_runner__filename']
        await this.reloadFile(false)
      }
    }
    // TODO: Potentially still bad interactions with autoSave
    // see https://github.com/OpenC3/cosmos/issues/915
    // this.autoSaveInterval = setInterval(async () => {
    //   // Only save if not-running, modified, and visible (e.g. not open in another tab)
    //   if (
    //     !this.scriptId &&
    //     this.fileModified.length > 0 &&
    //     document.visibilityState === 'visible'
    //   ) {
    //     await this.saveFile('auto')
    //   }
    // }, 60000) // Save every minute

    this.updateInterval = setInterval(async () => {
      this.processReceived()
    }, 100) // Every 100ms
  },
  beforeDestroy() {
    this.editor.destroy()
    this.editor.container.remove()
  },
  destroyed() {
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
  beforeRouteUpdate: function (to, from, next) {
    if (to.params.id) {
      this.tryLoadRunningScript(to.params.id).then(next)
    } else {
      next()
    }
  },
  methods: {
    showMetadata() {
      Api.get('/openc3-api/metadata').then((response) => {
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
      })
    },
    buildOpenC3RubyMode(api_shared) {
      var oop = ace.require('ace/lib/oop')
      var RubyHighlightRules = ace.require(
        'ace/mode/ruby_highlight_rules',
      ).RubyHighlightRules

      let apis = Object.getOwnPropertyNames(OpenC3Api.prototype)
        .filter((a) => a !== 'constructor')
        .filter((a) => a !== 'exec')
        .concat(api_shared)
      let regex = new RegExp(`(\\b${apis.join('\\b|\\b')}\\b)`)
      var OpenC3HighlightRules = function () {
        RubyHighlightRules.call(this)
        // add openc3 rules to the ruby rules
        for (var rule in this.$rules) {
          this.$rules[rule].unshift({
            regex: regex,
            token: 'support.function',
          })
        }
      }
      oop.inherits(OpenC3HighlightRules, RubyHighlightRules)

      var MatchingBraceOutdent = ace.require(
        'ace/mode/matching_brace_outdent',
      ).MatchingBraceOutdent
      var CstyleBehaviour = ace.require(
        'ace/mode/behaviour/cstyle',
      ).CstyleBehaviour
      var FoldMode = ace.require('ace/mode/folding/ruby').FoldMode
      var Mode = function () {
        this.HighlightRules = OpenC3HighlightRules
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
    buildOpenC3PythonMode(api_shared) {
      var oop = ace.require('ace/lib/oop')
      var PythonHighlightRules = ace.require(
        'ace/mode/python_highlight_rules',
      ).PythonHighlightRules

      let apis = Object.getOwnPropertyNames(OpenC3Api.prototype)
        .filter((a) => a !== 'constructor')
        .filter((a) => a !== 'exec')
        .concat(api_shared)
      let regex = new RegExp(`(\\b${apis.join('\\b|\\b')}\\b)`)
      var OpenC3HighlightRules = function () {
        PythonHighlightRules.call(this)
        // add openc3 rules to the python rules
        for (var rule in this.$rules) {
          this.$rules[rule].unshift({
            regex: regex,
            token: 'support.function',
          })
        }
      }
      oop.inherits(OpenC3HighlightRules, PythonHighlightRules)

      var MatchingBraceOutdent = ace.require(
        'ace/mode/matching_brace_outdent',
      ).MatchingBraceOutdent
      var CstyleBehaviour = ace.require(
        'ace/mode/behaviour/cstyle',
      ).CstyleBehaviour
      var FoldMode = ace.require('ace/mode/folding/pythonic').FoldMode
      var Mode = function () {
        this.HighlightRules = OpenC3HighlightRules
        this.$outdent = new MatchingBraceOutdent()
        this.$behaviour = new CstyleBehaviour()
        this.foldingRules = new FoldMode()
        this.indentKeywords = this.foldingRules.indentKeywords
      }
      var PythonMode = ace.require('ace/mode/python').Mode
      oop.inherits(Mode, PythonMode)
      ;(function () {
        this.$id = 'ace/mode/openc3'
      }).call(Mode.prototype)
      return Mode
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
      this.editor.setValue(this.files[filename].content)
      this.restoreBreakpoints(filename)
      this.editor.clearSelection()
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
    tryLoadRunningScript: function (id) {
      return Api.get('/script-api/running-script').then((response) => {
        const loadRunningScript = response.data.find(
          (s) => `${s.id}` === `${id}`,
        )
        if (loadRunningScript) {
          this.filename = loadRunningScript.name
          this.tryLoadSuites()
          this.initScriptStart()
          this.scriptStart(loadRunningScript.id)
        } else {
          this.$notify.caution({
            title: `Running Script ${id} not found`,
            body: 'Check the Completed Scripts below ...',
          })
          this.showScripts = true
        }
      })
    },
    tryLoadSuites: function () {
      Api.get(`/script-api/scripts/${this.filename}`).then((response) => {
        if (response.data.suites) {
          this.startOrGoDisabled = true
          this.suiteRunner = true
          this.suiteMap = JSON.parse(response.data.suites)
        }
        if (response.data.error) {
          this.suiteError = response.data.error
          this.showSuiteError = true
        }
        // Disable suite buttons if we didn't successfully parse the suite
        this.disableSuiteButtons = response.data.success == false
      })
    },
    showExecuteSelectionMenu: function ($event) {
      this.menuX = $event.pageX
      this.menuY = $event.pageY
      this.executeSelectionMenu = true
    },
    runFromCursor: function () {
      const start = this.editor.getCursorPosition().row
      const text = this.editor.session.doc
        .getLines(start, this.editor.session.doc.getLength())
        .join('\n')
      const breakpoints = this.getBreakpointRows()
        .filter((row) => row >= start)
        .map((row) => row - start)
      this.executeText(text, breakpoints)
    },
    executeSelection: function () {
      const text = this.editor.getSelectedText()
      const range = this.editor.getSelectionRange()
      const breakpoints = this.getBreakpointRows()
        .filter((row) => row <= range.end.row && row >= range.start.row)
        .map((row) => row - range.start.row)
      this.executeText(text, breakpoints)
    },
    async executeText(text, breakpoints = []) {
      // Create a new temp script and open in new tab
      const selectionTempFilename =
        TEMP_FOLDER +
        '/' +
        format(Date.now(), 'yyyy_MM_dd_HH_mm_ss_SSS') +
        '_temp.rb'
      await Api.post(`/script-api/scripts/${selectionTempFilename}`, {
        data: {
          text,
          breakpoints,
        },
      })
        .then((response) => {
          return Api.post(`/script-api/scripts/${selectionTempFilename}/run`, {
            data: {
              environment: this.scriptEnvironment.env,
            },
          })
        })
        .then((response) => {
          window.open(`/tools/scriptrunner/${response.data}`)
        })
    },
    clearBreakpoints: function () {
      this.editor.session.clearBreakpoints()
    },
    toggleBreakpoint: function ($event) {
      // Don't allow setting breakpoints while running
      if (!this.scriptId) {
        const row = $event.getDocumentPosition().row
        if ($event.editor.session.getBreakpoints(row, 0)[row]) {
          $event.editor.session.clearBreakpoint(row)
        } else {
          $event.editor.session.setBreakpoint(row)
        }
      }
    },
    updateBreakpoints: function ($event, session) {
      if ($event.lines.length <= 1) {
        return
      }
      const rowsToUpdate = this.getBreakpointRows(session).filter(
        (row) =>
          ($event.start.column === 0 && row === $event.start.row) ||
          row > $event.start.row,
      )
      let rowsToDelete = []
      let offset = 0
      switch ($event.action) {
        case 'insert':
          offset = $event.lines.length - 1
          rowsToUpdate.reverse() // shift the lower ones down out of the way first
          break
        case 'remove':
          offset = -$event.lines.length + 1
          rowsToDelete = [...Array($event.lines.length).keys()].map(
            (row) => row + $event.start.row,
          )
          break
      }
      rowsToUpdate.forEach((row) => {
        session.clearBreakpoint(row)
        if (!rowsToDelete.includes(row)) {
          session.setBreakpoint(row + offset)
        }
      })
    },
    getBreakpointRows: function (session = this.editor.session) {
      return session
        .getBreakpoints()
        .map((breakpoint, row) => breakpoint && row) // [empty, 'ace_breakpoint', 'ace_breakpoint', empty] -> [empty, 1, 2, empty]
        .filter(Number.isInteger) // [empty, 1, 2, empty] -> [1, 2]
    },
    restoreBreakpoints: function (filename) {
      this.clearBreakpoints()
      this.breakpoints[filename]?.forEach((breakpoint) => {
        this.editor.session.setBreakpoint(breakpoint)
      })
    },
    deleteAllBreakpoints: function () {
      this.$dialog
        .confirm('Permanently delete all breakpoints for ALL scripts?', {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          return Api.delete('/script-api/breakpoints/delete/all')
        })
        .then((response) => {
          this.clearBreakpoints()
        })
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
      if (this.scriptId || this.editor.getReadOnly() === true) {
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
    onChange(event) {
      // Don't track changes when we're running or read-only (locked)
      if (this.scriptId || this.editor.getReadOnly() === true) {
        return
      }
      if (this.editor.session.getUndoManager().canUndo()) {
        this.fileModified = '*'
      } else {
        this.fileModified = ''
      }
    },
    checkMnemonics: function () {
      this.mnemonicChecker
        .checkText(this.editor.getValue())
        .then(({ skipped, problems }) => {
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
        })
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
    scriptStart(id) {
      this.scriptId = id
      this.cable
        .createSubscription(
          'RunningScriptChannel',
          window.openc3Scope,
          {
            received: (data) => this.received(data),
          },
          {
            id: this.scriptId,
          },
        )
        .then((subscription) => {
          this.subscription = subscription
        })
    },
    async scriptComplete() {
      // Ensure stopped, if the script has an error we don't get the server stopped message
      this.state = 'stopped'
      this.fatal = false
      this.scriptId = null // No current scriptId
      this.currentFilename = null // No current file running
      this.files = {} // Clear the file cache
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
      this.editor.setReadOnly(false)

      // Lastly enable the buttons so another script can start
      this.disableSuiteButtons = false
      this.startOrGoButton = START
      this.pauseOrRetryButton = PAUSE
      // Disable start if suiteRunner
      this.startOrGoDisabled = this.suiteRunner
      this.envDisabled = false
      this.pauseOrRetryDisabled = true
      this.stopDisabled = true
    },
    environmentHandler: function (event) {
      this.scriptEnvironment.env = event
    },
    startHandler: function () {
      this.start()
    },
    async start(event, suiteRunner = null) {
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
      let data = {
        environment: this.scriptEnvironment.env,
      }
      if (suiteRunner) {
        data['suiteRunner'] = event
      }
      Api.post(url, { data })
        .then((response) => {
          this.scriptStart(response.data)
        })
        .catch((error) => {
          this.scriptComplete()
        })
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
      // We previously encountered a fatal error so remove the marker
      // and cleanup by calling scriptComplete() because the script
      // is already stopped in the backend
      if (this.fatal) {
        this.removeAllMarkers()
        this.scriptComplete()
      } else {
        Api.post(`/script-api/running-script/${this.scriptId}/stop`)
      }
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
          this.editor.setValue(this.files[data.filename].content)
          this.restoreBreakpoints(data.filename)
          this.editor.clearSelection()
        }
      }
      this.state = data.state
      const markers = this.editor.session.getMarkers()
      switch (this.state) {
        case 'running':
          this.startOrGoDisabled = false
          this.pauseOrRetryDisabled = false
          this.stopDisabled = false
          this.pauseOrRetryButton = PAUSE

          this.removeAllMarkers()
          this.editor.session.addMarker(
            new this.Range(data.line_no - 1, 0, data.line_no - 1, 1),
            'runningMarker',
            'fullLine',
          )
          this.editor.gotoLine(data.line_no)
          this.files[data.filename].lineNo = data.line_no
          break
        case 'fatal':
          this.fatal = true
        // Deliberate fall through (no break)
        case 'error':
          this.pauseOrRetryButton = RETRY
        // Deliberate fall through (no break)
        case 'breakpoint':
        case 'waiting':
        case 'paused':
          if (this.state == 'fatal') {
            this.startOrGoDisabled = true
            this.pauseOrRetryDisabled = true
          } else {
            this.startOrGoDisabled = false
            this.pauseOrRetryDisabled = false
          }
          this.stopDisabled = false
          let existing = Object.keys(markers).filter(
            (key) => markers[key].clazz === `${this.state}Marker`,
          )
          if (existing.length === 0) {
            this.removeAllMarkers()
            let line = data.line_no > 0 ? data.line_no : 1
            this.editor.session.addMarker(
              new this.Range(line - 1, 0, line - 1, 1),
              `${this.state}Marker`,
              'fullLine',
            )
            this.editor.gotoLine(line)
            // Fatal errors don't always have a filename set
            if (data.filename) {
              this.files[data.filename].lineNo = line
            }
          }
          break
        default:
          break
      }
    },
    processReceived() {
      let count = 0
      for (let data of this.receivedEvents) {
        count += 1
        // eslint-disable-next-line
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
            // data.line can consist of multiple lines split by newlines
            // thus we split and only output if the content is not empty
            for (const line of data.line.split('\n')) {
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
            this.handleScript(data)
            break
          case 'report':
            this.results.text = data.report
            this.results.show = true
            break
          case 'complete':
            // Don't complete on fatal because we just sit there on the fatal line
            if (!this.fatal) {
              this.removeAllMarkers()
              this.scriptComplete()
            }
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
            this.$set(definition, 'target', data.target_name)
            this.$set(definition, 'screen', data.screen_name)
            this.$set(definition, 'definition', data.definition)
            if (data.x) {
              this.$set(definition, 'left', data.x)
            } else {
              this.$set(definition, 'left', 0)
            }
            if (data.y) {
              this.$set(definition, 'top', data.y)
            } else {
              this.$set(definition, 'top', 0)
            }
            this.$set(definition, 'count', this.updateCounter++)
            if (!found) {
              this.$set(definition, 'id', this.idCounter++)
              this.$set(this.screens, this.screens.length, definition)
            } else {
              this.$set(this.screens, index, definition)
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
            // Make a link and then 'click' on it to start the download
            const link = document.createElement('a')
            link.href = window.location.origin + data.url
            link.setAttribute('download', data.filename)
            link.click()
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
    promptDialogCallback(value) {
      this.prompt.show = false
      Api.post(`/script-api/running-script/${this.scriptId}/prompt`, {
        data: {
          method: this.prompt.method,
          answer: value,
          prompt_id: this.activePromptId,
          multiple: this.prompt.multiple,
        },
      })
    },
    handleScript(data) {
      if (data.prompt_complete) {
        this.activePromptId = ''
        this.prompt.show = false
        this.ask.show = false
        return
      }
      this.activePromptId = data.prompt_id
      this.prompt.method = data.method // Set it here since all prompts use this
      this.prompt.layout = 'horizontal' // Reset the layout since most are horizontal
      this.prompt.title = 'Prompt'
      this.prompt.subtitle = ''
      this.prompt.details = ''
      this.prompt.buttons = []
      this.prompt.multiple = null
      switch (data.method) {
        case 'ask':
        case 'ask_string':
          // Reset values since this dialog can be re-used
          this.ask.default = null
          this.ask.answerRequired = true
          this.ask.password = false
          this.ask.question = data.args[0]
          // If the second parameter is not true or false it indicates a default value
          if (data.args[1] && data.args[1] !== true && data.args[1] !== false) {
            this.ask.default = data.args[1].toString()
          } else if (data.args[1] === true) {
            // If the second parameter is true it means no value is required to be entered
            this.ask.answerRequired = false
          }
          // The third parameter indicates a password textfield
          if (data.args[2] === true) {
            this.ask.password = true
          }
          this.ask.callback = (value) => {
            this.ask.show = false // Close the dialog
            if (this.ask.password) {
              Api.post(`/script-api/running-script/${this.scriptId}/prompt`, {
                data: {
                  method: data.method,
                  password: value, // Using password as a key automatically filters it from rails logs
                  prompt_id: this.activePromptId,
                },
              })
            } else {
              Api.post(`/script-api/running-script/${this.scriptId}/prompt`, {
                data: {
                  method: data.method,
                  answer: value,
                  prompt_id: this.activePromptId,
                },
              })
            }
          }
          this.ask.show = true // Display the dialog
          break
        case 'prompt_for_hazardous':
          this.prompt.title = 'Hazardous Command'
          this.prompt.message = `Warning: Command ${data.args[0]} ${data.args[1]} is Hazardous. `
          if (data.args[2]) {
            this.prompt.message += data.args[2] + ' '
          }
          this.prompt.message += 'Send?'
          this.prompt.buttons = [{ text: 'Send', value: 'Send' }]
          this.prompt.callback = this.promptDialogCallback
          this.prompt.show = true
          break
        case 'prompt':
          if (data.kwargs && data.kwargs.informative) {
            this.prompt.subtitle = data.kwargs.informative
          }
          if (data.kwargs && data.kwargs.details) {
            this.prompt.details = data.kwargs.details
          }
          this.prompt.message = data.args[0]
          this.prompt.buttons = [{ text: 'Ok', value: 'Ok' }]
          this.prompt.callback = this.promptDialogCallback
          this.prompt.show = true
          break
        case 'combo_box':
          if (data.kwargs && data.kwargs.informative) {
            this.prompt.subtitle = data.kwargs.informative
          }
          if (data.kwargs && data.kwargs.details) {
            this.prompt.details = data.kwargs.details
          }
          if (data.kwargs && data.kwargs.multiple) {
            this.prompt.multiple = true
          }
          this.prompt.message = data.args[0]
          data.args.slice(1).forEach((v) => {
            this.prompt.buttons.push({ text: v, value: v })
          })
          this.prompt.layout = 'combo'
          this.prompt.callback = this.promptDialogCallback
          this.prompt.show = true
          break
        case 'message_box':
        case 'vertical_message_box':
          if (data.kwargs && data.kwargs.informative) {
            this.prompt.subtitle = data.kwargs.informative
          }
          if (data.kwargs && data.kwargs.details) {
            this.prompt.details = data.kwargs.details
          }
          this.prompt.message = data.args[0]
          data.args.slice(1).forEach((v) => {
            this.prompt.buttons.push({ text: v, value: v })
          })
          if (data.method.includes('vertical')) {
            this.prompt.layout = 'vertical'
          }
          this.prompt.callback = this.promptDialogCallback
          this.prompt.show = true
          break
        case 'backtrace':
          this.information.title = 'Call Stack'
          this.information.text = data.args
          this.information.show = true
          break
        case 'metadata_input':
          this.inputMetadata.callback = (value) => {
            this.inputMetadata.show = false
            Api.post(`/script-api/running-script/${this.scriptId}/prompt`, {
              data: {
                method: data.method,
                answer: value,
                prompt_id: this.activePromptId,
              },
            })
          }
          this.showMetadata()
          break
        case 'open_file_dialog':
        case 'open_files_dialog':
          this.file.title = data.args[0]
          this.file.message = data.args[1]
          if (data.kwargs && data.kwargs.filter) {
            this.file.filter = data.kwargs.filter
          }
          if (data.method == 'open_files_dialog') {
            this.file.multiple = true
          }
          this.file.show = true
          break
        default:
          /* console.log(
            'Unknown script method:' + data.method + ' with args:' + data.args
          ) */
          break
      }
    },
    async fileDialogCallback(files) {
      this.file.show = false // Close the dialog
      // Set fileNames to 'Cancel' in case they cancelled
      // otherwise we will populate it with the file names they selected
      let fileNames = 'Cancel'
      if (files != 'Cancel') {
        fileNames = []
        await files.forEach(async (file) => {
          fileNames.push(file.name)
          // Reassign data to presignedRequest for readability
          const { data: presignedRequest } = await Api.get(
            `/openc3-api/storage/upload/${encodeURIComponent(
              `${window.openc3Scope}/tmp/${file.name}`,
            )}?bucket=OPENC3_CONFIG_BUCKET`,
          )
          // This pushes the file into storage by using the fields in the presignedRequest
          // See storage_controller.rb get_presigned_request()
          const response = await axios({
            ...presignedRequest,
            data: file,
          })
        })
      }
      await Api.post(`/script-api/running-script/${this.scriptId}/prompt`, {
        data: {
          method: this.file.multiple ? 'open_files_dialog' : 'open_file_dialog',
          answer: fileNames,
          prompt_id: this.activePromptId,
        },
      })
    },
    setError(event) {
      this.alertType = 'error'
      this.alertText = `Error: ${event}`
      this.showAlert = true
    },
    // ScriptRunner File menu actions
    newFile() {
      this.unlockFile()
      this.filename = NEW_FILENAME
      this.currentFilename = null
      this.tempFilename = null
      this.files = {} // Clear the cached file list
      this.editor.session.setValue('')
      this.saveAllowed = true
      this.fileModified = ''
      this.suiteRunner = false
      this.startOrGoDisabled = false
      this.envDisabled = false
      this.$router
        .replace({
          name: 'ScriptRunner',
        })
        // catch the error in case we route to where we already are
        .catch((err) => {})
      document.title = 'Script Runner'
    },
    async newRubyTestSuite() {
      this.newFile()
      this.editor.session.setValue(`require 'openc3/script/suite.rb'

# Group class name should indicate what the scripts are testing
class Power < OpenC3::Group
  # Methods beginning with script_ are added to Script dropdown
  def script_power_on
    # Using OpenC3::Group.puts adds the output to the Test Report
    # This can be useful for requirements verification, QA notes, etc
    OpenC3::Group.puts "Verifying requirement SR-1"
    configure()
  end

  # Other methods are not added to Script dropdown
  def configure
  end

  def setup
    # Run when Group Setup button is pressed
    # Run before all scripts when Group Start is pressed
  end

  def teardown
    # Run when Group Teardown button is pressed
    # Run after all scripts when Group Start is pressed
  end
end

class TestSuite < OpenC3::Suite
  def initialize
    add_group('Power')
  end
  def setup
    # Run when Suite Setup button is pressed
    # Run before all groups when Suite Start is pressed
  end
  def teardown
    # Run when Suite Teardown button is pressed
    # Run after all groups when Suite Start is pressed
  end
end
`)
      await this.saveFile('auto')
    },
    async newPythonTestSuite() {
      this.newFile()
      this.editor.session.setValue(`from openc3.script.suite import Suite, Group

# Group class name should indicate what the scripts are testing
class Power(Group):
  # Methods beginning with script_ are added to Script dropdown
  def script_power_on(self):
      # Using Group.print adds the output to the Test Report
      # This can be useful for requirements verification, QA notes, etc
      Group.print("Verifying requirement SR-1")
      self.configure()

  # Other methods are not added to Script dropdown
  def configure(self):
      pass

  def setup(self):
      # Run when Group Setup button is pressed
      # Run before all scripts when Group Start is pressed
      pass

  def teardown(self):
      # Run when Group Teardown button is pressed
      # Run after all scripts when Group Start is pressed
      pass

class TestSuite(Suite):
  def __init__(self):
      self.add_group(Power)

  def setup(self):
      # Run when Suite Setup button is pressed
      # Run before all groups when Suite Start is pressed
      pass

  def teardown(self):
      # Run when Suite Teardown button is pressed
      # Run after all groups when Suite Start is pressed
      pass
`)
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
          this.filename = event.label
          await this.reloadFile()
        },
      })
      if (this.recent.length > 8) {
        this.recent.pop()
      }
      // This only stringifies the label and icon ... not the command
      localStorage['script_runner__recent'] = JSON.stringify(this.recent)
    },
    removeFromRecent(filename) {
      this.recent = this.recent.filter((entry) => entry.label !== filename)
      localStorage['script_runner__recent'] = JSON.stringify(this.recent)
      if (localStorage['script_runner__filename'] === filename) {
        localStorage.removeItem('script_runner__filename')
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
      await Api.get(`/script-api/scripts/${this.filename}`, {
        headers: {
          Accept: 'application/json',
          'Ignore-Errors': '404',
        },
      })
        .then((response) => {
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
        })
        .catch((error) => {
          if (showError === true) {
            this.$notify.caution({
              title: 'File Open Error',
              body: `Failed to open ${this.filename} due to ${error}`,
            })
          }
          this.removeFromRecent(this.filename)
          this.newFile() // Reset the GUI
        })
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

      if (this.filename.split('.').pop() === 'py') {
        this.editor.session.setMode(this.openC3PythonMode)
      } else {
        this.editor.session.setMode(this.openC3RubyMode)
      }
      this.currentFilename = null
      this.editor.session.setValue(file.contents)
      this.breakpoints[filename] = breakpoints
      this.restoreBreakpoints(filename)
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
    },
    clearTemp() {
      this.recent = this.recent.filter(
        (entry) => !entry.label.includes('__TEMP__'),
      )
      localStorage['script_runner__recent'] = JSON.stringify(this.recent)
    },
    detectLanguage() {
      let rubyRegex1 = new RegExp('^\\s*(require|load|puts) ')
      let pythonRegex1 = new RegExp('^\\s*(import|from) ')
      let rubyRegex2 = new RegExp('^\\s*end\\s*$')
      let pythonRegex2 = new RegExp(
        '^\\s*(if|def|while|else|elif|class).*:\\s*$',
      )
      let pythonRegex3 = new RegExp('\\(f"') // f strings
      let text = this.editor.getValue()
      let lines = text.split('\n')
      for (let line of lines) {
        if (line.match(rubyRegex1)) {
          return 'ruby'
        }
        if (line.match(pythonRegex1)) {
          return 'python'
        }
        if (line.match(rubyRegex2)) {
          return 'ruby'
        }
        if (line.match(pythonRegex2)) {
          return 'python'
        }
        if (line.match(pythonRegex3)) {
          return 'python'
        }
      }
      return 'unknown' // otherwise unknown
    },
    // saveFile takes a type to indicate if it was called by the Menu
    // or automatically by 'Start' (to ensure a consistent backend file) or autoSave
    async saveFile(type = 'menu') {
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
              let language = this.detectLanguage()
              if (
                language === 'ruby' ||
                (type !== 'auto' && language == 'unknown')
              ) {
                this.tempFilename =
                  TEMP_FOLDER +
                  '/' +
                  format(Date.now(), 'yyyy_MM_dd_HH_mm_ss_SSS') +
                  '_temp.rb'
              } else if (language === 'python') {
                this.tempFilename =
                  TEMP_FOLDER +
                  '/' +
                  format(Date.now(), 'yyyy_MM_dd_HH_mm_ss_SSS') +
                  '_temp.py'
              } else {
                // No autosave for unknown language
                return
              }
              this.filename = this.tempFilename
              this.addToRecent(this.filename)
            }
          }
        }
        this.showSave = true
        await Api.post(`/script-api/scripts/${this.filename}`, {
          data: {
            text: this.editor.getValue(), // Pass in the raw file text
            breakpoints,
          },
        })
          .then((response) => {
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
          })
          .catch(({ response }) => {
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
          })
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
    delete() {
      let filename = this.filename
      if (this.tempFilename) {
        filename = this.tempFilename
      }
      this.$dialog
        .confirm(`Permanently delete file: ${filename}`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          return Api.post(`/script-api/scripts/${filename}/delete`, {
            data: {},
          })
        })
        .then((response) => {
          this.removeFromRecent(filename)
          this.newFile()
        })
        .catch((error) => {
          if (error) {
            const alertObject = {
              text: `Failed Multi-Delete. ${error}`,
              type: 'error',
            }
            this.$emit('alert', alertObject)
          }
        })
    },
    download() {
      const blob = new Blob([this.editor.getValue()], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', this.filename)
      link.click()
    },
    // ScriptRunner Script menu actions
    syntaxCheck() {
      Api.post(`/script-api/scripts/${this.filename}/syntax`, {
        data: this.editor.getValue(),
        headers: {
          Accept: 'application/json',
          'Content-Type': 'plain/text',
        },
      }).then((response) => {
        this.information.title = response.data.title
        this.information.text = JSON.parse(response.data.description)
        this.information.show = true
      })
    },
    showInstrumented() {
      Api.post(`/script-api/scripts/${this.filename}/instrumented`, {
        data: this.editor.getValue(),
        headers: {
          Accept: 'application/json',
          'Content-Type': 'plain/text',
        },
      }).then((response) => {
        this.information.title = response.data.title
        this.information.text = JSON.parse(response.data.description)
        this.information.show = true
      })
    },
    showCallStack() {
      Api.post(`/script-api/running-script/${this.scriptId}/backtrace`)
    },
    toggleDebug() {
      this.showDebug = !this.showDebug
    },
    toggleDisconnect() {
      this.showDisconnect = !this.showDisconnect
    },
    debugKeydown(event) {
      if (event.key === 'Escape') {
        this.debug = ''
        this.debugHistoryIndex = this.debugHistory.length
      } else if (event.key === 'Enter') {
        this.debugHistory.push(this.debug)
        this.debugHistoryIndex = this.debugHistory.length
        // Post the code to /debug, output is processed by receive()
        Api.post(`/script-api/running-script/${this.scriptId}/debug`, {
          data: {
            args: this.debug,
          },
        })
        this.debug = ''
      } else if (event.key === 'ArrowUp') {
        this.debugHistoryIndex -= 1
        if (this.debugHistoryIndex < 0) {
          this.debugHistoryIndex = this.debugHistory.length - 1
        }
        this.debug = this.debugHistory[this.debugHistoryIndex]
        // Prevent the cursor/caret from moving to the front
        event.preventDefault()
      } else if (event.key === 'ArrowDown') {
        this.debugHistoryIndex += 1
        if (this.debugHistoryIndex >= this.debugHistory.length) {
          this.debugHistoryIndex = 0
        }
        this.debug = this.debugHistory[this.debugHistoryIndex]
      }
    },
    removeAllMarkers: function () {
      const allMarkers = this.editor.session.getMarkers()
      Object.keys(allMarkers)
        .filter((key) => allMarkers[key].type === 'fullLine')
        .forEach((marker) => this.editor.session.removeMarker(marker))
    },
    confirmLocalUnlock: function () {
      this.$dialog
        .confirm(
          'Are you sure you want to unlock this script for editing? If another user is editing this script, your changes might conflict with each other.',
          {
            okText: 'Force Unlock',
            cancelText: 'Cancel',
          },
        )
        .then(() => {
          this.lockedBy = null
          return this.lockFile() // Re-lock it as this user so it's locked for anyone else who opens it
        })
    },
    lockFile: function () {
      return Api.post(`/script-api/scripts/${this.filename}/lock`)
    },
    unlockFile: function () {
      if (this.filename !== NEW_FILENAME && !this.readOnly) {
        Api.post(`/script-api/scripts/${this.filename}/unlock`)
      }
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
  },
}
</script>

<style scoped>
#sr-controls {
  padding: 0px;
}
.editorbox {
  height: 50vh;
}
.editor {
  height: 100%;
  width: 100%;
  position: relative;
  font-size: 16px;
}
hr {
  pointer-events: none;
  position: relative;
  top: 7px;
  background-color: grey;
  height: 3px;
  width: 5%;
  margin: auto;
}
.script-state {
  background-color: var(--color-background-base-default);
}
.script-state :deep(input) {
  text-transform: capitalize;
}
</style>
<style>
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
.fatalMarker {
  position: absolute;
  background: rgba(255, 0, 0, 0.5);
  z-index: 20;
}
.saving {
  z-index: 20;
  opacity: 0.35;
}
.ace_gutter-cell.ace_breakpoint {
  border-radius: 20px 0px 0px 20px;
  box-shadow: 0px 0px 1px 1px red inset;
}
.grid {
  position: relative;
}
.item {
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
</style>
