<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" width="85vw">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span v-text="title" />
        <v-spacer />
        <div class="mx-2">
          <v-btn
            icon="mdi-download"
            variant="text"
            density="compact"
            data-test="downloadIcon"
            @click="download"
          />
        </div>
      </v-toolbar>
      <v-card-text>
        <AceEditor
          ref="aceEditor"
          :mode="languageMode"
          autofocus
          read-only
          class="editor"
        />
      </v-card-text>
      <v-card-actions class="pr-6 pb-4 pt-0">
        <v-spacer />
        <v-btn variant="flat" @click="show = !show"> Ok </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { AceEditorModes } from './ace'
import AceEditor from './AceEditor.vue'

export default {
  components: { AceEditor },
  mixins: [AceEditorModes],
  props: {
    content: {
      type: String,
      required: true,
    },
    type: {
      type: String,
      default: null,
    },
    name: {
      type: String,
      default: null,
    },
    modelValue: Boolean,
    filename: {
      type: String,
      default: null,
    },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      editor: null,
      mode: null,
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
    fileExtension() {
      return this.filename ? this.filename.split('.').pop() : 'txt'
    },
    languageMode() {
      let Mode
      switch (this.fileExtension) {
        case 'json':
          Mode = this.buildJsonMode()
          break
        case 'py':
        case 'pyi':
          Mode = this.buildPythonMode()
          break
        case 'md':
          Mode = this.buildMarkdownMode()
          break
        default:
          // Most of the COSMOS text files are best display in Ruby
          // This includes Rakefiles, Gemfiles, etc.
          Mode = this.buildRubyMode()
          break
      }
      return new Mode()
    },
    title: function () {
      return `${this.type}: ${this.name}`
    },
  },
  mounted() {
    this.editor = this.$refs.aceEditor.editor
    if (this.fileExtension === 'json') {
      this.editor.setOptions({
        useWorker: false,
      })
    }
    this.editor.setValue(this.content)
    this.editor.clearSelection()
  },
  methods: {
    close: function () {
      this.show = !this.show
    },
    download: function () {
      const blob = new Blob([this.editor.getValue()], {
        type: 'text/plain',
      })
      // Make a link and then 'click' on it to start the download
      let filename = `${this.type.toLowerCase()}_${this.name.toLowerCase()}.json`
      if (this.filename) {
        filename = this.filename
      }
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', filename)
      link.click()
    },
  },
}
</script>

<style scoped>
.editor {
  height: 75vh;
  position: relative;
  font-size: 16px;
}

.v-textarea :deep(textarea) {
  padding: 5px;
}
</style>
