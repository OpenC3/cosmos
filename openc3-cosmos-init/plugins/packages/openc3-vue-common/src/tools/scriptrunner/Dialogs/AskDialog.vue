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
  <v-dialog persistent v-model="show" width="600">
    <v-card>
      <v-form v-model="valid" v-on:submit.prevent="submitHandler">
        <v-toolbar height="24">
          <v-spacer />
          <span> User Input Required </span>
          <v-spacer />
        </v-toolbar>
        <div class="pa-2">
          <v-card-text>
            <div class="question">{{ question }}</div>
            <v-text-field v-model="inputValue" autofocus data-test="ask-value-input"
              :type="password ? 'password' : 'text'" :rules="rules" />
          </v-card-text>
        </div>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn @click="cancelHandler" variant="outlined" data-test="ask-cancel">
            Cancel
          </v-btn>
          <v-btn @click.prevent="submitHandler" variant="flat" type="submit" data-test="ask-ok" :disabled="!valid">
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
    question: {
      type: String,
      required: true,
    },
    default: {
      type: String,
      default: null,
    },
    password: {
      type: Boolean,
      default: false,
    },
    answerRequired: {
      type: Boolean,
      default: true,
    },
    modelValue: Boolean,
  },
  data() {
    return {
      inputValue: '',
      valid: false,
      rules: [(v) => !!v || 'Required'],
    }
  },
  created() {
    if (this.default) {
      this.valid = true
      this.inputValue = this.default
    }
    if (this.answerRequired === false) {
      this.valid = true
      this.rules = [(v) => true]
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
      this.$emit('response', this.inputValue)
    },
    cancelHandler: function () {
      this.$emit('response', 'Cancel')
    },
  },
}
</script>

<style lang="scss" scoped>
.question {
  font-size: 1rem;
  white-space: pre-line;
}
</style>
