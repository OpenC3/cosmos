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
<!-- eslint-disable vue/no-mutating-props -->

<template>
  <div>
    <v-dialog v-model="show" width="650">
      <v-card>
        <v-system-bar>
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon
                  data-test="trigger-create-reset-icon"
                  @click="resetHandler"
                >
                  mdi-redo
                </v-icon>
              </div>
            </template>
            <span> Reset </span>
          </v-tooltip>
          <v-spacer />
          <span> Create New Trigger </span>
          <v-spacer />
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon
                  data-test="trigger-create-close-icon"
                  @click="clearHandler"
                >
                  mdi-close-box
                </v-icon>
              </div>
            </template>
            <span> Close </span>
          </v-tooltip>
        </v-system-bar>
        <v-card-text class="pa-5 pb-0">
          <v-row>
            <v-col>
              Trigger Groups spawn a microservice which process all triggers
              sequentially. If you have a high priority Trigger or overlapping
              Triggers you may want to close this dialog and create a new group.
            </v-col>
          </v-row>
          <v-row>
            <v-col>
              <v-text-field
                v-model="group"
                label="Group Name"
                data-test="group-name-input"
                dense
                outlined
                readonly
                hide-details
            /></v-col>
          </v-row>
        </v-card-text>
        <v-stepper v-model="dialogStep" vertical non-linear>
          <v-stepper-step editable step="1">
            Input Left Operand: {{ leftOperandText }}
          </v-stepper-step>
          <v-stepper-content step="1">
            <trigger-operand
              v-model="kind"
              order="left"
              :initOperand="leftOperand"
              :triggers="triggers"
              @set="(event) => operandChanged(event, 'left')"
            />
            <v-row class="ma-0">
              <v-spacer />
              <v-btn
                @click="dialogStep = 2"
                color="success"
                data-test="trigger-create-step-two-btn"
                :disabled="!leftOperand"
              >
                Continue
              </v-btn>
            </v-row>
          </v-stepper-content>

          <v-stepper-step editable step="2"> Operator </v-stepper-step>
          <v-stepper-content step="2">
            <v-row class="ma-0">
              <v-select
                v-model="operator"
                :items="operators"
                :hint="operatorHint"
                label="Operator"
                class="my-3"
                data-test="trigger-create-select-operator"
                dense
                persistent-hint
              />
            </v-row>
            <v-row class="ma-0">
              <v-spacer />
              <v-btn
                @click="dialogStep = 3"
                color="success"
                data-test="trigger-create-step-three-btn"
                :disabled="!operator"
              >
                Continue
              </v-btn>
            </v-row>
          </v-stepper-content>
          <v-stepper-step editable step="3">
            Input Right Operand: {{ rightOperandText }}
          </v-stepper-step>
          <v-stepper-content step="3">
            <v-row class="ma-0">
              <v-text-field
                v-model="evalDescription"
                label="Trigger Eval"
                data-test="trigger-create-eval"
                class="my-2"
                dense
                outlined
                readonly
                hide-details
              />
            </v-row>
            <trigger-operand
              v-model="kind"
              v-if="!itemChangeOperator"
              order="right"
              :leftOperand="leftOperand"
              :operator="operator"
              :initOperand="rightOperand"
              :triggers="triggers"
              @set="(event) => operandChanged(event, 'right')"
            />
            <v-row class="ma-0">
              <span class="ma-2 red--text" v-show="error" v-text="error" />
            </v-row>
            <v-row class="ma-2">
              <v-spacer />
              <v-btn
                @click="clearHandler"
                outlined
                class="mr-4"
                data-test="trigger-create-cancel-btn"
              >
                Cancel
              </v-btn>
              <v-btn
                @click.prevent="submitHandler"
                type="submit"
                color="primary"
                data-test="trigger-create-submit-btn"
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
import TriggerOperand from '@/tools/Autonomic/Tabs/Triggers/TriggerOperand'

