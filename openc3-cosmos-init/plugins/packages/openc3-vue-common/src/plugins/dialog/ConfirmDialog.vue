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
  <v-app>
    <v-dialog v-model="show" width="600">
      <v-card>
        <v-toolbar height="24">
          <v-spacer />
          <span> {{ params.title }} </span>
          <v-spacer />
        </v-toolbar>
        <v-card-text class="mt-4 pa-3">
          <v-icon v-if="params.validateText" class="mr-2"> mdi-alert </v-icon>
          <span v-if="params.html" v-html="sanitizedText"></span>
          <span v-else>{{ sanitizedText }}</span>
          <div v-if="params.validateText" class="validate mt-4">
            Enter {{ params.validateText }} to confirm!
            <v-text-field
              v-model="validationText"
              variant="solo"
              density="compact"
              single-line
              :rules="[rules.required, rules.match]"
              data-test="confirm-dialog-validate"
            />
          </div>
        </v-card-text>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn
            v-if="params.cancelText"
            variant="outlined"
            :data-test="dataTestCancel"
            @click="cancel"
          >
            {{ params.cancelText }}
          </v-btn>
          <v-btn
            variant="flat"
            :color="params.okClass"
            :data-test="dataTestOk"
            @click="ok"
          >
            {{ params.okText }}
          </v-btn>
        </v-card-actions>
      </v-card>
    </v-dialog>
  </v-app>
</template>

<script>
import DOMPurify from 'dompurify'
export default {
  data: function () {
    return {
      show: false,
      params: {
        title: 'Title',
        text: 'The text that is displayed',
        okText: 'Ok',
        okClass: 'primary',
        validateText: 'CONFIRM',
        cancelText: 'Cancel',
        html: false,
      },
      resolve: null,
      reject: null,
      validationText: null,
      rules: {
        required: (value) => !!value || 'Required.',
        match: (value) => {
          return value === this.params.validateText || 'Value mismatch.'
        },
      },
    }
  },
  computed: {
    dataTestOk: function () {
      return `confirm-dialog-${this.params.okText.toLowerCase()}`
    },
    dataTestCancel: function () {
      return `confirm-dialog-${this.params.cancelText.toLowerCase()}`
    },
    sanitizedText: function () {
      return DOMPurify.sanitize(this.params.text)
    },
  },
  methods: {
    dialog: function (params, resolve, reject) {
      this.params = params
      this.show = true
      this.resolve = resolve
      this.reject = reject
    },
    ok: function () {
      if (
        !this.params.validateText ||
        this.params.validateText === this.validationText
      ) {
        this.show = false
        this.resolve(true)
        this.refresh()
      }
    },
    cancel: function () {
      this.show = false
      this.reject(true)
      this.refresh()
    },
    refresh: function () {
      this.validationText = ''
    },
  },
}
</script>

<style scoped>
.validate {
  color: #ff5252;
}
</style>
