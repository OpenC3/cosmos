<!--
# Copyright 2025 OpenC3, Inc.
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
  <div class="script-editor-container">
    <v-row no-gutters align="center" class="mb-2">
      <v-btn-toggle v-model="language" mandatory density="compact" class="mr-3">
        <v-btn value="ruby" size="small">Ruby</v-btn>
        <v-btn value="python" size="small">Python</v-btn>
      </v-btn-toggle>
      <v-spacer />
      <v-btn
        icon="mdi-download"
        variant="text"
        density="compact"
        title="Download"
        data-test="script-editor-download"
        @click="downloadContent"
      />
    </v-row>
    <v-row no-gutters class="mb-2">
      <pre
        ref="editor"
        class="script-editor"
        :style="{ height: height, width: '100%' }"
        @contextmenu.prevent="showContextMenu"
      ></pre>
      <v-menu v-model="contextMenu" :target="[menuX, menuY]">
        <v-list>
          <v-list-item
            title="Toggle Vim mode"
            prepend-icon="extras:vim"
            @click="toggleVimMode"
          />
        </v-list>
      </v-menu>
    </v-row>
    <v-row no-gutters>
      <span class="text-caption text-grey">
        Ctrl-space brings up autocomplete.
      </span>
    </v-row>
  </div>
</template>

<script>
import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/mode-ruby'
import 'ace-builds/src-min-noconflict/mode-python'
import 'ace-builds/src-min-noconflict/theme-twilight'
import 'ace-builds/src-min-noconflict/ext-language_tools'
import 'ace-builds/src-min-noconflict/ext-searchbox'
import { AceEditorModes, AceEditorUtils } from './ace'
import { CmdCompleter, TlmCompleter } from '../tools/scriptrunner/autocomplete'

export default {
  mixins: [AceEditorModes],
  props: {
    modelValue: {
      type: String,
      default: '',
    },
    height: {
      type: String,
      default: '300px',
    },
    filename: {
      type: String,
      default: 'script',
    },
  },
  emits: ['update:modelValue'],
  data() {
    return {
      editor: null,
      language: AceEditorUtils.getDefaultScriptingLanguage() || 'ruby',
      rubyMode: null,
      pythonMode: null,
      contextMenu: false,
      menuX: 0,
      menuY: 0,
    }
  },
  watch: {
    modelValue(newValue) {
      if (this.editor && this.editor.getValue() !== newValue) {
        this.editor.setValue(newValue)
        this.editor.clearSelection()
      }
    },
    language(newValue) {
      if (this.editor) {
        if (newValue === 'python') {
          this.editor.session.setMode(this.pythonMode)
        } else {
          this.editor.session.setMode(this.rubyMode)
        }
      }
    },
  },
  mounted() {
    this.initEditor()
  },
  beforeUnmount() {
    if (this.editor) {
      this.editor.destroy()
      this.editor.container.remove()
    }
  },
  methods: {
    initEditor() {
      this.editor = ace.edit(this.$refs.editor)
      this.editor.setTheme('ace/theme/twilight')

      // Build modes using the mixin methods
      const RubyMode = this.buildRubyMode()
      const PythonMode = this.buildPythonMode()
      this.rubyMode = new RubyMode()
      this.pythonMode = new PythonMode()

      // Set initial mode based on language
      if (this.language === 'python') {
        this.editor.session.setMode(this.pythonMode)
      } else {
        this.editor.session.setMode(this.rubyMode)
      }

      this.editor.session.setTabSize(2)
      this.editor.session.setUseWrapMode(true)
      this.editor.$blockScrolling = Infinity
      this.editor.setOption('enableBasicAutocompletion', true)
      this.editor.setOption('enableLiveAutocompletion', true)
      this.editor.completers = [new CmdCompleter(), new TlmCompleter()]
      this.editor.setHighlightActiveLine(false)
      this.editor.setValue(this.modelValue)
      this.editor.clearSelection()
      AceEditorUtils.applyVimModeIfEnabled(this.editor)
      this.editor.focus()

      this.editor.session.on('change', () => {
        this.$emit('update:modelValue', this.editor.getValue())
      })
    },
    getValue() {
      return this.editor ? this.editor.getValue() : this.modelValue
    },
    toggleVimMode() {
      AceEditorUtils.toggleVimMode(this.editor)
    },
    showContextMenu(event) {
      this.menuX = event.pageX
      this.menuY = event.pageY
      this.contextMenu = true
    },
    downloadContent() {
      const ext = this.language === 'python' ? '.py' : '.rb'
      const blob = new Blob([this.editor.getValue()], {
        type: 'text/plain',
      })
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', `${this.filename}${ext}`)
      link.click()
    },
  },
}
</script>

<style scoped>
.script-editor-container {
  width: 100%;
}

.script-editor {
  width: 100%;
  position: relative;
  font-size: 16px;
}
</style>
