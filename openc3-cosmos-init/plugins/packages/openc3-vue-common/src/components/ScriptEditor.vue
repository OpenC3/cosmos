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
      <AceEditor
        ref="aceEditor"
        autofocus
        :completers="completers"
        :model-value="modelValue"
        vim
        :mode="language"
        class="script-editor"
        :style="{ height: height, width: '100%' }"
        @update:model-value="$emit('update:modelValue', $event)"
        @contextmenu.prevent="showContextMenu"
      />
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
import AceEditor from './AceEditor.vue'
import { AceEditorUtils } from './ace'
import { CmdCompleter, TlmCompleter } from '../tools/scriptrunner/autocomplete'

export default {
  components: { AceEditor },
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
      contextMenu: false,
      menuX: 0,
      menuY: 0,
    }
  },
  created() {
    // Plain instance property (not in data) so Vue doesn't proxy the completers
    this.completers = [new CmdCompleter(), new TlmCompleter()]
  },
  mounted() {
    this.editor = this.$refs.aceEditor.editor
  },
  methods: {
    getValue() {
      return this.editor ? this.editor.getValue() : this.modelValue
    },
    toggleVimMode() {
      this.$refs.aceEditor.toggleVim()
    },
    showContextMenu(event) {
      this.menuX = event.pageX
      this.menuY = event.pageY
      this.contextMenu = true
    },
    downloadContent() {
      const ext = this.language === 'python' ? '.py' : '.rb'
      this.$refs.aceEditor.download(`${this.filename}${ext}`)
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
}
</style>
