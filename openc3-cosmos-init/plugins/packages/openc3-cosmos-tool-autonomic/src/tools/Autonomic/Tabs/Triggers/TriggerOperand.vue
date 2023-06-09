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
    <v-select
      v-model="operandType"
      label="Operand Type"
      class="mt-1"
      :data-test="`trigger-operand-${order}-type`"
      :items="operandTypes"
    />
    <div v-if="operandType === 'ITEM'">
      <v-row class="ma-0">
        <v-radio-group
          v-model="valueType"
          class="px-2"
          row
          @change="valueTypeSelected"
        >
          <v-radio
            label="RAW"
            value="RAW"
            :data-test="`trigger-operand-${order}-raw`"
          />
          <v-radio
            label="CONVERTED"
            value="CONVERTED"
            :data-test="`trigger-operand-${order}-converted`"
          />
          <v-radio
            label="FORMATTED"
            value="FORMATTED"
            :data-test="`trigger-operand-${order}-formatted`"
          />
          <v-radio
            label="WITH_UNITS"
            value="WITH_UNITS"
            :data-test="`trigger-operand-${order}-with-units`"
          />
        </v-radio-group>
      </v-row>
      <target-packet-item-chooser
        vertical
        choose-item
        @on-set="itemSelected"
        :initialTargetName="targetName"
        :initialPacketName="packetName"
        :initialItemName="itemName"
      />
    </div>
    <div v-if="operandType === 'FLOAT'">
      <v-text-field
        label="Input Float Value"
        type="number"
        :data-test="`trigger-operand-${order}-float`"
        :rules="[rules.required]"
        :value="floatValue"
        @change="floatSelected"
      />
    </div>
    <div v-if="operandType === 'STRING'">
      <v-text-field
        label="Input String Value"
        type="string"
        :data-test="`trigger-operand-${order}-string`"
        :rules="[rules.required]"
        :value="stringValue"
        @change="stringSelected"
      />
    </div>
    <div v-if="operandType === 'REGEX'">
      <v-text-field
        label="Input Regular Expression"
        type="string"
        :data-test="`trigger-operand-${order}-regex`"
        :rules="[rules.required]"
        :value="regexValue"
        @change="regexSelected"
      />
    </div>
    <div v-if="operandType === 'LIMIT'">
      <v-select
        v-model="limitColor"
        label="Limit Color"
        class="mt-1"
        :data-test="`trigger-operand-${order}-color`"
        :items="limitColors"
        @change="limitSelected"
      />
      <v-select
        v-model="limitType"
        class="mt-1"
        label="Limit Type"
        :data-test="`trigger-operand-${order}-limit`"
        :items="limitTypes"
        @change="limitSelected"
      />
    </div>
    <div v-if="operandType === 'TRIGGER'">
      <v-select
        class="mt-3"
        label="Dependent Trigger"
        :data-test="`trigger-operand-${order}-trigger`"
        :items="triggerItems"
        @change="triggerSelected"
      />
    </div>
    <div v-if="operandType === ''">
      <v-row class="ma-0">
        <span class="ma-2 red--text">
          To continue select an operand type.
        </span>
      </v-row>
    </div>
  </div>
</template>

<script>
import TargetPacketItemChooser from '@openc3/tool-common/src/components/TargetPacketItemChooser'

