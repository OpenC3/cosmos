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
    <v-dialog v-model="show" width="600">
      <v-card>
        <v-system-bar>
          <v-spacer />
          <span>Create New Reaction</span>
          <v-spacer />
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon
                  data-test="reaction-create-close-icon"
                  @click="clearHandler"
                >
                  mdi-close-box
                </v-icon>
              </div>
            </template>
            <span>Close</span>
          </v-tooltip>
        </v-system-bar>

        <v-stepper v-model="dialogStep" vertical non-linear>
          <v-stepper-step editable step="1">Input Triggers</v-stepper-step>
          <v-stepper-content step="1">
            <v-row class="ma-0">
              <v-switch
                v-model="reactionReview"
                label="Review Reaction Triggers after snooze"
                class="mx-2"
              />
            </v-row>
            <v-row class="ma-0">
              <v-select
                v-model="deadSelect"
                persistent-hint
                label="Select Triggers"
                hint="Triggers to cause Reaction"
                data-test="reaction-select-triggers"
                :items="triggerItems"
                @change="addTrigger"
              >
                <template v-slot:item="{ item, attrs, on }">
                  <v-list-item
                    v-on="on"
                    v-bind="attrs"
                    :data-test="`reaction-select-trigger-${item.count}`"
                  >
                    <v-list-item-content>
                      <v-list-item-title>{{ item.text }}</v-list-item-title>
                    </v-list-item-content>
                  </v-list-item>
                </template>
              </v-select>
            </v-row>
            <div data-test="triggerList">
              <div v-for="(trigger, i) in reactionTriggers" :key="trigger.name">
                <v-card outlined class="mt-1 px-0">
                  <v-card-title>
                    <span>{{ trigger.name }}{{ trigger.type }}</span>
                    <v-spacer />
                    <v-tooltip top>
                      <template v-slot:activator="{ on, attrs }">
                        <v-icon
                          v-bind="attrs"
                          v-on="on"
                          :data-test="`reaction-create-remove-trigger-${i}`"
                          @click="removeTrigger(trigger)"
                        >
                          mdi-delete
                        </v-icon>
                      </template>
                      <span>Remove Trigger</span>
                    </v-tooltip>
                  </v-card-title>
                </v-card>
              </div>
            </div>
            <v-row class="ma-0 pa-2">
              <v-spacer />
              <v-btn
                @click="dialogStep = 2"
                color="success"
                data-test="reaction-create-step-two-btn"
                :disabled="!reactionTriggers"
              >
                Continue
              </v-btn>
            </v-row>
          </v-stepper-content>

          <v-stepper-step editable step="2">Input Actions</v-stepper-step>
          <v-stepper-content step="2">
            <v-row class="ma-0">
              <v-radio-group v-model="reactionActionKind" row class="px-2">
                <v-radio
                  label="Notify"
                  value="NOTIFY"
                  data-test="reaction-action-option-notify"
                />
                <v-radio
                  label="Command"
                  value="COMMAND"
                  data-test="reaction-action-option-command"
                />
                <v-radio
                  label="Script"
                  value="SCRIPT"
                  data-test="reaction-action-option-script"
                />
              </v-radio-group>
            </v-row>
            <div v-if="reactionActionKind === 'NOTIFY'">
              <v-text-field
                v-model="reactionNotify"
                type="text"
                label="Notification Severity"
                placeholder="normal"
                hint="Notification levels: critical, serious, caution, normal, standby, off"
                data-test="reaction-action-notify"
              />
            </div>
            <div v-else-if="reactionActionKind === 'COMMAND'">
              <v-text-field
                v-model="reactionCommand"
                type="text"
                label="Command Input"
                placeholder="INST COLLECT with TYPE 0, DURATION 1, OPCODE 171, TEMP 0"
                prefix="cmd('"
                suffix="')"
                hint="Autonomic runs commands with cmd_no_hazardous_check"
                data-test="reaction-action-command"
              />
            </div>
            <div v-else-if="reactionActionKind === 'SCRIPT'">
              <v-card-text>
                <script-chooser @file="scriptHandler" />
                <environment-chooser v-model="reactionEnvironments" />
              </v-card-text>
            </div>
            <div v-for="(action, index) in reactionActions" :key="index">
              <v-card outlined class="mt-1 px-0">
                <v-card-title>
                  <v-icon class="mr-3">
                    {{ displayIcon(action.type) }}
                  </v-icon>
                  <span>
                    {{
                      action.value.length > 28
                        ? `${action.value.slice(0, 28)}...`
                        : action.value
                    }}
                  </span>
                  <v-spacer />
                  <v-tooltip top>
                    <template v-slot:activator="{ on, attrs }">
                      <v-icon
                        v-bind="attrs"
                        v-on="on"
                        :data-test="`reaction-action-remove-${index}`"
                        @click="removeAction(index)"
                      >
                        mdi-delete
                      </v-icon>
                    </template>
                    <span>Remove Action</span>
                  </v-tooltip>
                </v-card-title>
              </v-card>
            </div>
            <v-row class="ma-0 pa-2">
              <v-btn
                data-test="reaction-action-add-action-btn"
                :disabled="disableAddAction"
                color="primary"
                @click="addAction"
              >
                Add Action
              </v-btn>
              <v-spacer />
              <v-btn
                @click="dialogStep = 3"
                color="success"
                data-test="reaction-create-step-three-btn"
                :disabled="!reactionActions"
              >
                Continue
              </v-btn>
            </v-row>
          </v-stepper-content>

          <v-stepper-step editable step="3"> Snooze and Review </v-stepper-step>
          <v-stepper-content step="3">
            <v-row class="ma-0">
              <v-text-field
                v-model="reactionSnooze"
                data-test="reaction-snooze-input"
                label="Reaction Snooze"
                hint="Snooze in Seconds"
                type="number"
                hide-spin-buttons
              />
            </v-row>
            <v-row class="ma-0">
              <span class="ma-2 red--text" v-show="error">{{ error }}</span>
            </v-row>
            <v-row class="ma-2">
              <v-spacer />
              <v-btn
                @click="clearHandler"
                outlined
                class="mr-4"
                data-test="reaction-create-cancel-btn"
              >
                Cancel
              </v-btn>
              <v-btn
                @click.prevent="submitHandler"
                type="submit"
                color="primary"
                data-test="reaction-create-submit-btn"
                :disabled="!!error"
              >
                Ok
              </v-btn>
            </v-row>
          </v-stepper-content>
        </v-stepper>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import Api from '@openc3/tool-common/src/services/api'
