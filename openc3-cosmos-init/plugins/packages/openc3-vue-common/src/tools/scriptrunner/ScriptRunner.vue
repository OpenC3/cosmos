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
        ref="gridItem"
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
        <div id="sr-controls">
          <v-row no-gutters justify="space-between">
            <v-icon v-if="showDisconnect" class="mt-2" color="red">
              mdi-connection
            </v-icon>
            <div class="d-flex align-center mr-1">
              <v-tooltip :open-delay="600" location="top">
                <template #activator="{ props }">
                  <v-btn
                    v-if="!scriptActive"
                    v-bind="props"
                    icon="mdi-cached"
                    variant="text"
                    density="compact"
                    :disabled="filename === NEW_FILENAME"
                    aria-label="Reload File"
                    @click="reloadFile"
                  />
                  <v-btn
                    v-else
                    v-bind="props"
                    icon="mdi-arrow-left"
                    variant="text"
                    density="compact"
                    @click="backToNewScript"
                  />
                </template>
                <span v-if="!scriptActive"> Reload File </span>
                <span v-else> Back to New Script </span>
              </v-tooltip>
            </div>
            <v-tooltip
              location="bottom"
              :text="filenameSelect"
              :disabled="!filenameSelect || filenameSelect.length <= 45"
            >
              <template #activator="{ props }">
                <div v-bind="props" style="width: 32rem">
                  <v-select
                    id="filename"
                    v-model="filenameSelect"
                    :items="fileList"
                    :disabled="fileList.length <= 1"
                    label="Filename"
                    data-test="filename"
                    density="compact"
                    variant="outlined"
                    hide-details
                    @update:model-value="fileNameChanged"
                  />
                </div>
              </template>
            </v-tooltip>
            <v-text-field
              v-model="scriptId"
              label="Script ID"
              data-test="id"
              class="shrink ml-2 script-state"
              style="max-width: 100px"
              density="compact"
              variant="outlined"
              readonly
              hide-details
            />
            <v-text-field
              v-model="stateTimer"
              label="Script State"
              data-test="state"
              :class="['shrink', 'ml-2', 'script-state', stateColorClass]"
              style="max-width: 120px"
              density="compact"
              variant="outlined"
              readonly
              hide-details
            />
            <v-chip
              v-if="lifecycleVisible"
              class="ml-4 align-self-center"
              :color="lifecycleColor"
              variant="flat"
              data-test="lifecycle-chip"
              @click="showLifecycle = true"
            >
              {{ lifecycleLabel }}
            </v-chip>
            <v-progress-circular
              v-if="state === 'Connecting...'"
              :size="40"
              class="mx-2"
              indeterminate
              color="primary"
            />
            <div v-else style="width: 40px; height: 40px" class="mx-2"></div>

            <v-spacer />
            <v-tooltip
              v-if="showPythonVenv && startOrGoButton === 'Start'"
              :open-delay="600"
              location="top"
            >
              <template #activator="{ props: tooltipProps }">
                <div v-bind="tooltipProps">
                  <v-select
                    v-model="pythonVenv"
                    :items="pythonVenvs"
                    item-title="name"
                    item-value="name"
                    label="Python Venv"
                    density="compact"
                    variant="outlined"
                    hide-details
                    style="max-width: 200px; min-width: 160px"
                    class="mr-2"
                    data-test="python-venv-select"
                  >
                    <template #item="{ item, props: itemProps }">
                      <v-list-item
                        v-bind="itemProps"
                        :subtitle="item.raw.venv"
                      />
                    </template>
                  </v-select>
                </div>
              </template>
              <span>{{ selectedVenvPath }}</span>
            </v-tooltip>
            <div v-if="startOrGoButton === 'Start'" class="d-flex align-center">
              <v-tooltip
                v-if="overridesCount > 0"
                :open-delay="600"
                location="top"
              >
                <template #activator="{ props }">
                  <v-btn
                    v-bind="props"
                    class="mr-4"
                    icon
                    variant="text"
                    density="compact"
                    data-test="tlm-override-button"
                    aria-label="TLM Overrides"
                    @click="showOverrides = !showOverrides"
                  >
                    <v-badge
                      :content="overridesCount > 99 ? '99+' : overridesCount"
                      floating
                      color="primary"
                    >
                      <v-icon icon="mdi-application-cog-outline" />
                    </v-badge>
                  </v-btn>
                </template>
                <span> TLM Overrides ({{ overridesCount }}) </span>
              </v-tooltip>
              <v-tooltip :open-delay="600" location="top">
                <template #activator="{ props }">
                  <v-btn
                    v-bind="props"
                    class="mr-2"
                    icon
                    variant="text"
                    density="compact"
                    :disabled="envDisabled"
                    data-test="env-button"
                    aria-label="Script Environment"
                    @click="scriptEnvironment.show = !scriptEnvironment.show"
                  >
                    <v-badge v-model="environmentModified" floating dot>
                      <v-icon icon="mdi-application-variable" />
                    </v-badge>
                  </v-btn>
                </template>
                <span>
                  Script Environment
                  <template v-if="environmentModified"> (modified) </template>
                </span>
              </v-tooltip>
              <v-btn
                class="mx-1"
                color="primary"
                text="Start"
                data-test="start-button"
                :disabled="startOrGoDisabled || !executeUser || runBlocked"
                :hidden="suiteRunner"
                @click="startHandler"
              />
            </div>
            <div v-else>
              <v-btn
                color="primary"
                class="mr-2"
                text="Go"
                :disabled="startOrGoDisabled"
                data-test="go-button"
                @click="go"
              />
              <v-btn
                color="primary"
                class="mr-2"
                :text="pauseOrRetryButton"
                :disabled="pauseOrRetryDisabled"
                data-test="pause-retry-button"
                @click="pauseOrRetry"
              />
              <v-btn
                color="primary"
                text="Stop"
                data-test="stop-button"
                :disabled="stopDisabled"
                @click="stop"
              />
            </div>
          </v-row>
        </div>
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
        <pre
          ref="editor"
          class="editor"
          @contextmenu.prevent="showExecuteSelectionMenu"
        ></pre>
        <v-menu v-model="executeSelectionMenu" :target="[menuX, menuY]">
          <v-list>
            <v-list-item
              :title="currentLineHasCommand ? 'Edit Command' : 'Insert Command'"
              @click="openCommandEditor"
            />
            <v-divider />
            <v-list-item title="Execute Selection" @click="executeSelection" />
            <v-list-item
              v-if="executionPhase !== 'finishing'"
              :title="scriptActive ? 'Goto Line' : 'Run From Line'"
              @click="runFromCursor"
            />
            <v-list-item
              v-if="!scriptActive"
              title="Clear Local Breakpoints"
              @click="clearBreakpoints"
            />
            <v-divider />
            <v-list-item
              title="Toggle Vim mode"
              prepend-icon="extras:vim"
              @click="toggleVimMode"
            />
          </v-list>
        </v-menu>
      </pane>
      <pane id="messages" class="mt-2" :size="100 - editorBoxSize">
        <div v-if="showDebug" id="debug" class="pa-0">
          <v-row no-gutters>
            <v-btn
              color="primary"
              style="width: 100px"
              class="mr-4"
              text="Step"
              append-icon="mdi-step-forward"
              :disabled="!liveScriptId"
              data-test="step-button"
              @click="step"
            />
            <v-text-field
              ref="debug"
              v-model="debug"
              class="mb-2"
              variant="outlined"
              density="compact"
              hide-details
              label="Debug"
              data-test="debug-text"
              @keydown="debugKeydown"
            />
          </v-row>
        </div>
        <script-log-messages
          id="log-messages"
          v-model="messages"
          @sort="messageSortOrder"
        />
      </pane>
    </splitpanes>
  </div>

  <div
    v-else
    style="
      background-color: var(--color-background-base-default);
      margin: 0px;
      padding: 0px;
    "
  >
    <v-row no-gutters justify="right">
      <v-tabs v-model="inlineTab" density="compact">
        <v-tab value="script" text="Script" data-test="script-tab" />
        <v-tab value="messages" text="Messages" data-test="messages-tab" />
      </v-tabs>
      <v-tooltip
        location="bottom"
        :text="filenameSelect"
        :disabled="!filenameSelect || filenameSelect.length <= 45"
      >
        <template #activator="{ props }">
          <div v-bind="props" style="width: 32rem">
            <v-select
              id="inline-filename"
              v-model="filenameSelect"
              :items="fileList"
              :disabled="fileList.length <= 1"
              label="Filename"
              data-test="filename"
              density="compact"
              variant="outlined"
              hide-details
              @update:model-value="fileNameChanged"
            />
          </div>
        </template>
      </v-tooltip>
      <v-text-field
        v-model="scriptId"
        label="Script ID"
        data-test="id"
        class="shrink ml-2 script-state"
        style="max-width: 100px"
        density="compact"
        variant="outlined"
        readonly
        hide-details
      />
      <v-text-field
        v-model="stateTimer"
        label="Script State"
        data-test="state"
        :class="['shrink', 'ml-2', 'script-state', stateColorClass]"
        style="max-width: 120px"
        density="compact"
        variant="outlined"
        readonly
        hide-details
      />
      <v-progress-circular
        v-if="state === 'Connecting...'"
        :size="40"
        class="mx-2"
        indeterminate
        color="primary"
      />
    </v-row>
    <v-tabs-window v-model="inlineTab">
      <v-tabs-window-item value="script">
        <v-row>
          <v-col
            class="v-col-10"
            style="margin: 15px 0px 0px 0px; padding: 0px"
          >
            <pre
              ref="editor"
              class="editor"
              style="height: 200px"
              @contextmenu.prevent="showExecuteSelectionMenu"
            ></pre>
          </v-col>
          <v-col
            class="v-col-2"
            style="
              display: flex;
              justify-content: center;
              align-items: center;
              background-color: var(--color-background-surface-default);
            "
          >
            <div v-if="startOrGoButton === 'Start'">
              <v-btn
                class="mx-1"
                color="primary"
                text="Start"
                data-test="start-button"
                :disabled="startOrGoDisabled || !executeUser || runBlocked"
                :hidden="suiteRunner"
                @click="startHandler"
              />
            </div>
            <div v-else>
              <v-btn
                color="primary"
                class="ma-2"
                text="Go"
                :disabled="startOrGoDisabled"
                data-test="go-button"
                @click="go"
              />
              <v-btn
                color="primary"
                class="ma-2"
                :text="pauseOrRetryButton"
                :disabled="pauseOrRetryDisabled"
                data-test="pause-retry-button"
                @click="pauseOrRetry"
              />

              <v-btn
                color="primary"
                class="ma-2"
                text="Stop"
                data-test="stop-button"
                :disabled="stopDisabled"
                @click="stop"
              />
            </div>
          </v-col>
        </v-row>
      </v-tabs-window-item>

      <v-tabs-window-item value="messages">
        <div style="height: 200px; overflow: hidden">
          <script-log-messages
            v-model="messages"
            :newest-on-top="messagesNewestOnTop"
            @message-order-changed="messageOrderChanged"
          />
        </div>
      </v-tabs-window-item>
    </v-tabs-window>
  </div>

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
  <bucket-dialog
    v-if="bucket.show"
    v-model="bucket.show"
    :title="bucket.title"
    :message="bucket.message"
    :default-path="bucket.defaultPath"
    :filter="bucket.filter"
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
    :description="prompt.description"
    :hazardous="prompt.hazardous"
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
  <script-lifecycle-dialog
    v-if="showLifecycle"
    v-model="showLifecycle"
    :filename="filename"
    :state="lifecycleState"
    :history="lifecycleHistory"
    :can-approve="canApprove"
    :can-edit="!readOnlyUser"
    :time-zone="timeZone"
    @updated="lifecycleUpdated"
  />
  <critical-cmd-dialog
    v-model="displayCriticalCmd"
    :uuid="criticalCmdUuid"
    :cmd-string="criticalCmdString"
    :cmd-user="criticalCmdUser"
    :persistent="true"
    @status="promptDialogCallback"
  />
  <version-history-dialog
    v-if="showVersionHistory"
    v-model="showVersionHistory"
    :filename="filename"
    :current-body="editor ? editor.getValue() : ''"
    @restored="onVersionRestored"
  />
  <!-- Command Editor Dialog -->
  <v-dialog
    v-model="commandEditor.show"
    max-width="1200"
    persistent
    scrollable
    @keydown.esc="closeCommandDialog"
  >
    <v-card>
      <v-card-title class="d-flex align-center">
        <span>Insert Command</span>
        <v-spacer />
        <v-btn icon="mdi-close" variant="text" @click="closeCommandDialog" />
      </v-card-title>
      <v-card-text class="pa-0">
        <div v-if="commandEditor.dialogError" class="error-message">
          <v-icon class="mr-2" color="error">mdi-alert-circle</v-icon>
          <span class="flex-grow-1">{{ commandEditor.dialogError }}</span>
          <v-btn
            icon="mdi-close"
            size="small"
            variant="text"
            color="error"
            class="ml-2"
            @click="commandEditor.dialogError = null"
          />
        </div>
        <command-editor
          ref="commandEditor"
          :initial-target-name="commandEditor.targetName"
          :initial-packet-name="commandEditor.packetName"
          :cmd-string="commandEditor.cmdString"
          :send-disabled="false"
          :show-command-button="false"
          @build-cmd="insertCommand($event)"
        />
      </v-card-text>
      <v-card-actions>
        <v-spacer />
        <v-btn variant="outlined" @click="closeCommandDialog"> Cancel </v-btn>
        <v-btn color="primary" variant="flat" @click="insertCommand()">
          Insert Command
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
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
import axios from 'axios'
import { format } from 'date-fns'
import { Splitpanes, Pane } from 'splitpanes'
import 'splitpanes/dist/splitpanes.css'

