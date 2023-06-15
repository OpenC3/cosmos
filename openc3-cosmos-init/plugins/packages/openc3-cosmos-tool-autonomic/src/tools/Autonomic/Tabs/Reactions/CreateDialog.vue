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
              <div class="radio-help">
                When should the Action run? Edge only runs the action when the
                trigger transitions to active. If the trigger is currently
                active the action will not run. Level runs the action if the
                trigger is currently active.
              </div>
              <v-radio-group v-model="triggerLevel" class="px-2" row>
                <v-radio
                  label="Edge Trigger"
                  value="EDGE"
                  data-test="edge-trigger"
                />
                <v-radio
                  label="Level Trigger"
                  value="LEVEL"
                  data-test="level-trigger"
                />
              </v-radio-group>
            </v-row>
            <v-row class="ma-0">
              <v-select
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
            <v-row dense class="ma-0">
              <v-radio-group v-model="actionKind" row class="px-2">
                <v-radio
                  label="Script"
                  value="SCRIPT"
                  data-test="reaction-action-option-script"
                />
                <v-radio
                  label="Command"
                  value="COMMAND"
                  data-test="reaction-action-option-command"
                />
                <v-radio
                  label="Notify Only"
                  value="NOTIFY"
                  data-test="reaction-action-option-notify"
                />
              </v-radio-group>
            </v-row>
            <div v-if="actionKind === 'SCRIPT'">
              <v-card-text>
                <script-chooser :value="script" @file="scriptHandler" />
                <environment-chooser v-model="reactionEnvironments" />
              </v-card-text>
            </div>
            <div v-else-if="actionKind === 'COMMAND'">
              <v-text-field
                v-model="command"
                type="text"
                label="Command Input"
                placeholder="INST COLLECT with TYPE 0, DURATION 1, OPCODE 171, TEMP 0"
                prefix="cmd('"
                suffix="')"
                hint="Autonomic runs commands with cmd_no_hazardous_check"
                data-test="reaction-action-command"
              />
            </div>
            <div v-if="actionKind === 'NOTIFY'">
              <v-select
                v-model="notifySeverity"
                persistent-hint
                label="Notification Severity"
                hint="Notification when the Action runs"
                data-test="reaction-notification"
                :items="notificationTypes(true)"
              />
            </div>
            <v-select
              v-else
              v-model="notifySeverity"
              persistent-hint
              label="Optional Notification Severity"
              hint="Optionally create a notification when the Action runs"
              data-test="reaction-notification"
              :items="notificationTypes(false)"
            />
            <v-text-field
              v-model="notifyText"
              data-test="reaction-notify-text"
              label="Notification text"
            />
            <v-row class="ma-0 pa-2">
              <v-spacer />
              <v-btn
                @click="dialogStep = 3"
                color="success"
                data-test="reaction-create-step-three-btn"
                :disabled="noActionSelected"
              >
                Continue
              </v-btn>
            </v-row>
          </v-stepper-content>
          <v-stepper-step editable step="3"> Snooze and Review </v-stepper-step>
          <v-stepper-content step="3">
            <v-row class="ma-0">
              <v-text-field
                v-model="snooze"
                data-test="reaction-snooze-input"
                label="Reaction Snooze"
                hint="Seconds to wait before re-enabling the Action"
                type="number"
                hide-spin-buttons
                persistent-hint
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
    reaction: {
      type: Object,
    },
    triggers: {
      type: Object,
      required: true,
    },
    value: Boolean, // value is the default prop when using v-model
  },
  data() {
    return {
      dialogStep: 1,
      triggerLevel: 'EDGE',
      reactionTriggers: [],
      actionKind: 'SCRIPT',
      notifySeverity: 'No Notification',
      notifyText: '',
      command: '',
      script: '',
      reactionEnvironments: [],
      snooze: 300,
    }
  },
  created() {
    if (this.reaction) {
      this.actionKind = null
      this.triggerLevel = this.reaction.triggerLevel
      this.reactionTriggers = this.reaction.triggers
      this.reaction.actions.forEach((action) => {
        switch (action.type) {
          case 'script':
            this.actionKind = 'SCRIPT'
            this.script = action.value
            break
          case 'command':
            this.actionKind = 'COMMAND'
            this.command = action.value
            break
          case 'notify':
            // Only set if not already set ... we can have notify along with script and command
            if (this.actionKind === null) {
              this.actionKind = 'NOTIFY'
            }
            this.notifyText = action.value
            this.notifySeverity = action.severity
            break
        }
      })
      this.snooze = this.reaction.snooze
    }
  },
  computed: {
    error: function () {
      if (this.snooze === '') {
        return 'Reaction snooze can not be blank.'
      }
      return null
    },
    noActionSelected: function () {
      switch (this.actionKind) {
        case 'SCRIPT':
          return !this.script
        case 'COMMAND':
          return !this.command
        case 'NOTIFY':
          return !this.notifyText
        default:
          return true
      }
    },
    event: function () {
      let actions = []
      if (this.actionKind === 'SCRIPT') {
        actions.push({
          type: 'script',
          value: this.script,
          environment: this.reactionEnvironments,
        })
        if (this.notifySeverity !== 'No Notification') {
          actions.push({
            type: 'notify',
            value: this.notifyText,
            severity: this.notifySeverity,
          })
        }
      } else if (this.actionKind === 'COMMAND') {
        actions.push({
          type: 'command',
          value: this.command,
        })
        if (this.notifySeverity !== 'No Notification') {
          actions.push({
            type: 'notify',
            value: this.notifyText,
            severity: this.notifySeverity,
          })
        }
      } else {
        actions.push({
          type: 'notify',
          value: this.notifyText,
          severity: this.notifySeverity,
        })
      }
      return {
        snooze: parseFloat(this.snooze),
        triggerLevel: this.triggerLevel,
        triggers: this.reactionTriggers,
        actions: actions,
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
    notificationTypes: function (required) {
      let list = [
        'No Notification',
        'critical',
        'serious',
        'caution',
        'normal',
        'standby',
        'off',
      ]
      if (required) {
        list.shift()
      }
      return list
    },
    expression: function (trigger) {
      let left = trigger.left[trigger.left.type]
      // Format trigger dependencies like normal expressions
      if (trigger.left.type === 'trigger') {
        Object.entries(this.triggers).flatMap(([_, triggerArray]) => {
          let found = triggerArray.find((t) => t.name === trigger.left.trigger)
          left = `(${this.expression(found)})`
        })
      }
      let right = ''
      if (trigger.right) {
        right = trigger.right[trigger.right.type]
        if (trigger.right.type === 'trigger') {
          Object.entries(this.triggers).flatMap(([_, triggerArray]) => {
            let found = triggerArray.find(
              (t) => t.name === trigger.right.trigger
            )
            right = `(${this.expression(found)})`
          })
        }
      }
      return `${left} ${trigger.operator} ${right}`
    },
    scriptHandler: function (event) {
      this.script = event ? event : null
    },
    resetHandler: function () {
      this.actionKind = 'SCRIPT'
      this.snooze = 300
      this.reactionTriggers = []
      this.dialogStep = 1
    },
    clearHandler: function () {
      this.show = !this.show
      this.resetHandler()
    },
    submitHandler: function (event) {
      if (this.reaction) {
        Api.put(`/openc3-api/autonomic/reaction/${this.reaction.name}`, {
          data: this.event,
        }).then((response) => {})
      } else {
        Api.post(`/openc3-api/autonomic/reaction`, {
          data: this.event,
        }).then((response) => {})
      }
      this.clearHandler()
    },
    operandChanged: function (event, operand) {
      this[`${operand}Operand`] = event
    },
    addTrigger: function (event) {
      this.reactionTriggers.push(event)
    },
    removeTrigger: function (trigger) {
      const triggerIndex = this.reactionTriggers.findIndex(
        (t) => t.name === trigger.name && t.group === trigger.group
      )
      this.reactionTriggers.splice(triggerIndex, triggerIndex >= 0 ? 1 : 0)
    },
  },
}
</script>

<style scoped>
.radio-help {
  font-size: 16px;
  line-height: 16px;
}

input[type='number'] {
  -moz-appearance: textfield;
}

input::-webkit-outer-spin-button,
input::-webkit-inner-spin-button {
  -webkit-appearance: none;
}
</style>
