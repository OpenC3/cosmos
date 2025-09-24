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
# All changes Copyright 2024, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" width="700">
    <v-card>
      <v-toolbar :height="24">
        <v-spacer />
        <span> Details </span>
        <v-spacer />
      </v-toolbar>

      <v-card-title>
        {{ targetName }} {{ packetName }} {{ itemName }}
      </v-card-title>
      <v-card-subtitle>{{ details.description }}</v-card-subtitle>
      <v-card-text>
        <v-container fluid>
          <v-row v-if="type === 'tlm'" no-gutters>
            <v-col cols="5" class="label">Item Values</v-col>
            <v-col />
          </v-row>
          <v-row no-gutters>
            <v-col cols="1"></v-col>
            <v-col cols="4" class="label">Raw Value</v-col>
            <v-col>{{ rawValue }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="1"></v-col>
            <v-col cols="4" class="label">Converted Value</v-col>
            <v-col>{{ convertedValue }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="1"></v-col>
            <v-col cols="4" class="label">Formatted Value</v-col>
            <v-col>{{ formattedValue }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Bit Offset</v-col>
            <v-col>{{ details.bit_offset }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Bit Size</v-col>
            <v-col>{{ details.bit_size }}</v-col>
          </v-row>
          <v-row v-if="details.array_size" no-gutters>
            <v-col cols="5" class="label">Array Size</v-col>
            <v-col>{{ details.array_size }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Data Type</v-col>
            <v-col>{{ details.data_type }}</v-col>
          </v-row>
          <v-row v-if="type === 'cmd'" no-gutters>
            <v-col cols="5" class="label">Minimum</v-col>
            <v-col>{{ details.minimum }}</v-col>
          </v-row>
          <v-row v-if="type === 'cmd'" no-gutters>
            <v-col cols="5" class="label">Maximum</v-col>
            <v-col>{{ details.maximum }}</v-col>
          </v-row>
          <v-row v-if="type === 'cmd'" no-gutters>
            <v-col cols="5" class="label">Default</v-col>
            <v-col>{{ details.default }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Format String</v-col>
            <v-col>{{ details.format_string }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Read Conversion</v-col>
            <v-col v-if="details.read_conversion">
              Class: {{ details.read_conversion.class }}
              <br />
              Params:
              {{ details.read_conversion.params }}
            </v-col>
            <v-col v-else></v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Write Conversion</v-col>
            <v-col v-if="details.write_conversion">
              Class: {{ details.write_conversion.class }}
              <br />
              Params:
              {{ details.write_conversion.params }}
            </v-col>
            <v-col v-else></v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Id Value</v-col>
            <v-col>{{ details.id_value }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Units Full</v-col>
            <v-col>{{ details.units_full }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Units Abbr</v-col>
            <v-col>{{ details.units }}</v-col>
          </v-row>
          <v-row no-gutters>
            <v-col cols="5" class="label">Endianness</v-col>
            <v-col>{{ details.endianness }}</v-col>
          </v-row>
          <div v-if="details.states">
            <v-row no-gutters>
              <v-col cols="5" class="label">States</v-col>
              <v-col />
            </v-row>
            <v-row v-for="(state, key) in details.states" :key="key" no-gutters>
              <v-col cols="1"></v-col>
              <v-col cols="4" class="label">{{ key }}</v-col>
              <v-col>{{ state.value }}</v-col>
            </v-row>
          </div>
          <v-row v-else no-gutters>
            <v-col cols="5" class="label">States</v-col>
            <v-col>None</v-col>
          </v-row>
          <div v-if="details.limits">
            <v-row no-gutters>
              <v-col cols="5" class="label">Limits</v-col>
              <v-col></v-col>
            </v-row>
            <v-row v-for="(limit, key) in details.limits" :key="key" no-gutters>
              <v-col cols="1"></v-col>
              <v-col v-if="key === 'enabled'" cols="4" class="label"
                >Enabled</v-col
              >
              <v-switch
                v-if="key === 'enabled'"
                v-model="details.limits.enabled"
                density="compact"
                color="primary"
                class="compact-switch"
                hide-details
                @update:model-value="changeLimitsEnabled"
              ></v-switch>
              <v-col v-if="key !== 'enabled'" cols="4" class="label">{{
                key
              }}</v-col>
              <div v-if="key !== 'enabled'">{{ formatLimit(limit) }}</div>
              <v-col></v-col>
            </v-row>
          </div>
          <v-row v-else no-gutters>
            <v-col cols="5" class="label">Limits</v-col>
            <v-col>None</v-col>
          </v-row>
          <div v-if="details.meta">
            <v-row no-gutters>
              <v-col cols="5" class="label">Meta</v-col>
              <v-col></v-col>
            </v-row>
            <v-row v-for="(value, key) in details.meta" :key="key" no-gutters>
              <v-col cols="1"></v-col>
              <v-col cols="4" class="label">{{ key }}</v-col>
              <v-col>{{ value.join(', ') }}</v-col>
            </v-row>
          </div>
          <v-row v-else no-gutters>
            <v-col cols="5" class="label">Meta</v-col>
            <v-col>None</v-col>
          </v-row>
        </v-container>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  props: {
    type: {
      default: 'tlm',
      validator: function (value) {
        // The value must match one of these strings
        return ['cmd', 'tlm'].indexOf(value) !== -1
      },
    },
    targetName: String,
    packetName: String,
    itemName: String,
    modelValue: Boolean,
  },
  data() {
    return {
      details: Object,
      updater: null,
      rawValue: null,
      convertedValue: null,
      formattedValue: null,
      unitsValue: null,
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
  },
  watch: {
    // Create a watcher on value which is the indicator to display the dialog
    // If value is true we request the details from the server
    // If this is a tlm dialog we setup an interval to get the telemetry values
    modelValue: function (newValue, oldValue) {
      if (newValue) {
        this.requestDetails()
        if (this.type === 'tlm') {
          this.updater = setInterval(() => {
            this.api
              .get_tlm_values([
                `${this.targetName}__${this.packetName}__${this.itemName}__RAW`,
                `${this.targetName}__${this.packetName}__${this.itemName}__CONVERTED`,
                `${this.targetName}__${this.packetName}__${this.itemName}__FORMATTED`,
              ])
              .then((values) => {
                for (let value of values) {
                  let rawString = null
                  // Check for raw encoded strings (non-ascii)
                  if (
                    value[0]['json_class'] === 'String' &&
                    value[0]['raw'] !== undefined
                  ) {
                    rawString = value[0]['raw']
                  } else if (this.details.data_type === 'BLOCK') {
                    rawString = value[0]
                  }
                  if (rawString !== null) {
                    // Slice the number of bytes in case they added UNITS
                    // Otherwise we would render the units,
                    // e.g. UNITS of 'B' becomes 20 42 (space, B)
                    rawString = rawString.slice(
                      0,
                      parseInt(this.details.bit_size) / 8,
                    )
                    // Only display the first 64 bytes at which point ...
                    let ellipse = false
                    if (rawString.length > 64) {
                      ellipse = true
                    }
                    value[0] = Array.from(
                      rawString.slice(0, 64),
                      function (byte) {
                        // Can't really display spaces so change to 20 (hex)
                        if (byte === ' ') {
                          return '20'
                        } else {
                          return ('0' + (byte & 0xff).toString(16)).slice(-2)
                        }
                      },
                    )
                      .join(' ')
                      .toUpperCase()
                    if (ellipse) {
                      value[0] += '...'
                    }
                  }
                }
                if (
                  this.details.data_type.includes('INT') &&
                  !this.details.array_size
                ) {
                  // For INT and UINT display both dec and hex
                  this.rawValue = `${values[0][0]} (0x${values[0][0]
                    .toString(16)
                    .toUpperCase()})`
                } else {
                  this.rawValue = values[0][0]
                }
                this.convertedValue = values[1][0]
                this.formattedValue = values[2][0]
                this.unitsValue = values[3][0]
              })
          }, 1000)
        }
      } else {
        clearInterval(this.updater)
        this.updater = null
      }
    },
  },
  created() {
    this.api = new OpenC3Api()
  },
  beforeUnmount() {
    clearInterval(this.updater)
    this.updater = null
  },
  methods: {
    // This check is necessary because COSMOS 5.20 was setting limits.enabled to false
    // even if the item did not have limits. While the backend changed we still need to
    // support the old results. Thus we check if the item has limits by checking if the
    // limits.DEFAULT key exists or if any of the states have a color.
    hasLimits(details) {
      let result = false
      if (details.limits.DEFAULT) {
        result = true
      }
      if (details.states) {
        Object.getOwnPropertyNames(details.states).forEach((state) => {
          if (details.states[state].color) {
            result = true
          }
        })
      }
      return result
    },
    async requestDetails() {
      if (this.type === 'tlm') {
        await this.api
          .get_item(this.targetName, this.packetName, this.itemName)
          .then((details) => {
            this.details = details
            // If the item does not have limits explicitly null it
            // to make the check in the template easier
            if (!this.hasLimits(details)) {
              this.details.limits = null
            }
          })
      } else {
        await this.api
          .get_parameter(this.targetName, this.packetName, this.itemName)
          .then((details) => {
            this.details = details
          })
      }
    },
    async changeLimitsEnabled() {
      if (this.details.limits.enabled) {
        await this.api.enable_limits(
          this.targetName,
          this.packetName,
          this.itemName,
        )
      } else {
        await this.api.disable_limits(
          this.targetName,
          this.packetName,
          this.itemName,
        )
      }
    },
    formatLimit(limit) {
      if (limit.hasOwnProperty('green_low')) {
        return (
          'RL/' +
          limit.red_low +
          ' YL/' +
          limit.yellow_low +
          ' YH/' +
          limit.yellow_high +
          ' RH/' +
          limit.red_high +
          ' GL/' +
          limit.green_low +
          ' GH/' +
          limit.green_high
        )
      } else if (limit.hasOwnProperty('red_low')) {
        return (
          'RL/' +
          limit.red_low +
          ' YL/' +
          limit.yellow_low +
          ' YH/' +
          limit.yellow_high +
          ' RH/' +
          limit.red_high
        )
      } else {
        return limit
      }
    },
  },
}
</script>

<style scoped>
.label {
  font-weight: bold;
  text-transform: capitalize;
}

:deep(.v-input--selection-controls) {
  padding: 0px;
  margin: 0px;
}

:deep(.v-switch .v-selection-control) {
  min-height: 28px;
}
</style>