import { Api, Cable, OpenC3Api } from '@openc3/js-common/services'
import { useContainerHeight } from '@/composables/useContainerHeight'
import {
  AceEditorModes,
  AceEditorUtils,
  CriticalCmdDialog,
  EnvironmentDialog,
  FileOpenSaveDialog,
  Openc3Screen,
  SimpleTextDialog,
  TopBar,
} from '@/components'
import { ClassificationBanners } from '@/tools/base'
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
import ScriptLifecycleDialog from '@/tools/scriptrunner/Dialogs/ScriptLifecycleDialog.vue'
import CommandEditor from '@/components/CommandEditor.vue'
import SuiteRunner from '@/tools/scriptrunner/SuiteRunner.vue'
import ScriptLogMessages from '@/tools/scriptrunner/ScriptLogMessages.vue'
import {
  CmdCompleter,
  TlmCompleter,
  MnemonicChecker,
} from '@/tools/scriptrunner/autocomplete'
import { SleepAnnotator } from '@/tools/scriptrunner/annotations'
import RunningScripts from '@/tools/scriptrunner/RunningScripts.vue'
import { useScriptLifecycle } from '@/tools/scriptrunner/useScriptLifecycle'
// Lazy-load the Enterprise-only Version History dialog so Monaco (~3 MB
// minified) lives in its own chunk that only downloads when the user
// opens version history. Core builds never reach this code path because
// the menu item is gated on the /openc3-api/info enterprise flag.
import { defineAsyncComponent } from 'vue'
const VersionHistoryDialog = defineAsyncComponent(
  () => import('@/tools/scriptrunner/VersionHistoryDialog.vue'),
)

// Matches target_file.rb TEMP_FOLDER
const TEMP_FOLDER = '__TEMP__'
const NEW_FILENAME = '<Untitled>'
const START = 'Start'
const GO = 'Go'
const PAUSE = 'Pause'
const RETRY = 'Retry'
// State/control events remain responsive at the 100 ms receive interval, but
// rebuilding a 200-row Vuetify table that often adds no visible value at that
// rate is expensive during output-heavy scripts.
const OUTPUT_FLUSH_INTERVAL_MS = 500
// Matches is_complete in script_status_model
const TERMINAL_STATES = new Set([
  'completed',
  'completed_errors',
  'stopped',
  'crashed',
  'killed',
])

