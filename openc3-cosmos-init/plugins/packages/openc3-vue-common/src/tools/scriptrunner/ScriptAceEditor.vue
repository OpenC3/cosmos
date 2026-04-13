<!--
# Copyright 2026, OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div class="ace-editor-container">
    <pre
      ref="editorElement"
      class="editor"
      @contextmenu.prevent="displayContextMenu"
    ></pre>
    <v-menu
      v-if="showContextMenu"
      v-model="contextMenuVisible"
      :target="[menuX, menuY]"
    >
      <v-list>
        <v-list-item
          :title="currentLineHasCommand ? 'Edit Command' : 'Insert Command'"
          @click="handleCommandEditor"
        />
        <v-divider />
        <v-list-item
          title="Execute Selection"
          @click="handleExecuteSelection"
        />
        <v-list-item
          :title="scriptId ? 'Goto Line' : 'Run From Line'"
          @click="handleRunFromCursor"
        />
        <v-list-item
          v-if="!scriptId"
          title="Clear Local Breakpoints"
          @click="handleClearBreakpoints"
        />
        <v-divider />
        <v-list-item
          title="Toggle Vim mode"
          prepend-icon="extras:vim"
          @click="toggleVimMode"
        />
      </v-list>
    </v-menu>
  </div>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount, watch } from 'vue'
import { buildRubyMode, buildPythonMode } from '@/components/ace/AceEditorModes'
import { AceEditorUtils } from '@/components'
import { CmdCompleter, TlmCompleter } from '@/tools/scriptrunner/autocomplete'
import { SleepAnnotator } from '@/tools/scriptrunner/annotations'
import { Api } from '@openc3/js-common/services'

const props = defineProps({
  filenameSelect: {
    type: String,
    default: null,
  },
  hideCursor: {
    type: Boolean,
    default: false,
  },
  language: {
    type: String,
    default: 'ruby',
    validator: (value) => ['ruby', 'python'].includes(value),
  },
  readOnly: {
    type: Boolean,
    default: false,
  },
  scriptId: {
    type: String,
    default: null,
  },
  showContextMenu: {
    type: Boolean,
    default: false,
  },
})

const modelValue = defineModel({ type: String, required: true })

const emit = defineEmits([
  'clearBreakpoints',
  'commandEditor',
  'ready',
  'resize',
  'save',
  'save-as',
  'save-file',
  'start',
  'tokenizer-update',
])

const editorElement = ref(null)
const editor = ref(null)
const rubyMode = ref(null)
const pythonMode = ref(null)
const sleepAnnotator = ref(null)
const contextMenuVisible = ref(false)
const menuX = ref(0)
const menuY = ref(0)
const currentLineHasCommand = ref(false)

async function keydown(event) {
  // Don't ever save if running or readonly
  if (props.scriptId || editor.value.getReadOnly()) {
    return
  }
  // NOTE: Chrome does not allow overriding Ctrl-N, Ctrl-Shift-N, Ctrl-T, Ctrl-Shift-T, Ctrl-W
  // NOTE: metaKey == Command on Mac
  if ((event.metaKey || event.ctrlKey) && event.keyCode === 'S'.charCodeAt(0)) {
    if (event.shiftKey) {
      event.preventDefault()
      emit('save-as')
    } else {
      event.preventDefault()
      emit('save-file')
    }
  }
}

onMounted(() => {
  // Build modes
  const RubyMode = buildRubyMode()
  const PythonMode = buildPythonMode()
  rubyMode.value = new RubyMode()
  pythonMode.value = new PythonMode()

  // Initialize editor
  const initialMode =
    props.language === 'python' ? pythonMode.value : rubyMode.value

  editor.value = AceEditorUtils.initializeEditor(editorElement.value, {
    mode: initialMode,
    completers: [new CmdCompleter(), new TlmCompleter()],
    vimModeSaveFn: () => {
      emit('save')
    },
    readOnly: props.readOnly,
    hideCursor: props.hideCursor,
  })

  // Set initial value if provided
  if (modelValue.value) {
    editor.value.setValue(modelValue.value, -1) // -1 moves cursor to start
  }

  // Setup sleep annotator
  sleepAnnotator.value = new SleepAnnotator(editor.value)

  // Add event listeners
  editor.value.on('guttermousedown', ($event) => {
    toggleBreakpoint($event)
  })

  editor.value.session.on('tokenizerUpdate', () => {
    emit('tokenizer-update', $event)
  })

  editor.value.session.on('change', ($event, session) => {
    sleepAnnotator.value.annotate($event, session)
    updateBreakpoints($event, session)
  })

  editor.value.container.addEventListener('keydown', keydown)
  editor.value.container.addEventListener('resize', () => emit('resize'))
  // Emit ready event with editor instance
  emit('ready', editor.value)
})

onBeforeUnmount(() => {
  if (editor.value) {
    editor.value.destroy()
    editor.value.container.remove()
  }
})

// Watch for language changes
watch(
  () => props.language,
  (newLang) => {
    if (editor.value) {
      const mode = newLang === 'python' ? pythonMode.value : rubyMode.value
      editor.value.session.setMode(mode)
    }
  },
)

// Watch for readOnly changes
watch(
  () => props.readOnly,
  (newReadOnly) => {
    if (editor.value) {
      editor.value.setReadOnly(newReadOnly)
      if (newReadOnly) {
        editor.value.renderer.$cursorLayer.element.style.display = 'none'
      } else {
        editor.value.renderer.$cursorLayer.element.style.display = null
      }
    }
  },
)

