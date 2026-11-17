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
import { onBeforeUnmount, onMounted, shallowRef, useTemplateRef } from 'vue'

// Wraps ace.edit. Class, style and listeners fall through to the <pre>.
// Parents get the Ace instance from `ref.editor` once mounted (or via the
// `ready` event) and configure modes, options and content themselves.
const emit = defineEmits(['ready'])
const editorRef = useTemplateRef('editor')
const editor = shallowRef(null)

onMounted(() => {
  editor.value = ace.edit(editorRef.value)
  editor.value.setTheme('ace/theme/twilight')
  editor.value.setHighlightActiveLine(false)
  editor.value.session.setTabSize(2)
  editor.value.session.setUseWrapMode(true)
  emit('ready', editor.value)
})

onBeforeUnmount(() => {
  if (editor.value) {
    editor.value.destroy()
    editor.value.container.remove()
    editor.value = null
  }
})

defineExpose({
  editor,
})
</script>
