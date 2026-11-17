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
  <pre ref="editor"></pre>
</template>

<script setup>
import * as ace from 'ace-builds'
import 'ace-builds/src-min-noconflict/theme-twilight'
import { AceEditorUtils } from './ace'
import {
  onBeforeUnmount,
  onMounted,
  shallowRef,
  toRaw,
  useTemplateRef,
  watch,
} from 'vue'

// Wraps ace.edit. Class, style and listeners fall through to the <pre>.
// Parents get the Ace instance from `ref.editor` once mounted (or via the
// `ready` event) and configure modes, options and content themselves.
const props = defineProps({
  // Ace mode: a mode path string ('ace/mode/ruby') or a mode instance
  mode: {
    type: [String, Object],
    default: null,
  },
  readOnly: {
    type: Boolean,
    default: false,
  },
  // Use vim keybindings when the user has enabled vim mode (a global setting
  // stored in localStorage and toggled with toggleVim)
  vim: {
    type: Boolean,
    default: false,
  },
  // Called for :w in vim mode. Defaults to Ace's 'save' command.
  vimSaveFn: {
    type: Function,
    default: undefined,
  },
  // Wrapping is on by default; set to turn it off
  noWrap: {
    type: Boolean,
    default: false,
  },
  // Where the cursor lands when the text is set. 'start' also leaves the view
  // scrolled to the top, 'end' to the bottom.
  cursor: {
    type: String,
    default: 'end',
    validator: (value) => ['start', 'end'].includes(value),
  },
  // Focus the editor once mounted
  autofocus: {
    type: Boolean,
    default: false,
  },
})
// The editor text. Leave undefined to manage content yourself.
const model = defineModel({ type: String, default: undefined })
const emit = defineEmits(['ready'])
const editorRef = useTemplateRef('editor')
const editor = shallowRef(null)

// toRaw because mode instances held in parent data are reactive proxies
function applyMode() {
  if (editor.value && props.mode) {
    editor.value.session.setMode(toRaw(props.mode))
  }
}

watch(() => props.mode, applyMode)

function setText(value) {
  editor.value.setValue(value, props.cursor === 'start' ? -1 : 1)
}
watch(model, (value) => {
  if (
    editor.value &&
    value !== undefined &&
    value !== editor.value.getValue()
  ) {
    setText(value)
  }
})
watch(
  () => props.noWrap,
  (value) => editor.value?.session.setUseWrapMode(!value),
)
watch(
  () => props.readOnly,
  (value) => editor.value?.setReadOnly(value),
)

onMounted(() => {
  editor.value = ace.edit(editorRef.value)
  editor.value.setTheme('ace/theme/twilight')
  editor.value.setHighlightActiveLine(false)
  editor.value.session.setTabSize(2)
  editor.value.session.setUseWrapMode(!props.noWrap)
  applyMode()
  if (props.vim) {
    AceEditorUtils.applyVimModeIfEnabled(editor.value, {
      saveFn: props.vimSaveFn,
    })
  }
  editor.value.setReadOnly(props.readOnly)
  if (model.value !== undefined) {
    setText(model.value)
  }
  // Attached after the initial value so mounting doesn't emit
  editor.value.session.on('change', () => {
    model.value = editor.value.getValue()
  })
  if (props.autofocus) {
    editor.value.focus()
  }
  emit('ready', editor.value)
})

onBeforeUnmount(() => {
  if (editor.value) {
    editor.value.destroy()
    editor.value.container.remove()
    editor.value = null
  }
})

function toggleVim() {
  AceEditorUtils.toggleVimMode(editor.value)
}

defineExpose({
  editor,
  toggleVim,
})
</script>
