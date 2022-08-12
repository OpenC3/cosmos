<!--
# Copyright 2022 OpenC3, Inc.
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
-->

<template>
  <!-- Edit dialog -->
  <v-dialog v-model="show" width="600">
    <v-card>
      <v-system-bar>
        <div class="mx-2">
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon data-test="delete-screen-icon" @click="deleteScreen">
                  mdi-delete
                </v-icon>
              </div>
            </template>
            <span> Delete Screen </span>
          </v-tooltip>
        </div>
        <v-spacer />
        <span> Edit Screen: {{ target }} {{ screen }} </span>
        <v-spacer />
        <div class="mx-2">
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon
                  data-test="download-screen-icon"
                  @click="downloadScreen"
                >
                  mdi-download
                </v-icon>
              </div>
            </template>
            <span> Download Screen </span>
          </v-tooltip>
        </div>
      </v-system-bar>
      <v-card-text>
        <v-row class="mt-3"> Upload a screen file. </v-row>
        <v-row no-gutters align="center">
          <v-col cols="3">
            <v-btn
              block
              color="success"
              @click="loadFile"
              :disabled="!file || loadingFile"
              :loading="loadingFile"
              data-test="editScreenLoadBtn"
            >
              Load
              <template v-slot:loader>
                <span>Loading...</span>
              </template>
            </v-btn>
          </v-col>
          <v-col cols="9">
            <v-file-input
              v-model="file"
              truncate-length="15"
              accept=".txt"
              label="Click to select .txt screen file."
            />
          </v-col>
        </v-row>
        <v-row> Edit the screen definition. </v-row>
        <v-row no-gutters>
          <!-- TODO: Consider putting this in the Ace Editor for line number support -->
          <v-textarea
            v-model="currentDefinition"
            rows="12"
            :rules="[rules.required]"
            data-test="screen-text-input"
          />
        </v-row>
        <v-row v-for="(error, index) in editErrors" :key="index" class="my-3">
          <span class="red--text" v-text="error"></span>
        </v-row>
        <v-row>
          <v-spacer />
          <v-btn
            @click="$emit('cancel')"
            class="mx-2"
            outlined
            data-test="editScreenCancelBtn"
          >
            Cancel
          </v-btn>
          <v-btn
            @click="$emit('save', currentDefinition)"
            class="mx-2"
            color="primary"
            data-test="editScreenSubmitBtn"
          >
            Save
          </v-btn>
        </v-row>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
export default {
  props: {
    value: Boolean, // value is the default prop when using v-model
    target: {
      type: String,
      default: '',
    },
    screen: {
      type: String,
      default: '',
    },
    definition: {
      type: String,
      default: '',
    },
    errors: {
      type: Array,
      default: () => [],
    },
  },
  data() {
    return {
      rules: {
        required: (value) => !!value || 'Required',
      },
      currentDefinition: this.definition,
      file: null,
      loadingFile: Boolean,
    }
  },
  computed: {
    editErrors: function () {
      if (this.definition === '' && !this.file) {
        return ['Input can not be blank.']
      }
      if (this.errors.length !== 0) {
        let messages = new Set()
        let result = []
        for (const error of this.errors) {
          if (messages.has(error.message)) {
            continue
          }
          let msg = `At ${error.lineNumber}: (${error.line}) ${error.message}.`
          if (error.usage) {
            msg += ` Usage: ${error.usage}`
          }
          result.push(msg)
          messages.add(error.message)
        }
        return result
      }
      return []
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
    downloadScreen: function () {
      const blob = new Blob([this.currentDefinition], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', `${this.target}_${this.screen}.txt`)
      link.click()
    },
    loadFile: function () {
      const fileReader = new FileReader()
      fileReader.readAsText(this.file)
      this.loadingFile = true
      const that = this
      fileReader.onload = function () {
        that.loadingFile = false
        that.currentDefinition = fileReader.result
        that.inputType = 'txt'
        that.file = null
      }
    },
    deleteScreen: function () {
      this.$dialog
        .confirm(`Are you sure you want to delete this screen?!`, {
          okText: 'Delete',
          cancelText: 'Cancel',
        })
        .then((dialog) => {
          this.$emit('delete')
        })
    },
  },
}
</script>

<style scoped>
.v-card {
  background-color: var(--v-tertiary-darken2);
}
.v-textarea :deep(textarea) {
  padding: 5px;
  background-color: var(--v-tertiary-darken1) !important;
}
</style>