// Watch for external value changes
watch(modelValue, (newValue) => {
  if (editor.value && editor.value.getValue() !== newValue) {
    const cursorPosition = editor.value.getCursorPosition()
    editor.value.setValue(newValue, -1)
    editor.value.moveCursorToPosition(cursorPosition)
  }
})

// Context menu handlers
function displayContextMenu($event) {
  if (!props.showContextMenu) return

  menuX.value = $event.pageX
  menuY.value = $event.pageY

  // Check if the current line contains a command
  if (editor.value) {
    const position = editor.value.getCursorPosition()
    const line = editor.value.session.getLine(position.row)
    currentLineHasCommand.value = isCommandLine(line)
  }

  contextMenuVisible.value = true
}

function isCommandLine(line) {
  // Check if line contains cmd() or cmd_no_hazardous_check() or similar command patterns
  const trimmedLine = line.trim()
  // Match patterns like: cmd("...", cmd_no_hazardous_check("...", cmd_raw("...", etc.
  return /^\s*cmd(_\w+)?\s*\(/.test(trimmedLine)
}

function parseCommandFromLine(line) {
  // Extract the command string from patterns like: cmd("TARGET COMMAND with PARAM value")
  const match = line.match(/cmd(_\w+)?\s*\(\s*["'](.+?)["']\s*\)/)
  if (match) {
    return match[2] // Return the command string
  }
  return null
}

function handleCommandEditor() {
  contextMenuVisible.value = false
  if (editor.value) {
    const position = editor.value.getCursorPosition()
    const line = editor.value.session.getLine(position.row)
    const cmdString = currentLineHasCommand.value
      ? parseCommandFromLine(line)
      : null

    emit('commandEditor', {
      cmdString,
      isEditing: currentLineHasCommand.value,
      editLine: position.row,
    })
  }
}

function handleExecuteSelection() {
  contextMenuVisible.value = false
  if (editor.value) {
    const range = editor.value.getSelectionRange()
    const startRow = range.start.row + 1
    const endRow = range.end.column === 0 ? range.end.row : range.end.row + 1
    if (props.scriptId) {
      Api.post(
        `/script-api/running-script/${props.scriptId}/executewhilepaused`,
        {
          data: {
            args: [props.filenameSelect, startRow, endRow],
          },
        },
      )
    } else {
      emit('start', [null, null, startRow, endRow])
    }
  }
}

function handleRunFromCursor() {
  contextMenuVisible.value = false
  if (editor.value) {
    const position = editor.value.getCursorPosition()
    const startRow = position.row + 1
    if (props.scriptId) {
      Api.post(
        `/script-api/running-script/${props.scriptId}/executewhilepaused`,
        {
          data: {
            args: [props.filenameSelect, startRow],
          },
        },
      )
    } else {
      emit('start', [null, null, startRow])
    }
  }
}

function handleClearBreakpoints() {
  contextMenuVisible.value = false
  clearBreakpoints()
}

function toggleVimMode() {
  contextMenuVisible.value = false
  if (editor.value) {
    AceEditorUtils.toggleVimMode(editor.value)
  }
}

// Breakpoint helpers
function getBreakpointRows() {
  if (!editor.value) return []
  return editor.value.session
    .getBreakpoints()
    .map((breakpoint, row) => breakpoint && row) // [empty, 'ace_breakpoint', 'ace_breakpoint', empty] -> [empty, 1, 2, empty]
    .filter(Number.isInteger) // [empty, 1, 2, empty] -> [1, 2]
}

function toggleBreakpoint($event) {
  // Don't allow setting breakpoints while running
  if (!props.scriptId && editor.value) {
    const row = $event.getDocumentPosition().row
    if ($event.editor.session.getBreakpoints(row, 0)[row]) {
      $event.editor.session.clearBreakpoint(row)
    } else {
      $event.editor.session.setBreakpoint(row)
    }
  }
}

function clearBreakpoints() {
  if (!editor.value) return
  editor.value.session.clearBreakpoints()
}

function updateBreakpoints($event, session) {
  if ($event.lines.length <= 1) {
    return
  }
  const rowsToUpdate = getBreakpointRows().filter(
    (row) =>
      ($event.start.column === 0 && row === $event.start.row) ||
      row > $event.start.row,
  )
  let rowsToDelete = []
  let offset = 0
  switch ($event.action) {
    case 'insert':
      offset = $event.lines.length - 1
      rowsToUpdate.reverse() // shift the lower ones down out of the way first
      break
    case 'remove':
      offset = -$event.lines.length + 1
      rowsToDelete = Array.from(
        { length: $event.lines.length },
        (_, i) => i + $event.start.row,
      )
      break
  }
  rowsToUpdate.forEach((row) => {
    session.clearBreakpoint(row)
    if (!rowsToDelete.includes(row)) {
      session.setBreakpoint(row + offset)
    }
  })
}

function restoreBreakpoints(breakpoints) {
  if (!editor.value || !breakpoints) return
  editor.value.session.clearBreakpoints()
  breakpoints.forEach((breakpoint) => {
    editor.value.session.setBreakpoint(breakpoint)
  })
}

// Expose editor instance and utility methods
defineExpose({
  editor,
  setValue: (value, cursorPos = -1) => {
    editor.value?.setValue(value, cursorPos)
  },
  getValue: () => {
    return editor.value?.getValue() || ''
  },
  clearSelection: () => {
    editor.value?.clearSelection()
  },
  resize: () => {
    editor.value?.resize()
  },
  toggleVimMode,
  getBreakpointRows,
  restoreBreakpoints,
  clearBreakpoints,
})
</script>

<style scoped>
.ace-editor-container {
  width: 100%;
  height: 100%;
  position: relative;
}

.editor {
  width: 100%;
  height: 100%;
  margin: 0;
}
</style>