// detectLanguage() heuristics
const RUBY_REQUIRE_REGEX = /^\s*(require|load|puts) /
const RUBY_END_REGEX = /^\s*end\s*$/
// Ruby named parameters, e.g. "foo(bar: 1)". Split into two independent tests
// because the single regex this replaced (/\(.*\w+:\s+.+\)(?!:)$/) nested two
// greedy .* around \w+:, so a long line that did NOT match cost time quadratic
// in its length -- and detectLanguage() runs this over every line of the file.
// Each half below has one unambiguous quantifier and so is linear.
// Python type annotations are defined like "def method(string: str):", so
// requiring the line to end in ')' rather than ':' is what excludes them.
const CLOSING_PAREN_REGEX = /\)$/
const NAMED_PARAM_REGEX = /\w:\s/
const PYTHON_IMPORT_REGEX = /^\s*(import|from) /
const PYTHON_BLOCK_REGEX = /^\s*(if|def|while|else|elif|class).*:\s*$/
const PYTHON_FSTRING_REGEX = /\(f"/ // f strings

const RUBY_SUITE_TEMPLATE = `require 'openc3/script/suite.rb'

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
`

const PYTHON_SUITE_TEMPLATE = `from openc3.script.suite import Suite, Group

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
`

export default {
  components: {
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
    ScriptLifecycleDialog,
    SimpleTextDialog,
    SuiteRunner,
    RunningScripts,
    ScriptLogMessages,
    CriticalCmdDialog,
    CommandEditor,
    VersionHistoryDialog,
  },
  mixins: [AceEditorModes, ClassificationBanners],
  beforeRouteUpdate: function (to, from, next) {
    if (to.params.id) {
      this.tryLoadRunningScript(to.params.id).then(next)
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

    return { containerHeight, ...useScriptLifecycle() }
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
      // Execution lifecycle owned by this component. scriptId is not a
      // reliable "is a script running" marker: the backend publishes the
      // terminal state ('completed', etc.) as a 'line' event BEFORE the
      // 'complete' event that drives scriptComplete(), so there is a window
      // where the UI shows completed but scriptId is still set and an async
      // reloadFile is pending. 'idle' -> 'active' (initScriptStart),
      // 'active' -> 'finishing' (terminal state seen in processLine),
      // any -> 'idle' (end of scriptComplete).
      executionPhase: 'idle',
      // Generation counter guarding async loads (reloadFile, the processLine
      // file fetch). Incremented whenever the authoritative file/breakpoint
      // source changes; stale callbacks compare their captured value and
      // drop their results instead of clobbering newer state.
      sessionEpoch: 0,
      // Generation counter guarding the websocket subscription (scriptStart /
      // scriptComplete). Comparing scriptId is not enough: two interleaved
      // scriptStart calls with the SAME id (e.g. beforeRouteUpdate re-firing
      // for the already-attached script) would both pass an id check, create
      // two subscriptions, and deliver every event twice.
      subscribeToken: 0,
      startOrGoButton: START,
      startOrGoDisabled: false,
      envDisabled: false,
      pauseOrRetryButton: PAUSE,
      showEnvironment: false,
      showDebug: false,
      debug: '',
      debugHistory: [],
      debugHistoryIndex: 0,
      showDisconnect: false,
      files: {},
      breakpoints: {},
      enableStackTraces: false,
      filename: NEW_FILENAME,
      showVersionHistory: false,
      // Enterprise-only feature; populated from /openc3-api/info on mount.
      isEnterprise: false,
      readOnlyUser: false,
      executeUser: true,
      saveAllowed: true,
      tempFilename: null,
      fileModified: '',
      fileOpen: false,
      lockedBy: null,
      showEditingToast: false,
      showSaveAs: false,
      areYouSure: false,
      subscription: null,
      cable: null,
      fatal: false,
      updateInterval: null,
      messages: [],
      messagesNewestOnTop: true,
      inlineTab: 'script',
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
      bucket: {
        show: false,
        title: '',
        message: '',
        defaultPath: null,
        filter: null,
      },
      prompt: {
        show: false,
        title: '',
        subtitle: '',
        message: '',
        details: '',
        description: '',
        hazardous: '',
        buttons: null,
        layout: 'horizontal',
        callback: () => {},
      },
      information: {
        show: false,
        title: '',
        text: [],
        width: '600',
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
      overridesCount: 0,
      commandEditor: {
        show: false,
        targetName: null,
        commandName: null,
        dialogError: null,
        cmdString: null,
        isEditing: false,
        editLine: null,
      },
      currentLineHasCommand: false,
      activePromptId: '',
      api: null,
      timeZone: 'local',
      screens: [],
      screenKeywords: null,
      idCounter: 0,
      updateCounter: 0,
      recent: [],
      waitingInterval: null,
      waitingTime: 0,
      waitingStart: 0,
      criticalCmdUuid: null,
      criticalCmdString: null,
      criticalCmdUser: null,
      displayCriticalCmd: false,
      editorBoxSize: 50,
      lockingEnabled: true,
      canApprove: false,
      // Enterprise-only Version History; enabled when the backend has
      // OPENC3_VERSION_HISTORY_DIR set (reported by /openc3-api/info).
      scriptVersionsEnabled: false,
      pythonVenv: 'system',
      pythonVenvs: [],
    }
  },
  computed: {
    // True for the entire execution lifecycle: from Start (or connecting to
    // a running script) through the finishing window between the terminal
    // 'line' event and scriptComplete(). Use this to gate editing/UI, not
    // scriptId, which is set late (after the run POST returns) and cleared
    // late (during scriptComplete after an async reload).
    scriptActive: function () {
      return this.executionPhase !== 'idle'
    },
    // The id of a script we can command right now. Non-null only while the
    // phase is 'active' (not during 'finishing', when the script process is
    // already gone) and after the run POST has returned the id (scriptId is
    // briefly null at the start of the 'active' phase).
    liveScriptId: function () {
      return this.executionPhase === 'active' ? this.scriptId : null
    },
    // Pause/Retry and Stop only make sense against a commandable script;
    // deriving these (rather than imperatively toggling flags at every
    // lifecycle write site) makes stale-event wedges impossible
    pauseOrRetryDisabled: function () {
      return !this.liveScriptId
    },
    stopDisabled: function () {
      return !this.liveScriptId
    },
    stateTimer: function () {
      if (this.state === 'waiting' || this.state === 'paused') {
        return `${this.state} ${this.waitingTime}s`
      }
      // Map completed_errors to completed for display
      // it will be colored via the stateColorClass
      if (this.state === 'completed_errors') {
        return 'completed'
      }
      return this.state
    },
    stateColorClass: function () {
      // All possible states: spawning, init, running, paused, waiting, breakpoint,
      // error, crashed, stopped, completed, completed_errors, killed
      if (
        this.state === 'error' ||
        this.state === 'crashed' ||
        this.state === 'killed'
      ) {
        return 'script-state-red'
      } else if (this.state === 'completed_errors') {
        return 'script-state-orange'
      } else if (this.state === 'completed') {
        return 'script-state-green'
      } else {
        return ''
      }
    },
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
    showPythonVenv: function () {
      if (this.pythonVenvs.length === 0) return false
      const name = this.tempFilename || this.filename
      return (
        name === NEW_FILENAME ||
        (name.startsWith(TEMP_FOLDER) && name.endsWith('.py'))
      )
    },
    selectedVenvPath: function () {
      if (!this.pythonVenv) return 'Select Python virtual environment'
      const entry = this.pythonVenvs.find((e) => e.name === this.pythonVenv)
      return entry ? entry.venv : this.pythonVenv
    },
    isLocked: function () {
      if (!this.lockingEnabled) {
        return false
      }
      return !!this.lockedBy
    },
    // Users with only the script_run (runner) permission may only run
    // approved scripts when the lifecycle feature is enabled
    runBlocked: function () {
      return (
        this.lifecycleEnabled &&
        this.scriptVersionsEnabled &&
        this.readOnlyUser &&
        this.executeUser &&
        this.lifecycleState !== 'approved'
      )
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
    // Temp files are auto-saved unsaved scripts under the __TEMP__ folder.
    // They aren't real saved scripts, so they get no lifecycle.
    isTempFile: function () {
      return this.filename.startsWith(`${TEMP_FOLDER}/`)
    },
    // Lifecycle only applies to real, saved (non-temp, non-untitled) scripts.
    // It is git-backed, so it also requires the version store (Enterprise).
    lifecycleVisible: function () {
      return (
        this.lifecycleEnabled &&
        this.scriptVersionsEnabled &&
        this.filename !== NEW_FILENAME &&
        !this.isTempFile
      )
    },
    menus: function () {
      return [
        {
          label: 'File',
          items: [
            {
              label: 'New File',
              icon: 'mdi-file-plus',
              disabled: this.scriptActive || this.readOnlyUser,
              command: () => {
                this.newFileWithConfirm()
              },
            },
            {
              label: 'New Suite',
              icon: 'mdi-file-document-plus',
              disabled: this.scriptActive || this.readOnlyUser,
              subMenu: [
                {
                  label: 'Ruby',
                  icon: 'mdi-language-ruby',
                  command: () => {
                    this.newTestSuite(RUBY_SUITE_TEMPLATE)
                  },
                },
                {
                  label: 'Python',
                  icon: 'mdi-language-python',
                  command: () => {
                    this.newTestSuite(PYTHON_SUITE_TEMPLATE)
                  },
                },
              ],
            },
            {
              label: 'Open File',
              icon: 'mdi-folder-open',
              disabled: this.scriptActive,
              command: () => {
                this.openFileWithConfirm()
              },
            },
            {
              label: 'Open Recent',
              icon: 'mdi-folder-open',
              disabled: this.scriptActive,
              subMenu: this.recent,
            },
            {
              divider: true,
            },
            {
              label: 'Save File',
              icon: 'mdi-content-save',
              disabled:
                this.scriptActive || this.readOnlyUser || this.scriptApproved,
              tooltip: this.scriptApproved
                ? 'Script is approved and cannot be modified. Move it back to review to edit.'
                : null,
              command: () => {
                this.saveFile()
              },
            },
            {
              label: 'Save As...',
              icon: 'mdi-content-save',
              disabled: this.scriptActive || this.readOnlyUser,
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
              disabled: this.scriptActive,
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
              disabled:
                this.scriptActive || this.readOnlyUser || this.scriptApproved,
              tooltip: this.scriptApproved
                ? 'Script is approved and cannot be deleted. Move it back to review to delete.'
                : null,
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
              disabled: this.scriptActive,
              command: () => {
                this.editor.execCommand('replace')
              },
            },
            {
              label: 'Set Line Delay',
              icon: 'mdi-invoice-text-clock',
              disabled: this.scriptActive,
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
            ...(this.lifecycleVisible
              ? [
                  {
                    label: 'Script Lifecycle',
                    icon: 'mdi-list-status',
                    command: () => {
                      this.showLifecycle = true
                    },
                  },
                ]
              : []),
            {
              divider: true,
            },
            {
              label: 'Global Environment',
              icon: 'mdi-library',
              disabled: this.scriptActive,
              command: () => {
                this.showEnvironment = !this.showEnvironment
              },
            },
            {
              label: 'Metadata',
              icon: 'mdi-calendar',
              disabled: this.scriptActive,
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
              disabled: this.scriptActive,
              command: () => {
                this.syntaxCheck()
              },
            },
            {
              label: 'Mnemonic Check',
              icon: 'mdi-spellcheck',
              disabled: this.scriptActive,
              command: () => {
                this.checkMnemonics()
              },
            },
            {
              label: 'Instrumented Script',
              icon: 'mdi-code-braces-box',
              disabled: this.scriptActive,
              command: () => {
                this.showInstrumented()
              },
            },
            {
              label: 'Call Stack',
              icon: 'mdi-format-list-numbered',
              disabled: !this.scriptActive,
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
              disabled: this.scriptActive,
              command: () => {
                this.toggleDisconnect()
              },
            },
            {
              label: 'Enable Stack Traces',
              checkbox: true,
              checked: this.enableStackTraces,
              disabled: this.scriptActive,
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
              disabled: this.scriptActive,
              command: () => {
                this.deleteAllBreakpoints()
              },
            },
            // Enterprise-only Version History entry. ScriptVersionController
            // lives in the openc3-enterprise gem; omit the divider + item
            // entirely so Core builds don't render a dead menu option.
            ...(this.scriptVersionsEnabled
              ? [
                  { divider: true },
                  {
                    label: 'Version History',
                    icon: 'mdi-history',
                    disabled:
                      this.scriptActive ||
                      !this.filename ||
                      this.filename === NEW_FILENAME,
                    command: () => {
                      this.showVersionHistory = true
                    },
                  },
                ]
              : []),
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
      if (!this.readOnlyUser && !val && !this.inline && !this.scriptApproved) {
        this.editor.setReadOnly(val)
      } else {
        this.editor.setReadOnly(true)
      }
    },
    scriptApproved: function (val) {
      if (!this.editor) {
        return
      }
      if (val) {
        this.editor.setReadOnly(true)
      } else if (
        !this.readOnlyUser &&
        !this.isLocked &&
        !this.inline &&
        !this.scriptActive
      ) {
        this.editor.setReadOnly(false)
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
    showOverrides: function (newVal, oldVal) {
      if (oldVal && !newVal) {
        this.updateOverridesCount()
      }
    },
  },
  created: async function () {
    // Websocket event queue drained by the processReceived interval.
    // Deliberately NOT in data(): nothing renders from it, and reactive
    // proxying would tax the hottest data path (per line event)
    this.receivedEvents = []
    // Output does not need strict ordering with control events and is capped in
    // the UI. Keep it out of the unbounded control queue so a print-heavy loop
    // cannot delay prompts, state changes, or completion processing.
    this.receivedOutputEvents = new Array(this.maxArrayLength)
    this.receivedOutputEventCount = 0
    this.receivedOutputEventIndex = 0
    this.pendingOutputLines = []
    this.lastOutputFlush = 0
    // Track the execution marker outside Vue reactivity. Tight loops often
    // report the same handful of lines repeatedly; repainting an unchanged
    // marker still makes Ace scan markers, render, and scroll the editor.
    this.highlightedLine = null
    this.highlightedState = null
    this.highlightedFilename = null
    // Ensure Offline Access Is Setup For the Current User
    this.api = new OpenC3Api()
    this.api.ensure_offline_access()
    // Detect Enterprise and whether the Version History backend is enabled
    // (OPENC3_VERSION_HISTORY_DIR set) so we can show the menu item.
    Api.get('/openc3-api/info')
      .then((response) => {
        this.isEnterprise = !!response.data?.enterprise
        this.scriptVersionsEnabled = !!response.data?.script_versions
      })
      .catch(() => {
        this.isEnterprise = false
        this.scriptVersionsEnabled = false
      })
    this.api
      .get_setting('time_zone')
      .then((response) => {
        if (response) {
          this.timeZone = response
        }
      })
      .catch((error) => {
        // Do nothing
      })
    // Independent settings fetches: run them concurrently
    await Promise.all([
      this.api
        .get_setting('script_runner_locking')
        .then((lockingResponse) => {
          if (lockingResponse !== null && lockingResponse !== undefined) {
            this.lockingEnabled = lockingResponse
          }
        })
        .catch(() => {
          // Keep default (true)
        }),
      this.loadLifecycleSetting(),
    ])

    this.updateOverridesCount()

    Api.get('/script-api/scripts/plugin_python_venvs')
      .then((response) => {
        this.pythonVenvs = [
          { name: 'system', venv: '/openc3/python/.venv' },
          ...response.data,
        ]
      })
      .catch(() => {
        // Python venvs will remain empty
      })

    // Make NEW_FILENAME available to the template
    this.NEW_FILENAME = NEW_FILENAME

    let user = OpenC3Auth.user()
    let roles = OpenC3Auth.userroles()
    this.readOnlyUser = true
    this.executeUser = false
    const customRoles = []
    for (let role of roles) {
      if (role == 'viewer') {
        continue
      }
      if (role == 'admin' || role == 'operator') {
        this.readOnlyUser = false
        this.executeUser = true
        this.canApprove = true
      } else if (role == 'runner') {
        this.executeUser = true
      } else {
        customRoles.push(role)
      }
    }
    // Fetch custom role permissions concurrently rather than one
    // serialized round trip per role
    await Promise.all(
      customRoles.map(async (role) => {
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
          if (
            response.data.permissions.some(
              (i) => i.permission == 'script_approver',
            )
          ) {
            this.canApprove = true
          }
        }
      }),
    )
    // Output the userinfo for use in the SuiteRunner component
    if (!this.inline) {
      localStorage['script_runner__userinfo'] = JSON.stringify({
        name: user['preferred_username'],
        readOnly: this.readOnlyUser,
        execute: this.executeUser,
      })
    }
    if (this.readOnlyUser) {
      this.alertType = 'info'
      let text = `User ${user['preferred_username']} is read only`
      if (this.executeUser) {
        text += ' but can execute scripts'
      }
      this.alertText = text
      this.showAlert = true
    }

    Api.get('/openc3-api/autocomplete/keywords/screen')
      .then((response) => {
        this.screenKeywords = response.data
      })
      .catch(console.error)

    if (this.inline) {
      this.readOnly = true
    }
  },
  mounted: async function () {
    this.editor = ace.edit(this.$refs.editor)
    this.editor.setTheme('ace/theme/twilight')
    const RubyMode = this.buildRubyMode()
    const PythonMode = this.buildPythonMode()
    this.rubyMode = new RubyMode()
    this.pythonMode = new PythonMode()
    const language = AceEditorUtils.getDefaultScriptingLanguage()
    if (language === 'python') {
      this.editor.session.setMode(this.pythonMode)
    } else {
      this.editor.session.setMode(this.rubyMode)
    }
    this.editor.session.setTabSize(2)
    this.editor.session.setUseWrapMode(true)
    this.editor.$blockScrolling = Infinity
    this.editor.setOption('enableBasicAutocompletion', true)
    this.editor.setOption('enableLiveAutocompletion', true)
    this.editor.completers = [new CmdCompleter(), new TlmCompleter()]
    this.editor.setHighlightActiveLine(false)
    AceEditorUtils.applyVimModeIfEnabled(this.editor, { saveFn: this.saveFile })
    this.editor.focus()

    this.editor.on('guttermousedown', this.toggleBreakpoint)
    // We listen to tokenizerUpdate rather than change because this
    // is the background process that updates as changes are processed
    // while change fires immediately before the UndoManager is updated.
    this.editor.session.on('tokenizerUpdate', this.onChange)
    if (this.readOnlyUser || this.inline) {
      this.editor.setReadOnly(true)
      this.editor.renderer.$cursorLayer.element.style.display = 'none'
    }

    const sleepAnnotator = new SleepAnnotator(this.editor)
    this.editor.session.on('change', ($event, session) => {
      sleepAnnotator.annotate($event, session)
      this.updateBreakpoints($event, session)
    })

    this.editor.container.addEventListener('resize', this.doResize)
    // Listen on window (not editor.container) so Ctrl-S saves regardless of
    // where focus is — attaching to the editor only caught the key while the
    // cursor was in the editor, which made saving feel inconsistent after
    // using a menu, button, or dialog. Removed in beforeUnmount.
    window.addEventListener('keydown', this.keydown)

    this.cable = new Cable('/script-api/cable')

    if (!this.inline && localStorage['script_runner__recent']) {
      // Rebuild the command since that doesn't get stringified
      this.recent = JSON.parse(localStorage['script_runner__recent']).map(
        (item) => this.buildRecentEntry(item.label),
      )
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
        this.editor.setValue(this.body)
        this.editor.clearSelection()
        // If initialFilename is provided, use it for path resolution
        if (this.initialFilename) {
          this.filename = this.initialFilename
        }
      }
    }
    this.updateInterval = setInterval(() => {
      this.processReceived()
    }, 100) // Every 100ms
  },
  beforeUnmount() {
    if (this.scriptId && !this.inline) {
      sessionStorage.setItem('script_runner__script_id', this.scriptId)
    }
    window.removeEventListener('keydown', this.keydown)
    this.editor.destroy()
    this.editor.container.remove()
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
    updateOverridesCount: function () {
      this.api.get_overrides().then((result) => {
        this.overridesCount = result.length
      })
    },
    toggleVimMode() {
      AceEditorUtils.toggleVimMode(this.editor)
    },
    openCommandEditor() {
      this.executeSelectionMenu = false
      const position = this.editor.getCursorPosition()
      const line = this.editor.session.getLine(position.row)

      if (this.currentLineHasCommand) {
        // Extract and parse the command from the line
        const cmdString = this.parseCommandFromLine(line)
        this.commandEditor.cmdString = cmdString
        this.commandEditor.isEditing = true
        this.commandEditor.editLine = position.row
      } else {
        // Inserting a new command
        this.commandEditor.cmdString = null
        this.commandEditor.isEditing = false
        this.commandEditor.editLine = null
      }
      this.commandEditor.show = true
      this.commandEditor.dialogError = null
    },
    insertCommand(event) {
      let commandString = ''
      try {
        commandString = this.$refs.commandEditor.getCmdString()
        let parts = commandString.split(' ')
        this.commandEditor.targetName = parts[0]
        this.commandEditor.commandName = parts[1]
      } catch (error) {
        this.commandEditor.dialogError =
          error.message || 'Please fix command parameters'
        return
      }

      if (
        this.commandEditor.isEditing &&
        this.commandEditor.editLine !== null
      ) {
        // Replace the existing line
        const line = this.editor.session.getLine(this.commandEditor.editLine)
        const indent = line.match(/^\s*/)[0] // Preserve indentation
        // Extract trailing comment if present
        const commentMatch = line.match(/\s+#.*$/)
        const trailingComment = commentMatch ? commentMatch[0] : ''
        const newLine = `${indent}cmd("${commandString}")${trailingComment}`
        const Range = this.Range
        this.editor.session.replace(
          new Range(
            this.commandEditor.editLine,
            0,
            this.commandEditor.editLine,
            line.length,
          ),
          newLine,
        )
      } else {
        // Insert a new command at the cursor position
        const position = this.editor.getCursorPosition()
        this.editor.session.insert(position, `cmd("${commandString}")\n`)
      }

      this.fileModified = true
      this.commandEditor.show = false
    },
    closeCommandDialog: function () {
      this.commandEditor.show = false
    },
    doResize() {
      this.editor.resize()
    },
    scriptDisconnect() {
      if (this.subscription) {
        this.subscription.unsubscribe()
        this.subscription = null
      }
      this.receivedEvents.length = 0 // Clear any unprocessed events
      this.discardPendingOutput()
    },
    showMetadata() {
      Api.get('/openc3-api/metadata')
        .then((response) => {
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
        .catch(console.error)
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
      // Strip the '*' which indicates modified
      filename = filename.replace(/\*$/, '')
      this.editor.setValue(this.files[filename].content)
      this.restoreBreakpoints(filename)
      this.markLine(this.files[filename].lineNo, this.state)
    },
    // Install new editor content. setValue resets the scroll and invalidates
    // any existing execution marker, so drop the markLine cache to force the
    // next markLine to repaint and rescroll.
    setEditorContent(content) {
      this.editor.setValue(content)
      this.editor.clearSelection()
      this.highlightedLine = null
      this.highlightedState = null
      this.highlightedFilename = null
    },
    // Replace all fullLine markers with a single `${clazz}Marker` on lineNo
    // (1-based) and scroll to it
    markLine(lineNo, clazz) {
      // Only the marker work is cached. gotoLine always runs: markLine is also
      // how the editor scrolls to the current line, so a cache hit right after
      // a setValue (which resets the scroll to the top) would leave the user
      // staring at line 1 of a script stopped far below.
      if (
        lineNo !== this.highlightedLine ||
        clazz !== this.highlightedState ||
        this.currentFilename !== this.highlightedFilename
      ) {
        this.removeAllMarkers()
        this.editor.session.addMarker(
          new this.Range(lineNo - 1, 0, lineNo - 1, 1),
          `${clazz}Marker`,
          'fullLine',
        )
        this.highlightedLine = lineNo
        this.highlightedState = clazz
        this.highlightedFilename = this.currentFilename
      }
      this.editor.gotoLine(lineNo)
    },
    tryLoadRunningScript: function (id) {
      // Gate editing immediately: we're (probably) about to attach to a
      // running script, and gutter clicks made during this fetch would be
      // wiped when the running file loads. Every exit path normalizes the
      // phase: initScriptStart() on attach, scriptComplete() on
      // completed/not-found.
      this.executionPhase = 'active'
      return Api.get(`/script-api/running-script/${id}`)
        .then((response) => {
          if (response.data) {
            if (!TERMINAL_STATES.has(response.data.state)) {
              this.filename = response.data.filename
              this.tryLoadSuites(response)
              this.initScriptStart()
              this.scriptStart(id)
              // Show the state we just fetched rather than waiting on the first
              // channel event. A script paused at an error or a prompt only
              // republishes its state about once a second, and a script that is
              // simply running between lines may not publish for even longer, so
              // without this the user stares at "Connecting..." with no idea
              // what the script is doing.
              this.applyScriptStatus(response.data)
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
        })
        .catch((error) => {
          // TODO: This is appearing on the main page which is blurred from the presence of the bottom sheet
          // We should probably not allow the bottom sheet to blur the screen
          this.$notify.caution({
            title: `Running Script ${id} not found`,
            body: 'Check the Completed Scripts below ...',
          })
          this.scriptComplete()
          this.showScripts = true
        })
    },
    tryLoadSuites: function (response) {
      if (response.data.suites) {
        this.startOrGoDisabled = true
        this.suiteRunner = true
        this.suiteMap = JSON.parse(response.data.suites)
      }
      this.doResize()
    },
    showExecuteSelectionMenu: function ($event) {
      this.menuX = $event.pageX
      this.menuY = $event.pageY
      // Check if the current line contains a command
      const position = this.editor.getCursorPosition()
      const line = this.editor.session.getLine(position.row)
      this.currentLineHasCommand = this.isCommandLine(line)
      this.executeSelectionMenu = true
    },
    isCommandLine: function (line) {
      // Check if line contains cmd() or cmd_no_hazardous_check() or similar command patterns
      const trimmedLine = line.trim()
      // Match patterns like: cmd("...", cmd_no_hazardous_check("...", cmd_raw("...", etc.
      return /^\s*cmd(_\w+)?\s*\(/.test(trimmedLine)
    },
    parseCommandFromLine: function (line) {
      // Extract the command string from patterns like: cmd("TARGET COMMAND with PARAM value")
      const match = line.match(/cmd(_\w+)?\s*\(\s*["'](.+?)["']\s*\)/)
      if (match) {
        return match[2] // Return the command string
      }
      return null
    },
    runFromCursor: function () {
      const start_row = this.editor.getCursorPosition().row + 1
      this.executeRange(start_row)
    },
    executeSelection: function () {
      const range = this.editor.getSelectionRange()
      let start_row = range.start.row + 1
      let end_row = range.end.row + 1
      if (range.end.column === 0) {
        end_row -= 1
      }
      this.executeRange(start_row, end_row)
    },
    executeRange: function (start_row, end_row = null) {
      if (!this.scriptActive) {
        this.start(null, null, start_row, end_row)
      } else if (this.liveScriptId) {
        const args = [this.filenameSelect, start_row]
        if (end_row !== null) {
          args.push(end_row)
        }
        Api.post(
          `/script-api/running-script/${this.liveScriptId}/executewhilepaused`,
          {
            data: { args },
          },
        ).catch(console.error)
      }
    },
    clearBreakpoints: function () {
      this.editor.session.clearBreakpoints()
    },
    toggleBreakpoint: function ($event) {
      // Don't allow setting breakpoints during script execution. Gate on
      // scriptActive rather than scriptId: after the terminal 'line' event
      // the state box shows completed but scriptComplete() hasn't run yet
      // (scriptId still set, async reloadFile pending), and a click in that
      // window would be silently undone by the server-driven
      // restoreBreakpoints when the reload lands.
      if (this.scriptActive) {
        return
      }
      const row = $event.getDocumentPosition().row
      if ($event.editor.session.getBreakpoints(row, 0)[row]) {
        $event.editor.session.clearBreakpoint(row)
      } else {
        $event.editor.session.setBreakpoint(row)
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
      if (this.scriptActive || this.editor.getReadOnly() === true) {
        return
      }
      // NOTE: Chrome does not allow overriding Ctrl-N, Ctrl-Shift-N, Ctrl-T, Ctrl-Shift-T, Ctrl-W
      // NOTE: metaKey == Command on Mac
      if (
        (event.metaKey || event.ctrlKey) &&
        event.key?.toLowerCase() === 's'
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
      if (this.scriptActive || this.editor.getReadOnly() === true) {
        return
      }
      if (this.editor.session.getUndoManager().canUndo()) {
        this.fileModified = '*'
      } else {
        this.fileModified = ''
      }
    },
    checkMnemonics: function () {
      let filename = this.filename
      if (this.filename !== NEW_FILENAME) {
        // Check if the extension is not .rb or .py
        if (!(filename.endsWith('.rb') || filename.endsWith('.py'))) {
          Api.post(`/script-api/scripts/${this.filename}/mnemonics`, {
            data: this.editor.getValue(),
            headers: {
              Accept: 'application/json',
              'Content-Type': 'text/plain',
            },
          })
            .then((response) => {
              let alertText = ''
              alertText += `<strong>${response.data.title}</strong><br/><br/>`
              alertText += JSON.parse(response.data.description)
              this.$dialog.alert(alertText.trim(), { html: true })
            })
            .catch(console.error)
        }
      }
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
      this.executionPhase = 'active'
      this.disableSuiteButtons = true
      this.startOrGoDisabled = true
      this.envDisabled = true
      this.state = 'Connecting...'
      this.startOrGoButton = GO
      this.editor.setReadOnly(true)
    },
    async scriptStart(id) {
      this.$emit('script-id', id)
      this.scriptId = id
      // Invalidate any file loads still in flight from before this run
      // so they can't overwrite the editor mid-execution
      this.sessionEpoch++
      // Claim the subscription: any older scriptStart still awaiting its
      // unsubscribe/subscribe below sees a newer token and drops out
      const token = ++this.subscribeToken
      // Ensure only one subscription is ever active. scriptStart can be reached
      // again while a subscription already exists -- most notably "Connect to
      // Running Script", which updates the route (beforeRouteUpdate) on the
      // already-mounted component. A second subscription on the same connection
      // streams the same key and would deliver (and the frontend would process)
      // every event twice. Tear the old one down first.
      if (this.subscription) {
        await this.subscription.unsubscribe()
        this.subscription = null
      }
      if (token !== this.subscribeToken) {
        // A newer scriptStart (or scriptComplete) superseded this call
        // while we awaited the unsubscribe: let it own the subscription
        return
      }
      this.receivedEvents.length = 0 // Drop any events not yet processed
      this.discardPendingOutput()
      // Reset prompt tracking so the first prompt re-published on this fresh
      // subscription is always processed and displayed. Without this, attaching
      // to a running script (which reuses the component) could carry over a
      // stale activePromptId and skip showing the dialog (see handleScript).
      this.activePromptId = ''
      // `connected` below is called with `this` bound to the subscription, so
      // hold onto the component to reach its methods from there.
      const self = this
      const subscription = await this.cable.createSubscription(
        'RunningScriptChannel',
        window.openc3Scope,
        {
          // Tell the backend we are ready to stream events only after the
          // subscription is confirmed: a broadcast sent before the gateway
          // registers our stream is silently dropped, which could permanently
          // lose the startup line events of a script that then goes quiet
          // (stuck on 'Connecting...'). Fires again on reconnect, so the
          // backend is told we are ready again. See RunningScriptChannel#ready.
          // Not an arrow function: `this` must be the subscription so perform()
          // targets this channel.
          connected(data) {
            this.perform('ready')
            // A reconnect can silently cost us events: the channel's backlog
            // replay only runs when the server processes a fresh subscribe, and
            // a resumed session doesn't re-run it. Re-seed from the script's
            // status so the display can't be left showing a stale state.
            if (data?.reconnected) {
              self.refreshScriptStatus()
            }
          },
          received: (data) => this.received(data),
        },
        {
          id,
        },
      )
      if (token !== this.subscribeToken) {
        // Superseded while subscribing: drop the subscription we just made
        // instead of overwriting (and leaking) the newer one
        await subscription.unsubscribe()
        return
      }
      this.subscription = subscription
    },
    // Update the display from a script status (GET running-script/:id) rather
    // than a channel event. The state field is otherwise only ever set from
    // channel events, so any gap in the event stream leaves it stale.
    applyScriptStatus(data) {
      const filename = data.current_filename || data.filename
      if (!filename) {
        return
      }
      // Reuse processLine so the state, markers and button enable/disable all
      // follow the same rules they would for a real 'line' event.
      this.processLine({
        type: 'line',
        filename: filename,
        line_no: data.line_no,
        state: data.state,
      })
      if (TERMINAL_STATES.has(data.state)) {
        this.scriptComplete()
      }
    },
    async refreshScriptStatus() {
      const id = this.scriptId
      if (!id) {
        return
      }
      try {
        const response = await Api.get(`/script-api/running-script/${id}`)
        // Ignore a response that lost the race with a switch to another script
        if (response.data && this.scriptId === id) {
          this.applyScriptStatus(response.data)
        }
      } catch (error) {
        // Nothing to seed from -- leave the display as is
      }
    },
    async scriptComplete() {
      // Completion can also be reached through status refreshes or failed run
      // requests rather than a queued 'complete' event.
      this.queueReceivedOutputLines()
      this.flushOutputLines(true)
      // Supersede any scriptStart still awaiting its subscription. Must
      // happen before our unsubscribe below: a start resolving mid-complete
      // would otherwise install a fresh subscription after we tore ours
      // down, leaving a leaked channel delivering stale events.
      this.subscribeToken++
      // Make sure we process no more events
      if (this.subscription) {
        await this.subscription.unsubscribe()
        this.subscription = null
      }
      this.receivedEvents.length = 0 // Clear any unprocessed events
      this.discardPendingOutput()
      // Close any prompt dialogs a killed/stopped script left open;
      // answering them would POST to a script that no longer exists
      this.closePromptDialogs()

      // Note: reloadFile bumps sessionEpoch, invalidating any in-flight
      // per-line file fetches (processLine) from the finished run
      await this.reloadFile() // Make sure the right file is shown
      // We may have changed the contents (if there were sub-scripts)
      // so don't let the undo manager think this is a change
      this.editor.session.getUndoManager().reset()
      if (!this.readOnlyUser && !this.inline && !this.scriptApproved) {
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
      // Overrides can be set from a script
      this.updateOverridesCount()
      // Execution lifecycle fully over: editor reloaded, breakpoints
      // restored, scriptId cleared. Gutter clicks are honored again.
      this.executionPhase = 'idle'
    },
    environmentHandler: function (event) {
      this.scriptEnvironment.env = event
    },
    startHandler: function () {
      this.start()
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
      if (this.pythonVenv) {
        data['pythonVenv'] = this.pythonVenv
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
      // They may have changed it using the drop down.
      // currentFilename can briefly be null when connected to a running
      // script (the file is fetched asynchronously), so guard against it
      // to ensure the go request is always sent.
      if (this.currentFilename) {
        this.filenameSelect = this.currentFilename
        this.fileNameChanged(this.currentFilename)
      }
      Api.post(`/script-api/running-script/${this.scriptId}/go`).catch(
        console.error,
      )
    },
    pauseOrRetry() {
      if (this.pauseOrRetryButton === PAUSE) {
        Api.post(`/script-api/running-script/${this.scriptId}/pause`).catch(
          console.error,
        )
      } else {
        this.pauseOrRetryButton = PAUSE
        Api.post(`/script-api/running-script/${this.scriptId}/retry`).catch(
          console.error,
        )
      }
    },
    async stop() {
      await Api.post(`/script-api/running-script/${this.scriptId}/stop`)
    },
    async step() {
      if (this.liveScriptId) {
        await Api.post(`/script-api/running-script/${this.liveScriptId}/step`)
      }
    },
    // This is called by processLine no matter the current state
    handleWaiting() {
      // Not waiting/paused: tear down any timer and bail. Without the
      // return, every 'running' line event would recreate the interval
      // (timer churn per line, and a background tick for the whole run).
      if (this.state !== 'waiting' && this.state !== 'paused') {
        this.clearWaiting()
        return
      }
      if (this.waitingInterval !== null) {
        // If we're waiting and the interval is active then nothing to do
        return
      }
      this.waitingStart = Date.now()
      // Create an interval to count every second
      this.waitingInterval = setInterval(() => {
        this.waitingTime = Math.round((Date.now() - this.waitingStart) / 1000)
      }, 1000)
    },
    clearWaiting() {
      this.waitingTime = 0
      clearInterval(this.waitingInterval)
      this.waitingInterval = null
    },
    // display=false skips the Ace marker/scroll work; processReceived
    // passes it for 'line' events that are immediately superseded by
    // another 'line' event in the same drain (only the last one is ever
    // visible). State handling always runs.
    processLine(data, display = true) {
      if (data.filename && data.filename !== this.currentFilename) {
        const cached = this.files[data.filename]
        if (cached && !cached.pending) {
          this.currentFilename = data.filename
          this.setEditorContent(cached.content)
          this.restoreBreakpoints(data.filename)
        } else if (!cached) {
          // We don't have the contents of the running file (probably because connected to running script)
          // Set the contents initially to an empty string so we don't start slamming the API.
          // pending distinguishes this placeholder from real content: attaching
          // twice (Connect to Running Script re-enters scriptStart, which is
          // expected) would otherwise let the second attach take the branch
          // above, install '' in the editor and set currentFilename -- after
          // which every later event skips the content load and the script stays
          // blank forever.
          this.files[data.filename] = { content: '', lineNo: 0, pending: true }

          // Request the script we need
          const epoch = this.sessionEpoch
          Api.get(`/script-api/scripts/${data.filename}`)
            .then((response) => {
              if (epoch !== this.sessionEpoch) {
                // A newer file source took over while this fetch was in
                // flight (script completed / new file loaded) - drop it
                // rather than clobber the current breakpoints and content.
                // Clear the pending placeholder as the catch below does:
                // nothing else will land, so leaving it in place would make
                // every later event wait on a fetch that never completes
                // instead of retrying it.
                this.files[data.filename] = null
                return
              }
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
              if (epoch !== this.sessionEpoch) {
                return
              }
              // Error - Restore the file contents to null so we'll try the API again on the next line
              this.files[data.filename] = null
            })
        }
        // else: a fetch is already in flight for this file. Leave the editor and
        // currentFilename alone so a later event installs the content once it
        // lands, or retries if the fetch is dropped or fails -- both clear the
        // cache entry.
      }
      this.state = data.state
      switch (this.state) {
        // Handle all the script states, see script_status_model for details
        // spawning, init, running, paused, waiting, breakpoint, error, crashed, stopped, completed, completed_errors, killed
        case 'running':
          this.handleWaiting()
          this.startOrGoDisabled = false
          this.pauseOrRetryButton = PAUSE

          if (display) {
            this.markLine(data.line_no, 'running')
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
          if (display) {
            // Only fetch markers here: this is the sole case that reads
            // them, and it's off the per-line hot path
            const markers = this.editor.session.getMarkers()
            const existing = Object.keys(markers).filter(
              (key) => markers[key].clazz === `${this.state}Marker`,
            )
            if (existing.length === 0) {
              let line = data.line_no > 0 ? data.line_no : 1
              this.markLine(line, this.state)
              // Fatal errors don't always have a filename set
              if (data.filename) {
                this.files[data.filename].lineNo = line
              }
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
          // Mark the window between this terminal state and scriptComplete()
          // so user input (e.g. gutter clicks) stays gated until cleanup.
          // Guarded so a duplicate/replayed terminal event arriving after
          // scriptComplete can't push an idle session back to 'finishing'.
          if (this.executionPhase === 'active') {
            this.executionPhase = 'finishing'
            // The script process is gone; don't leave Go posting to it
            // during the finishing window (Pause/Stop derive from
            // liveScriptId and disable themselves). Inside the phase guard
            // so a replayed terminal event can't wedge Start disabled once
            // scriptComplete has re-enabled it.
            this.startOrGoDisabled = true
          }
          // Stop the waiting timer: nothing else clears it on terminal
          // states, and a surviving interval carries its stale waitingStart
          // into the next run's waiting display
          this.clearWaiting()
          this.removeAllMarkers()
          break

        default:
          break
      }
    },
    processReceived() {
      if (
        this.receivedEvents.length === 0 &&
        this.receivedOutputEventCount === 0
      ) {
        // Output is rendered less frequently than control events. Keep polling
        // so the final partial batch is displayed even after output goes quiet.
        this.flushOutputLines()
        return
      }
      // Detach the current batch instead of splicing a potentially large hot
      // queue after processing it. Events received during a future turn go
      // into the new array and are handled by the next interval.
      const events = this.receivedEvents
      this.receivedEvents = []
      // Only the newest maxArrayLength messages can survive the UI cap. Scan
      // backward so older output events and lines are never converted into
      // short-lived objects merely to be discarded below.
      this.queueReceivedOutputLines()
      // Highlight only the newest line in the whole batch. Looking only at
      // consecutive line events is insufficient because script output is
      // commonly interleaved between them, causing every line in a tight loop
      // to remove/add an Ace marker before the browser can paint any of them.
      let lastLineIndex = -1
      for (let i = events.length - 1; i >= 0; i--) {
        if (events[i].type === 'line') {
          lastLineIndex = i
          break
        }
      }
      let terminated = false
      for (let i = 0; i < events.length; i++) {
        const data = events[i]
        // console.log(data) // Uncomment for debugging
        try {
          switch (data.type) {
            case 'file':
              this.files[data.filename] = { content: data.text, lineNo: 0 }
              this.breakpoints[data.filename] = data.breakpoints
              if (this.currentFilename === data.filename) {
                this.restoreBreakpoints(data.filename)
              }
              break
            case 'line':
              // Every 'line' event runs the state machine (buttons, phase,
              // lineNo bookkeeping), but only the newest event in the entire
              // drain does Ace marker/scroll work. Intermediate states still
              // matter, but their highlights could never become visible.
              this.processLine(data, i === lastLineIndex)
              break
            case 'script':
              this.handleScript(data)
              break
            // DEPRECATED because the 'complete' message now includes the report
            case 'report':
              this.results.text = data.report
              this.results.show = true
              break
            case 'complete':
              // Do not leave the tail of the log waiting for the output throttle
              // when the script has already completed.
              this.flushOutputLines(true)
              if (data.report) {
                this.results.text = data.report
                this.results.show = true
              }
              // Set before the teardown below: 'complete' is terminal even if
              // scriptComplete() throws, and the catch would otherwise let the
              // loop run on against a half-torn-down session.
              terminated = true
              this.removeAllMarkers()
              this.scriptComplete()
              break
            case 'step':
              this.showDebug = true
              break
            case 'screen': {
              const screenIndex = this.screens.findIndex(
                (s) =>
                  s.target == data.target_name && s.screen == data.screen_name,
              )
              const definition =
                screenIndex === -1 ? {} : this.screens[screenIndex]
              definition.target = data.target_name
              definition.screen = data.screen_name
              definition.definition = data.definition
              definition.left = data.x || 0
              definition.top = data.y || 0
              definition.count = this.updateCounter++
              if (screenIndex === -1) {
                definition.id = this.idCounter++
                this.screens.push(definition)
              } else {
                this.screens[screenIndex] = definition
              }
              break
            }
            case 'clearscreen': {
              const screenIndex = this.screens.findIndex(
                (s) =>
                  s.target == data.target_name && s.screen == data.screen_name,
              )
              if (screenIndex !== -1) {
                this.screens.splice(screenIndex, 1)
              }
              break
            }
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
            case 'opentab':
              window.open(data.url, '_blank')
              break
            default:
              // console.log('Unexpected ActionCable message')
              // console.log(data)
              break
          }
        } catch (error) {
          // Isolate each event: the batch was detached from receivedEvents
          // above, so throwing out of this loop would permanently drop every
          // event after this one -- the receive interval has nothing left to
          // retry. Log and keep draining instead.
          console.error('ScriptRunner failed to process event', data, error)
        }
        // 'complete' is terminal and scriptComplete() tore the session down.
        // Anything after it in this batch would be processed against a dead
        // session -- a duplicate 'complete' reloading the file again, or a
        // replayed 'line' pushing state back to running.
        if (terminated) {
          break
        }
      }

      this.flushOutputLines()
    },
    collectRecentOutputLines(outputEvents) {
      const newestFirst = []
      for (
        let i = outputEvents.length - 1;
        i >= 0 && newestFirst.length < this.maxArrayLength;
        i--
      ) {
        let text = outputEvents[i]
        if (text === null || text === undefined) {
          continue
        } else if (typeof text === 'object') {
          text = JSON.stringify(text)
        } else {
          text = String(text)
        }

        // Walk backward without split(), which avoids allocating an array for
        // a very large multi-line output event when only its tail is visible.
        let end = text.length
        // end > 0, not end >= 0: lastIndexOf clamps a negative fromIndex to 0,
        // so text starting with '\n' would return 0 rather than -1 and spin
        // here forever. Nothing is left to collect at end === 0 anyway.
        while (end > 0 && newestFirst.length < this.maxArrayLength) {
          const newline = text.lastIndexOf('\n', end - 1)
          const line = text.slice(newline + 1, end)
          if (line) {
            newestFirst.push({ message: line })
          }
          if (newline === -1) {
            break
          }
          end = newline
        }
      }
      return newestFirst.reverse()
    },
    queueReceivedOutputLines() {
      if (this.receivedOutputEventCount === 0) {
        return
      }
      const outputEvents = []
      const start =
        (this.receivedOutputEventIndex -
          this.receivedOutputEventCount +
          this.maxArrayLength) %
        this.maxArrayLength
      for (let i = 0; i < this.receivedOutputEventCount; i++) {
        outputEvents.push(
          this.receivedOutputEvents[(start + i) % this.maxArrayLength],
        )
      }
      this.clearReceivedOutputEvents()
      this.queueOutputLines(this.collectRecentOutputLines(outputEvents))
    },
    clearReceivedOutputEvents() {
      this.receivedOutputEvents.fill(undefined)
      this.receivedOutputEventCount = 0
      this.receivedOutputEventIndex = 0
    },
    // Drop every output event and line that has not been rendered yet. Unlike
    // clearReceivedOutputEvents (which queueReceivedOutputLines uses to rotate
    // the ring buffer) this also drops lines already waiting on the flush
    // throttle, so a restart inside the throttle window cannot spill the old
    // run's output into the new run's log.
    discardPendingOutput() {
      this.clearReceivedOutputEvents()
      this.pendingOutputLines = []
    },
    queueOutputLines(lines) {
      if (lines.length > 0) {
        this.pendingOutputLines = this.pendingOutputLines
          .concat(lines)
          .slice(-this.maxArrayLength)
      }
    },
    flushOutputLines(force = false) {
      if (this.pendingOutputLines.length === 0) {
        return
      }
      const now = Date.now()
      if (!force && now - this.lastOutputFlush < OUTPUT_FLUSH_INTERVAL_MS) {
        return
      }

      const outputLines = this.pendingOutputLines
      this.pendingOutputLines = []
      this.lastOutputFlush = now
      if (this.messagesNewestOnTop) {
        this.messages = outputLines
          .slice()
          .reverse()
          .concat(this.messages)
          .slice(0, this.maxArrayLength)
      } else {
        this.messages = this.messages
          .concat(outputLines)
          .slice(-this.maxArrayLength)
      }
    },
    received(data) {
      this.cable.recordPing()
      // RunningScriptChannel sends bounded arrays to avoid one ActionCable
      // frame per script event. Also accept an individual event so the UI can
      // connect to an older backend during a rolling upgrade.
      const events = Array.isArray(data) ? data : [data]
      for (const event of events) {
        if (event.type === 'output') {
          this.receivedOutputEvents[this.receivedOutputEventIndex] = event.line
          this.receivedOutputEventIndex =
            (this.receivedOutputEventIndex + 1) % this.maxArrayLength
          this.receivedOutputEventCount = Math.min(
            this.receivedOutputEventCount + 1,
            this.maxArrayLength,
          )
        } else {
          this.receivedEvents.push(event)
        }
      }
    },
    // All prompt responses share the running-script prompt endpoint and
    // the active prompt id; payload carries the method-specific fields
    answerPrompt(method, payload) {
      return Api.post(`/script-api/running-script/${this.scriptId}/prompt`, {
        data: {
          method,
          prompt_id: this.activePromptId,
          ...payload,
        },
      })
    },
    closePromptDialogs() {
      this.prompt.show = false
      this.ask.show = false
      this.file.show = false
      this.bucket.show = false
      this.activePromptId = ''
    },
    promptDialogCallback(value) {
      this.prompt.show = false
      this.answerPrompt(this.prompt.method, {
        answer: value,
        multiple: this.prompt.multiple,
      })
    },
    handleScript(data) {
      if (data.prompt_complete) {
        this.closePromptDialogs()
        return
      }
      // The running script re-publishes the active prompt about once a second
      // while it waits for an answer. Ignore these repeats so we don't reset the
      // dialog state and re-fetch the hazardous command description on every
      // tick, which makes the dialog visibly bounce (issue #3472).
      if (data.prompt_id && data.prompt_id === this.activePromptId) {
        return
      }
      this.activePromptId = data.prompt_id
      this.prompt.method = data.method // Set it here since all prompts use this
      this.prompt.layout = 'horizontal' // Reset the layout since most are horizontal
      this.prompt.title = 'Prompt'
      this.prompt.subtitle = ''
      this.prompt.details = ''
      this.prompt.description = ''
      this.prompt.hazardous = ''
      this.prompt.buttons = []
      this.prompt.multiple = null
      // Shared optional kwargs (only the prompt-family dialogs read these;
      // harmless for the rest since both fields were just reset above)
      if (data.kwargs) {
        this.prompt.subtitle = data.kwargs.informative || ''
        this.prompt.details = data.kwargs.details || ''
      }
      switch (data.method) {
        case 'ask':
        case 'ask_string':
          // Reset values since this dialog can be reused
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
            // Using password as a key automatically filters it from rails logs
            const key = this.ask.password ? 'password' : 'answer'
            this.answerPrompt(data.method, { [key]: value })
          }
          this.ask.show = true // Display the dialog
          break
        case 'prompt_for_hazardous':
          this.prompt.title = 'Hazardous Command'
          this.prompt.message = `Warning: Command ${data.args[0]} ${data.args[1]} is Hazardous. Send?`
          if (data.args[2]) {
            this.prompt.hazardous = data.args[2]
          }
          // The HazardousError only carries the hazardous description, so fetch
          // the general command description to match Command Sender (issue #3472)
          this.api
            .get_cmd(data.args[0], data.args[1])
            .then((command) => {
              this.prompt.description = command.description || ''
            })
            .catch(() => {}) // Ignore - just don't show the description
          this.prompt.buttons = [{ text: 'Send', value: 'Send' }]
          this.prompt.callback = this.promptDialogCallback
          this.prompt.show = true
          break
        case 'prompt_for_critical_cmd':
          this.criticalCmdUuid = data.args[0]
          this.criticalCmdString = data.args[5]
          this.criticalCmdUser = data.args[1]
          this.displayCriticalCmd = true
          break
        case 'prompt':
          this.prompt.message = data.args[0]
          this.prompt.buttons = [{ text: 'Ok', value: 'Ok' }]
          this.prompt.callback = this.promptDialogCallback
          this.prompt.show = true
          break
        case 'combo_box':
        case 'check_box':
          // check_box is always multiple choice, combo_box is single choice unless kwargs.multiple is set to true
          if (
            data.method === 'check_box' ||
            (data.kwargs && data.kwargs.multiple)
          ) {
            this.prompt.multiple = true
          }
          this.prompt.message = data.args[0]
          data.args.slice(1).forEach((v) => {
            this.prompt.buttons.push({ title: v, value: v })
          })
          this.prompt.layout = data.method.split('_')[0]
          this.prompt.callback = this.promptDialogCallback
          this.prompt.show = true
          break
        case 'message_box':
        case 'vertical_message_box':
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
          this.information.width = '600'
          break
        case 'metadata_input':
          this.inputMetadata.callback = (value) => {
            this.inputMetadata.show = false
            this.answerPrompt(data.method, { answer: value })
          }
          this.showMetadata()
          break
        case 'open_bucket_dialog':
          this.bucket.title = data.args[0]
          this.bucket.message = data.args[1]
          this.bucket.defaultPath =
            (data.kwargs && data.kwargs.default_path) || null
          this.bucket.filter = (data.kwargs && data.kwargs.filter) || null
          this.bucket.show = true
          break
        // This is called continuously by the backend
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
          // console.log(
          // 'Unknown script method:' + data.method + ' with args:' + data.args
          // )
          break
      }
    },
    async uploadFile(file) {
      const response = await Api.get(
        `/openc3-api/storage/upload/${encodeURIComponent(
          `${window.openc3Scope}/tmp/${file.name}`,
        )}?bucket=OPENC3_CONFIG_BUCKET`,
      )
      // This pushes the file into storage by using the fields in the presignedRequest
      // See storage_controller.rb get_upload_presigned_request()
      return axios({
        ...response.data,
        data: file,
      })
    },
    async fileDialogCallback(files) {
      // Set fileNames to 'COSMOS__CANCEL' in case they cancelled
      // otherwise we will populate it with the file names they selected
      let fileNames = 'COSMOS__CANCEL'
      // Record all the API request promises so we can ensure they complete
      let promises = []
      if (files != 'COSMOS__CANCEL') {
        fileNames = []
        files.forEach((file) => {
          fileNames.push(file.name)
          promises.push(this.uploadFile(file))
        })
      }
      const respond = (answer) => {
        this.answerPrompt(
          this.file.multiple ? 'open_files_dialog' : 'open_file_dialog',
          { answer },
        )
        this.file.show = false // Close the dialog immediately to avoid race condition
      }
      try {
        // We have to wait for all the upload API requests to finish before notifying the prompt
        await Promise.all(promises)
        respond(fileNames)
      } catch (error) {
        // An upload failed. Answer with cancel so the running script
        // doesn't wait forever on a reply that will never come (repeats
        // of the same prompt_id are ignored, so nothing would recover).
        respond('COSMOS__CANCEL')
        this.setError(`File upload failed: ${error}`)
      }
    },
    bucketDialogCallback(response) {
      this.bucket.show = false
      this.answerPrompt('open_bucket_dialog', { answer: response })
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
      // Invalidate in-flight loads (reloadFile, processLine fetch) so a
      // late response can't reinstall the old file over the blank editor --
      // especially after delete(), which lands here
      this.sessionEpoch++
      this.unlockFile()
      this.filename = NEW_FILENAME
      this.currentFilename = null
      this.tempFilename = null
      this.resetLifecycle()
      this.files = {} // Clear the cached file list
      this.editor.session.setValue('')
      this.saveAllowed = true
      this.fileModified = ''
      this.suiteRunner = false
      this.startOrGoDisabled = false
      this.envDisabled = false
      this.pythonVenv = 'system'
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
    async newTestSuite(template) {
      const confirmed = await this.confirmUnsavedChanges()
      if (!confirmed) return
      this.newFile()
      this.editor.session.setValue(template)
      await this.saveFile('auto')
    },
    buildRecentEntry(filename) {
      return {
        label: filename,
        icon: fileIcon(filename),
        command: async (event) => {
          const confirmed = await this.confirmUnsavedChanges()
          if (!confirmed) return
          this.filename = event.label
          await this.reloadFile()
        },
      }
    },
    // This only stringifies the label and icon ... not the command
    persistRecent() {
      if (!this.inline) {
        localStorage['script_runner__recent'] = JSON.stringify(this.recent)
      }
    },
    addToRecent(filename) {
      // See if this filename is already in the recent ... if so remove it
      let index = this.recent.findIndex((i) => i.label === filename)
      if (index !== -1) {
        this.recent.splice(index, 1)
      }
      // Push this filename to the front of the recently used
      this.recent.unshift(this.buildRecentEntry(filename))
      if (this.recent.length > 8) {
        this.recent.pop()
      }
      this.persistRecent()
    },
    removeFromRecent(filename) {
      this.recent = this.recent.filter((entry) => entry.label !== filename)
      this.persistRecent()
      if (!this.inline) {
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
      if (this.filename === NEW_FILENAME) {
        // Nothing to reload (e.g. completing a script that was never
        // saved) -- skip the guaranteed-404 fetch and error toast
        return
      }
      // Disable start while we're loading the file so we don't hit Start
      // before it's fully loaded and then save over it with a blank file
      this.saveAllowed = false
      this.startOrGoDisabled = true
      // This load supersedes any earlier in-flight loads; capture the new
      // epoch so we in turn get dropped if something newer starts
      const epoch = ++this.sessionEpoch
      await Api.get(`/script-api/scripts/${this.filename}`, {
        headers: {
          Accept: 'application/json',
          'Ignore-Errors': '404',
        },
        params: {
          pythonVenv: this.showPythonVenv ? this.pythonVenv : null,
        },
      })
        .then((response) => {
          if (epoch !== this.sessionEpoch) {
            return
          }
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
          this.setFile({ file, locked, breakpoints }, true) // Sets saveAllowed
        })
        .catch((error) => {
          if (epoch !== this.sessionEpoch) {
            return
          }
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
      // New authoritative content: invalidate older in-flight loads so
      // their late responses can't overwrite what we install here
      this.sessionEpoch++
      // A superseded reloadFile set saveAllowed = false and its .then (the
      // only place it flips back) is now epoch-dropped -- re-allow here
      // since we're installing fresh content
      this.saveAllowed = true
      this.files = {} // Clear the cached file list
      // Strip the '*' which indicates a file is modified on the server
      let newFilename = file.name.replace(/\*$/, '')
      if (local === false) {
        // We only need to unlock if the file is different
        if (this.filename !== newFilename) {
          this.unlockFile() // first unlock what was just being edited
          this.lockedBy = locked
        }
      }
      this.filename = newFilename
      // Saved scripts resolve their venv from the file path, so clear
      // any manually selected python venv. Keep it for temp scripts
      // so the selection persists across runs.
      if (!newFilename.startsWith(TEMP_FOLDER)) {
        this.pythonVenv = null
        this.tempFilename = null
      }
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
        this.editor.session.setMode(this.pythonMode)
      } else {
        this.editor.session.setMode(this.rubyMode)
      }
      this.currentFilename = null
      this.editor.session.setValue(file.contents)
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
      this.fetchLifecycle(this.filename)
      this.doResize()
    },
    clearTemp() {
      this.recent = this.recent.filter(
        (entry) => !entry.label.includes('__TEMP__'),
      )
      this.persistRecent()
    },
    detectLanguage() {
      let text = this.editor.getValue()
      let lines = text.split('\n')
      for (let line of lines) {
        if (line.match(RUBY_REQUIRE_REGEX)) {
          return 'ruby'
        }
        if (line.match(PYTHON_IMPORT_REGEX)) {
          return 'python'
        }
        if (line.match(RUBY_END_REGEX)) {
          return 'ruby'
        }
        if (line.match(PYTHON_BLOCK_REGEX)) {
          return 'python'
        }
        if (line.match(PYTHON_FSTRING_REGEX)) {
          return 'python'
        }
        // Cheap end-anchored test first so most lines never run the second
        if (CLOSING_PAREN_REGEX.test(line) && NAMED_PARAM_REGEX.test(line)) {
          return 'ruby'
        }
      }
      return 'unknown' // otherwise unknown
    },
    // saveFile takes a type to indicate if it was called by the Menu
    // or automatically by 'Start' (to ensure a consistent backend file) or autoSave
    async saveFile(type = 'menu') {
      if (this.readOnlyUser) {
        return
      }
      if (this.scriptApproved) {
        if (type === 'menu') {
          this.setError(
            'Script is approved and cannot be modified. Move it back to review to edit.',
          )
        }
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
              let language = this.detectLanguage()
              if (language === 'unknown') {
                language = AceEditorUtils.getDefaultScriptingLanguage()
              }
              const ext = { ruby: 'rb', python: 'py' }[language]
              if (!ext) {
                // No autosave for unknown language
                return
              }
              const uuid = crypto.randomUUID().split('-')[0]
              const timestamp = format(Date.now(), 'yyyy_MM_dd_HH_mm_ss_SSS')
              this.tempFilename = `${TEMP_FOLDER}/${timestamp}_${uuid}_temp.${ext}`
              this.filename = this.tempFilename
              this.addToRecent(this.filename)
            }
          }
        }
        this.showSave = true
        const data = {
          text: this.editor.getValue(), // Pass in the raw file text
          breakpoints,
        }
        if (this.showPythonVenv) {
          data.pythonVenv = this.pythonVenv
        }
        await Api.post(`/script-api/scripts/${this.filename}`, { data })
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
            this.doResize()
          })
          .catch(({ response }) => {
            this.showSave = false
            // 422 error means we couldn't parse the script file into Suites
            // response.data.suites holds the parse result
            if (response.status == 422) {
              this.alertType = 'error'
              this.alertText = response.data.suites
            } else if (response.status == 403 && response.data?.message) {
              // e.g. attempting to save over an approved script
              this.alertType = 'error'
              this.alertText = response.data.message
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
      this.filename = filename.replace(/\*$/, '')
      this.currentFilename = null
      // The lifecycle state belongs to the file, not the editor contents,
      // so clear it before saving under the new name. The server still
      // rejects overwriting a different approved script.
      this.resetLifecycle()
      if (this.tempFilename) {
        Api.post(`/script-api/scripts/${this.tempFilename}/delete`).catch(
          console.error,
        )
        this.tempFilename = null
      }
      await this.saveFile('menu')
      // Pick up the actual lifecycle state of the file we saved over
      this.fetchLifecycle(this.filename)
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
          if (error !== true) {
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
          'Content-Type': 'text/plain',
        },
      })
        .then((response) => {
          this.information.title = response.data.title
          this.information.text = JSON.parse(response.data.description)
          this.information.show = true
          this.information.width = '600'
        })
        .catch(console.error)
    },
    showInstrumented() {
      Api.post(`/script-api/scripts/${this.filename}/instrumented`, {
        data: this.editor.getValue(),
        headers: {
          Accept: 'application/json',
          'Content-Type': 'text/plain',
        },
      })
        .then((response) => {
          this.information.title = response.data.title
          this.information.text = JSON.parse(response.data.description)
          this.information.show = true
          this.information.width = '90vw'
        })
        .catch(console.error)
    },
    showCallStack() {
      if (this.liveScriptId) {
        Api.post(
          `/script-api/running-script/${this.liveScriptId}/backtrace`,
        ).catch(console.error)
      }
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
    debugKeydown(event) {
      if (event.key === 'Escape') {
        this.debug = ''
        this.debugHistoryIndex = this.debugHistory.length
      } else if (event.key === 'Enter') {
        this.debugHistory.push(this.debug)
        this.debugHistoryIndex = this.debugHistory.length
        // Post the code to /debug, output is processed by receive()
        if (this.liveScriptId) {
          Api.post(`/script-api/running-script/${this.liveScriptId}/debug`, {
            data: {
              args: this.debug,
            },
          }).catch(console.error)
        }
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
      this.highlightedLine = null
      this.highlightedState = null
      this.highlightedFilename = null
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
      if (!this.readOnlyUser) {
        return Api.post(`/script-api/scripts/${this.filename}/lock`)
      }
    },
    unlockFile: function () {
      if (
        this.filename !== NEW_FILENAME &&
        !this.readOnly &&
        !this.readOnlyUser
      ) {
        Api.post(`/script-api/scripts/${this.filename}/unlock`).catch(
          console.error,
        )
      }
    },
    onVersionRestored: function () {
      this.reloadFile()
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
      const index = this.screens.findIndex((s) => s.id == id)
      if (index !== -1) {
        this.screens.splice(index, 1)
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

.error-message {
  border: 2px solid #f44336;
  border-radius: 8px;
  background-color: rgba(244, 67, 54, 0.1);
  color: #d32f2f;
  padding-left: 8px;
  padding-right: 8px;
  margin: 16px;
  display: flex;
  align-items: center;
  font-weight: 500;
  box-shadow: 0 2px 4px rgba(244, 67, 54, 0.2);
}

#sr-controls {
  padding: 0px;
}

.editor {
  height: 100%;
  width: 100%;
  position: relative;
  font-size: 16px;
}

.script-state :deep(.v-field) {
  background-color: var(--color-background-base-default);
}

.script-state :deep(input) {
  text-transform: capitalize;
}

/* Taken from the various status-symbol-color-fill classes
   on https://www.astrouxds.com/design-tokens/component/ */
.script-state-red :deep(input) {
  color: #ff3838 !important;
}

.script-state-orange :deep(input) {
  color: #ffb302 !important;
}

.script-state-green :deep(input) {
  color: #56f000 !important;
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
