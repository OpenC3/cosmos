<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <!-- Edit dialog -->
  <v-dialog
    v-model="show"
    persistent
    width="75vw"
    @keydown.esc="$emit('cancel')"
  >
    <v-card>
      <v-toolbar height="24">
        <v-btn
          class="mx-2"
          icon="mdi-delete"
          variant="text"
          density="compact"
          data-test="delete-screen-icon"
          @click="deleteScreen"
        />
        <v-spacer />
        <span> Edit Screen: {{ target }} {{ screen }} </span>
        <v-spacer />
      </v-toolbar>
      <v-card-text style="max-height: 90vh">
        <screen-editor
          ref="screenEditor"
          v-model="editorContent"
          :keywords="keywords"
          :filename="`${screen.toLowerCase()}.txt`"
          height="45vh"
        />
        <!-- Make the error messages a max height and scrollable -->
        <v-row class="ma-3" style="max-height: 120px; overflow-y: auto">
          <div v-for="(error, index) in editErrors" :key="index">
            <span class="text-red" v-text="error" />
          </div>
        </v-row>
        <v-row class="mt-3">
          <v-spacer />
          <v-btn
            class="mx-2"
            variant="outlined"
            data-test="edit-screen-cancel"
            @click="$emit('cancel')"
          >
            Cancel
          </v-btn>
          <v-btn
            class="mx-2"
            color="primary"
            data-test="edit-screen-save"
            @click="$emit('save', editorContent)"
          >
            Save
          </v-btn>
        </v-row>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
import ScreenEditor from './ScreenEditor.vue'

export default {
  components: {
    ScreenEditor,
  },
  props: {
    modelValue: Boolean,
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
    keywords: {
      type: Array,
      default: () => [],
    },
    errors: {
      type: Array,
      default: () => [],
    },
  },
  emits: ['cancel', 'delete', 'save', 'update:modelValue'],
  data() {
    return {
      editorContent: this.definition,
    }
  },
  computed: {
    editErrors: function () {
      if (this.editorContent === '') {
        return ['Input can not be blank.']
      }
      if (this.errors.length !== 0) {
        let messages = new Set()
        let result = []
        const sortedErrors = this.errors.toSorted(
          (a, b) => a.lineNumber - b.lineNumber,
        )
        for (const error of sortedErrors) {
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
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
  },
  watch: {
    definition(newValue) {
      this.editorContent = newValue
    },
  },
  methods: {
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