import EnvironmentChooser from '@openc3/tool-common/src/components/EnvironmentChooser'
import ScriptChooser from '@openc3/tool-common/src/components/ScriptChooser'

export default {
  components: {
    EnvironmentChooser,
    ScriptChooser,
  },
  props: {
    triggers: {
      type: Object,
      required: true,
    },
    value: Boolean, // value is the default prop when using v-model
  },
  data() {
    return {
      dialogStep: 1,
      rules: {
        required: (value) => !!value || 'Required',
      },
      deadSelect: -1,
      reactionActionKind: 'NOTIFY',
      reactionSnooze: 300,
      reactionReview: true,
      reactionTriggers: [],
      reactionActions: [],
      reactionNotify: '',
      reactionCommand: '',
      reactionScript: '',
      reactionEnvironments: [],
    }
  },
  created() {},
  watch: {
    // This is mainly used when a user resets the CreateDialog
    reactionActionKind: function (newVal, oldVal) {
      if (newVal !== oldVal) {
        this.reactionNotify = ''
        this.reactionCommand = ''
        this.reactionScript = ''
        this.reactionEnvironments = []
      }
    },
  },
  computed: {
    error: function () {
      if (this.reactionSnooze === '') {
        return 'Reaction snooze can not be blank.'
      }
      return null
    },
    disableAddAction: function () {
      switch (this.reactionActionKind) {
        case 'NOTIFY':
          return !this.reactionNotify
        case 'COMMAND':
          return !this.reactionCommand
        case 'SCRIPT':
          return !this.reactionScript
        default:
          return true
      }
    },
    event: function () {
      return {
        snooze: parseFloat(this.reactionSnooze),
        review: this.reactionReview,
        triggers: this.reactionTriggers,
        actions: this.reactionActions,
      }
    },
    triggerItems: function () {
      const reactionTriggers = this.reactionTriggers
      let count = 0
      return Object.entries(this.triggers).flatMap(([group, triggerArray]) =>
        triggerArray
          .filter((t) => {
            return !reactionTriggers.find(
              (tt) => tt.name === t.name && tt.group === t.group
            )
          })
          .map((t) => {
            return {
              text: `${group}: ${t.name} (${this.expression(t)})`,
              value: { name: t.name, group },
              count: count++,
            }
          })
      )
    },
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
  },
  methods: {
    displayIcon: function (type) {
      switch (type) {
        case 'notify':
          return 'mdi-bell'
        case 'command':
          return 'mdi-code-braces'
        case 'script':
          return 'mdi-file'
      }
    },
    expression: function (trigger) {
      let left = trigger.left[trigger.left.type]
      // Format trigger dependencies like normal expressions
      if (trigger.left.type === 'trigger') {
        let found = this.triggers.find((t) => t.name === trigger.left.trigger)
        left = `(${this.expression(found)})`
      }
      let right = trigger.right[trigger.right.type]
      if (trigger.right.type === 'trigger') {
        let found = this.triggers.find((t) => t.name === trigger.right.trigger)
        right = `(${this.expression(found)})`
      }
      return `${left} ${trigger.operator} ${right}`
    },
    scriptHandler: function (event) {
      this.reactionScript = event ? event : null
    },
    resetHandler: function () {
      this.reactionActionKind = 'NOTIFY'
      this.reactionSnooze = 300
      this.reactionReview = true
      this.reactionTriggers = []
      this.reactionActions = []
      this.dialogStep = 1
    },
    clearHandler: function () {
      this.show = !this.show
      this.reactionActionKind = 'NOTIFY'
      this.reactionSnooze = 300
      this.reactionReview = true
      this.reactionTriggers = []
      this.reactionActions = []
      this.dialogStep = 1
    },
    submitHandler: function (event) {
      Api.post(`/openc3-api/autonomic/reaction`, {
        data: this.event,
      }).then((response) => {})
      this.clearHandler()
    },
    operandChanged: function (event, operand) {
      this[`${operand}Operand`] = event
    },
    addTrigger: function (event) {
      this.reactionTriggers.push(event)
      this.deadSelect = null
    },
    removeTrigger: function (trigger) {
      const triggerIndex = this.reactionTriggers.findIndex(
        (t) => t.name === trigger.name && t.group === trigger.group
      )
      this.reactionTriggers.splice(triggerIndex, triggerIndex >= 0 ? 1 : 0)
      this.deadSelect = null
    },
    addAction: function () {
      if (this.reactionNotify) {
        this.reactionActions.push({
          type: 'notify',
          value: this.reactionNotify,
        })
      } else if (this.reactionCommand) {
        this.reactionActions.push({
          type: 'command',
          value: this.reactionCommand,
        })
      } else if (this.reactionScript) {
        this.reactionActions.push({
          type: 'script',
          value: this.reactionScript,
          environment: this.reactionEnvironments,
        })
      }
      this.reactionActionKind = 'NOTIFY'
    },
    removeAction: function (index) {
      this.reactionActions.splice(index, index >= 0 ? 1 : 0)
    },
  },
}
</script>

<style scoped>
input[type='number'] {
  -moz-appearance: textfield;
}

input::-webkit-outer-spin-button,
input::-webkit-inner-spin-button {
  -webkit-appearance: none;
}
</style>
