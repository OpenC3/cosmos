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
# All changes Copyright 2025, OpenC3, Inc.
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
        <pre ref="editor" class="editor"></pre>
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

export default {
  mixins: [AceEditorModes],
  props: {
    content: {
      type: String,
      required: true,
    },
    type: String,
    name: String,
    modelValue: Boolean,
    filename: {
      type: String,
      required: false,
    },
  },
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
    title: function () {
      return `${this.type}: ${this.name}`
    },
  },
  mounted() {
    this.editor = ace.edit(this.$refs.editor)
    this.editor.setTheme('ace/theme/twilight')
    let languageMode = null
    const fileExtension = this.filename ? this.filename.split('.').pop() : 'txt'
    switch (fileExtension) {
      case 'json':
        const JsonMode = this.buildJsonMode()
        languageMode = new JsonMode()
        this.editor.setOptions({
          useWorker: false,
        })
        break
      case 'py':
      case 'pyi':
        const PythonMode = this.buildPythonMode()
        languageMode = new PythonMode()
        break
      case 'md':
        const MarkdownMode = this.buildMarkdownMode()
        languageMode = new MarkdownMode()
        break
      default:
        // Most of the COSMOS text files are best display in Ruby
        // This includes Rakefiles, Gemfiles, etc.
        const RubyMode = this.buildRubyMode()
        languageMode = new RubyMode()
        break
    }
    this.editor.session.setMode(languageMode)
    this.editor.session.setUseWrapMode(true)
    this.editor.$blockScrolling = Infinity
    this.editor.setHighlightActiveLine(false)
    this.editor.setValue(this.content)
    this.editor.clearSelection()
    this.editor.focus()
    this.editor.setReadOnly(true)
  },
  beforeUnmount() {
    if (this.editor) {
      this.editor.destroy()
    }
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
