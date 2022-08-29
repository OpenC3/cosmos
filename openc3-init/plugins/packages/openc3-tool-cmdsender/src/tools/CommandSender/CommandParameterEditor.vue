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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
-->

<template>
  <div>
    <v-text-field
      v-if="states === null"
      :value="textfieldValue"
      hide-details
      dense
      @change="handleChange"
      data-test="cmd-param-value"
    />
    <v-container v-else>
      <v-row no-gutters>
        <v-col>
          <v-overflow-btn
            :items="states"
            v-model="value.selected_state"
            @change="handleStateChange"
            item-text="label"
            item-value="value"
            label="State"
            style="primary"
            :class="stateClass()"
            hide-details
            dense
            data-test="cmd-param-select"
          />
        </v-col>
        <v-col>
          <v-text-field
            :value="stateValue"
            @change="handleChange"
            hide-details
            dense
            data-test="cmd-param-value"
          />
        </v-col>
      </v-row>
    </v-container>
  </div>
</template>

<script>
import Utilities from '@/tools/CommandSender/utilities'

export default {
  mixins: [Utilities],
  model: {
    prop: 'initialValue',
    event: 'input',
  },
  props: {
    statesInHex: {
      type: Boolean,
      default: false,
    },
    initialValue: {
      type: Object,
      default: () => ({
        val: '',
        states: null,
        selected_state: null,
        selected_state_label: '',
        manual_value: null,
        hazardous: false,
      }),
    },
  },
  data() {
    return {
      value: this.initialValue,
    }
  },
  computed: {
    textfieldValue() {
      return this.convertToString(this.value.val)
    },
    stateValue() {
      if (this.statesInHex) {
        return '0x' + this.value.val.toString(16)
      } else {
        return this.value.val
      }
    },
    states() {
      if (this.value.states != null) {
        var calcStates = []
        for (var key in this.value.states) {
          if (Object.prototype.hasOwnProperty.call(this.value.states, key)) {
            calcStates.push({
              label: key,
              value: this.value.states[key].value,
              // states which are not hazardous don't have this property set so they are undefined
              hazardous: this.value.states[key].hazardous,
            })
          }
        }
        calcStates.push({
          label: 'MANUALLY ENTERED',
          value: 'MANUALLY ENTERED',
          hazardous: undefined, // see above
        })

        // TBD pick default better (use actual default instead of just first item in list)
        return calcStates
      } else {
        return null
      }
    },
  },
  methods: {
    stateClass() {
      return this.value.hazardous ? 'hazardous mr-4' : 'mr-4'
    },
    handleChange(value) {
      this.value.val = value
      this.value.manual_value = value
      if (this.value.states) {
        var selected_state = 'MANUALLY ENTERED'
        var selected_state_label = 'MANUALLY_ENTERED'
        for (const state of this.states) {
          if (state.value === parseInt(value)) {
            selected_state = parseInt(value)
            selected_state_label = state.label
            if (state.hazardous == undefined) {
              this.value.hazardous = false
            } else {
              this.value.hazardous = true
            }
            break
          }
        }
        this.value.selected_state = selected_state
        this.value.selected_state_label = selected_state_label
      } else {
        this.value.selected_state = null
      }
      this.$emit('input', this.value)
    },

    handleStateChange(value) {
      var selected_state_label = null
      var selected_state = null
      for (var index = 0; index < this.states.length; index++) {
        if (value == this.states[index].value) {
          if (this.states[index].hazardous == undefined) {
            this.value.hazardous = false
          } else {
            this.value.hazardous = true
          }
          selected_state_label = this.states[index].label
          selected_state = value
          break
        }
      }
      this.value.selected_state_label = selected_state_label
      if (selected_state_label == 'MANUALLY ENTERED') {
        this.value.val = this.value.manual_value
        // Stop propagation of the click event so the editor stays active
        // to let the operator enter a manual value.
        // event.originalEvent.stopPropagation()
      } else {
        this.value.val = selected_state
        this.$emit('input', this.value)
      }
    },
  },
}
</script>
<style scoped>
/* This allows Value or State selection to be wider and show state names */
.container :deep(.v-select__selections) {
  width: auto;
}
.v-overflow-btn {
  margin-top: 0px;
}
.container {
  padding: 0px;
}
.hazardous :deep(.v-select__selection) {
  color: rgb(255, 220, 0);
}
</style>
