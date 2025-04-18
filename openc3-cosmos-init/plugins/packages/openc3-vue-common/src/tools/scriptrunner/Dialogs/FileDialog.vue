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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" persistent width="600">
    <v-card>
      <v-form v-model="valid" @submit.prevent="submitHandler">
        <v-toolbar height="24">
          <v-spacer />
          <span> File Dialog </span>
          <v-spacer />
        </v-toolbar>
        <div class="pa-2">
          <v-card-text>
            <v-row>
              <span class="title">{{ title }}</span>
            </v-row>
            <v-row v-if="message">
              <span
                class="ma-3"
                style="white-space: pre-line"
                v-text="message"
              />
            </v-row>
            <v-row class="my-1">
              <v-file-input
                v-model="inputValue"
                label="Choose File"
                :rules="rules"
                autofocus
                data-test="file-input"
                :accept="filter"
                small-chips
                :multiple="multiple"
              />
            </v-row>
          </v-card-text>
        </div>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn
            variant="outlined"
            data-test="file-cancel"
            @click="cancelHandler"
          >
            Cancel
          </v-btn>
          <v-btn
            variant="flat"
            type="submit"
            data-test="file-ok"
            :disabled="!valid"
            @click.prevent="submitHandler"
          >
            Ok
          </v-btn>
        </v-card-actions>
      </v-form>
    </v-card>
  </v-dialog>
</template>

<script>
export default {
  props: {
    title: {
      type: String,
      required: true,
    },
    message: {
      type: String,
      default: null,
    },
    filter: {
      type: String,
      default: '*',
    },
    multiple: {
      type: Boolean,
      default: false,
    },
    modelValue: Boolean,
  },
  data() {
    return {
      inputValue: null,
      valid: null,
      rules: [
        (value) => {
          if (this.multiple) {
            return value.length != 0 || 'Required'
          } else {
            return !!value || 'Required'
          }
        },
      ],
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
  methods: {
    submitHandler: function () {
      // Ensure we send back an array of file names even in the single case
      // to make it easier to deal with a consistent result
      if (!Array.isArray(this.inputValue)) {
        this.inputValue = [this.inputValue]
      }
      this.$emit('response', this.inputValue)
    },
    cancelHandler: function () {
      this.$emit('response', 'Cancel')
    },
  },
}
</script>

<style scoped>
.title {
  font-size: 1.125rem;
  font-weight: bold;
  padding-bottom: 5px;
}
</style>