export default {
  components: {
    TriggerOperand,
  },
  props: {
    group: {
      type: String,
      required: true,
    },
    trigger: {
      type: Object,
    },
    triggers: {
      type: Array,
      required: true,
    },
    value: Boolean, // value is the default prop when using v-model
  },
  data() {
    return {
      dialogStep: 1,
      kind: '',
      operator: '',
      leftOperand: null,
      rightOperand: null,
    }
  },
  created() {
    if (this.trigger) {
      this.operator = this.trigger.operator
      this.leftOperand = this.trigger.left
      this.rightOperand = this.trigger.right
    }
  },
  computed: {
    leftOperandText: function () {
      const op = this.leftOperand
      if (!op) {
        return ''
      }
      if (op.type === 'item') {
        return `${op.target} ${op.packet} ${op.item} (${op.valueType})`
      } else if (op.type === 'trigger') {
        return this.displayTrigger(op)
      }
      return op[op.type]
    },
    rightOperandText: function () {
      const op = this.rightOperand
      if (!op) {
        return ''
      }
      if (op.type === 'item') {
        return `${op.target} ${op.packet} ${op.item} (${op.valueType})`
      } else if (op.type === 'trigger') {
        return this.displayTrigger(op)
      }
      return op[op.type]
    },
    evalDescription: function () {
      if (this.operator === '') {
        return ' '
      }
      return `${this.leftOperandText} ${this.operator} ${this.rightOperandText}`
    },
    itemChangeOperator: function () {
      if (
        this.leftOperand &&
        this.leftOperand.type === 'item' &&
        (this.operator === 'CHANGES' || this.operator === 'DOES NOT CHANGE')
      ) {
        return true
      } else {
        return false
      }
    },
    operators: function () {
      if (this.leftOperand) {
        switch (this.leftOperand.type.toUpperCase()) {
          case 'ITEM':
            return [
              '==',
              '!=',
              '>',
              '<',
              '>=',
              '<=',
              'CHANGES',
              'DOES NOT CHANGE',
            ]
          case 'LIMIT':
            return ['==', '!=']
          case 'TRIGGER':
            return ['AND', 'OR']
          default:
            return []
        }
      } else return []
    },
    operatorHint: function () {
      switch (this.operator) {
        case '==':
          return 'Equals'
        case '!=':
          return 'Not equals'
        case '>':
          return 'Greater than'
        case '<':
          return 'Less than'
        case '>=':
          return 'Greater than or equals'
        case '<=':
          return 'Less than or equals'
        case 'AND':
          return 'Both triggers must be active'
        case 'OR':
          return 'Either trigger is active'
        case 'CHANGES':
          return 'Item value changes (sample to sample)'
        case 'DOES NOT CHANGE':
          return 'Item value does NOT change (sample to sample)'
      }
      return ''
    },
    event: function () {
      return {
        group: this.group,
        operator: this.operator,
        left: this.leftOperand,
        right: this.rightOperand,
      }
    },
    error: function () {
      if (this.operator === '') {
        return 'Trigger operator can not be blank.'
      }
      if (!this.leftOperand) {
        return 'Trigger left operand can not be blank.'
      }
      if (!this.rightOperand && !this.itemChangeOperator) {
        return 'Trigger right operand can not be blank.'
      }
      return null
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
    displayTrigger: function (trigger) {
      let found = this.triggers.find((t) => t.name === trigger.trigger)
      return `${found.name} (${found.left[found.left.type]} ${found.operator} ${
        found.right[found.right.type]
      })`
    },
    resetHandler: function () {
      this.kind = ''
      this.operator = ''
      this.leftOperand = null
      this.rightOperand = null
      this.dialogStep = 1
    },
    clearHandler: function () {
      this.show = !this.show
      this.resetHandler()
    },
    submitHandler(event) {
      if (this.trigger) {
        Api.put(
          `/openc3-api/autonomic/${this.group}/trigger/${this.trigger.name}`,
          {
            data: this.event,
          }
        ).then((response) => {})
      } else {
        Api.post(`/openc3-api/autonomic/${this.group}/trigger`, {
          data: this.event,
        }).then((response) => {})
      }
      this.clearHandler()
    },
    operandChanged(event, operand) {
      this[`${operand}Operand`] = event
    },
  },
}
</script>