export default {
  components: {
    TargetPacketItemChooser,
  },
  props: {
    initOperand: {
      type: Object,
    },
    leftOperand: {
      type: Object,
    },
    operator: {
      type: Object,
    },
    value: {
      type: String,
      required: true,
    },
    triggers: {
      type: Array,
      required: true,
    },
    order: {
      type: String,
      required: true,
    },
  },
  data() {
    return {
      api: null,
      limitType: '',
      limitColor: '',
      operandType: '',
      floatValue: null,
      stringValue: '',
      regexValue: '',
      targetName: '',
      packetName: '',
      itemName: '',
      valueType: 'CONVERTED',
      operand: {},
      rules: {
        required: (value) => !!value || 'Required',
      },
    }
  },
  created() {
    if (this.initOperand) {
      this.operandType = this.initOperand.type.toUpperCase()
      switch (this.operandType) {
        case 'ITEM':
          this.targetName = this.initOperand.target
          this.packetName = this.initOperand.packet
          this.itemName = this.initOperand.item
          this.valueType = this.initOperand.valueType
          break
        case 'LIMIT':
          let parts = this.initOperand.limit.split('_')
          this.limitColor = parts[0]
          this.limitType = parts[1]
        case 'FLOAT':
          this.floatValue = this.initOperand.float
          break
        case 'STRING':
          this.stringValue = this.initOperand.string
        case 'REGEX':
          this.regexValue = this.initOperand.regex
          break
      }
    }
  },
  computed: {
    kind: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
    limitColors: function () {
      return ['RED', 'YELLOW', 'GREEN', 'BLUE']
    },
    limitTypes: function () {
      return [
        { text: '', value: '' },
        { text: 'LOW', value: 'LOW' },
        { text: 'HIGH', value: 'HIGH' },
      ]
    },
    operandTypes: function () {
      if (this.order === 'left') {
        return [
          { text: 'Telemetry Item', value: 'ITEM' },
          { text: 'Existing Trigger', value: 'TRIGGER' },
        ]
      } else if (this.leftOperand) {
        if (this.leftOperand.type === 'trigger') {
          return [{ text: 'Existing Trigger', value: 'TRIGGER' }]
        } else {
          return [
            { text: 'Telemetry Item', value: 'ITEM' },
            { text: 'Telemetry Limits State', value: 'LIMIT' },
            { text: 'Existing Trigger', value: 'TRIGGER' },
            { text: 'Value', value: 'FLOAT' },
            { text: 'String', value: 'STRING' },
            { text: 'Regular Expression', value: 'REGEX' },
          ]
        }
      } else {
        return []
      }
    },
    triggerItems: function () {
      let filtered = this.triggers
      // If the leftOperand was given (this is the right)
      // filter out the left since it was already chosen
      if (this.leftOperand) {
        filtered = this.triggers.filter(
          (t) => t.name !== this.leftOperand.trigger
        )
      }
      return filtered.map((t) => {
        return { text: `${this.displayTrigger(t)}`, value: t.name }
      })
    },
  },
  watch: {
    // This is mainly used when a user resets the CreateDialog
    kind: {
      immediate: true,
      handler: function (newVal, oldVal) {
        if (newVal === '') {
          this.operandType = ''
        }
      },
    },
    // This updates kind and will reset the operand if the operandType changes
    operandType: {
      immediate: true,
      handler: function (newVal, oldVal) {
        if (newVal === 'FLOAT' && !this.kind) {
          this.kind = 'FLOAT'
        } else if (newVal === 'LIMIT' && !this.kind) {
          this.kind = 'LIMIT'
        } else if (newVal === 'STRING' && !this.kind) {
          this.kind = 'STRING'
        } else if (newVal === 'REGEX' && !this.kind) {
          this.kind = 'REGEX'
        } else if (newVal === 'TRIGGER' && !this.kind) {
          this.kind = 'TRIGGER'
        }
        if (newVal !== oldVal) {
          this.operand = {}
        }
      },
    },
    // When the operand changes emit the new Value
    operand: {
      immediate: true,
      handler: function (newVal, oldVal) {
        // Only emit if this is a real value with the type set
        if (newVal.type) {
          this.$emit('set', newVal)
        }
      },
    },
    // Watch the operator and if it changes and the left is a trigger
    // then the right can automatically populate the type as trigger
    operator: {
      immediate: true,
      handler: function (newVal, oldVal) {
        if (this.leftOperand && this.leftOperand.type === 'trigger') {
          this.operandType = 'TRIGGER'
        }
      },
    },
  },
  methods: {
    displayTrigger: function (trigger) {
      return `${trigger.name} (${trigger.left[trigger.left.type]} ${
        trigger.operator
      } ${trigger.right[trigger.right.type]})`
    },
    valueTypeSelected: function (event) {
      this.operand = {
        ...this.operand,
        valueType: event,
      }
    },
    itemSelected: function (event) {
      this.operand = {
        type: 'item',
        target: event.targetName,
        packet: event.packetName,
        item: event.itemName,
        valueType: event.valueType,
      }
    },
    floatSelected: function (event) {
      this.operand = {
        type: 'float',
        float: parseFloat(event),
      }
    },
    stringSelected: function (event) {
      this.operand = {
        type: 'string',
        string: event,
      }
    },
    regexSelected: function (event) {
      this.operand = {
        type: 'regex',
        regex: event,
      }
    },
    limitSelected: function (event) {
      this.operand = {
        type: 'limit',
        limit: `${this.limitColor}_${this.limitType}`,
      }
    },
    triggerSelected: function (event) {
      this.operand = {
        type: 'trigger',
        trigger: event,
      }
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
