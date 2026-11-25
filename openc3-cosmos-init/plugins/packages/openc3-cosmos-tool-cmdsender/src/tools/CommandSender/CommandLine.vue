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
  <!-- Paste and keys are handled here, on their way up from the textarea -->
  <div
    class="cs-line"
    data-test="command-line-panel"
    @paste="onPaste"
    @keydown="onKeydown"
  >
    <v-textarea
      ref="input"
      v-model="text"
      label="Script"
      :placeholder="placeholder"
      rows="1"
      max-rows="8"
      auto-grow
      density="compact"
      variant="outlined"
      autocomplete="off"
      spellcheck="false"
      persistent-placeholder
      :persistent-hint="true"
      :hint="hint"
      :error-messages="error"
      :loading="busy || loading"
      :class="['cs-line-input', { 'cs-line-dirty': dirty }]"
      data-test="command-line"
      @update:model-value="markEdited"
      @update:focused="focused = $event"
    >
      <template #append-inner>
        <v-btn
          :icon="copied ? 'mdi-check' : 'mdi-content-copy'"
          size="small"
          variant="text"
          density="comfortable"
          :disabled="!text.trim()"
          :title="copied ? 'Copied' : 'Copy'"
          aria-label="Copy command"
          data-test="command-line-copy"
          @click="copy"
        />
      </template>
    </v-textarea>
  </div>
</template>

<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { writeClipboard } from './clipboard'

// The form's command as the user would script it, rebuilt as the form
// changes so it can be checked (or copied) before it's sent. Editing it and
// pressing Enter, or pasting a whole command, loads it into the form. It
// never sends: the form's Send button does.
const props = defineProps({
  // The form's command, see formatFormCmd
  command: {
    type: String,
    default: '',
  },
  // async (text, { edited }) => an error message, or null once the form is
  // loaded. edited: the line was edited rather than pasted whole.
  load: {
    type: Function,
    required: true,
  },
  // The form is loading a command
  loading: {
    type: Boolean,
    default: false,
  },
})
// The line has changes that aren't in the form
const emit = defineEmits(['dirty'])

const placeholder = `cmd("INST COLLECT with TYPE 'NORMAL'")`
const text = ref(props.command)
// The user changed the text since it was last the form's command
const editing = ref(false)
const focused = ref(false)
const error = ref('')
const busy = ref(false)
const copied = ref(false)
const input = ref(null)
let copiedTimer = null

const dirty = computed(
  () => editing.value && text.value.trim() !== props.command.trim(),
)
watch(dirty, (value) => emit('dirty', value))

const hint = computed(() =>
  dirty.value
    ? 'Not loaded: press Enter to load it into the form or Esc to undo. Send is off until then.'
    : 'Follows the form. Edit or paste a command and press Enter to load it.',
)

// The form changed: show it, unless the user is typing here. Changing the
// form elsewhere drops edits that weren't loaded, as the form is what's sent.
watch(
  () => props.command,
  (command) => {
    if (editing.value && focused.value) return
    text.value = command
    editing.value = false
    error.value = ''
  },
)

function markEdited() {
  editing.value = true
  error.value = ''
}

function textarea() {
  return input.value?.$el.querySelector('textarea')
}

// Select it all so a paste replaces it, and loads (see onPaste)
function focus() {
  const el = textarea()
  el?.focus()
  el?.select()
}

// Load text pasted elsewhere, e.g. on the page with nothing focused
function loadText(pasted) {
  focus()
  text.value = pasted.trim()
  markEdited()
  return submit({ edited: false })
}
defineExpose({ focus, loadText })

// A paste that replaces the whole line loads it, as a command pasted from a
// script. Pasting part of it is an edit, loaded with Enter.
function onPaste(event) {
  const el = event.target
  if (el?.tagName !== 'TEXTAREA') return
  const pasted = event.clipboardData?.getData('text')
  if (!pasted?.trim()) return
  const all =
    el.value === '' ||
    (el.selectionStart === 0 && el.selectionEnd === el.value.length)
  if (!all) return
  event.preventDefault()
  // loadText shows its own errors under the line
  void loadText(pasted)
}

function onKeydown(event) {
  if (event.target?.tagName !== 'TEXTAREA') return
  if (event.key === 'Enter') {
    // One line: Enter loads it rather than starting another
    event.preventDefault()
    void submit({ edited: true })
  } else if (event.key === 'Escape' && (dirty.value || error.value)) {
    event.preventDefault()
    event.stopPropagation()
    revert()
  }
}

function revert() {
  text.value = props.command
  editing.value = false
  error.value = ''
}

async function submit({ edited }) {
  if (busy.value) return
  const line = text.value.trim()
  if (!line) {
    error.value = props.command
      ? 'Enter a command to load, or press Esc to undo'
      : ''
    return
  }
  // An edit back to the form's command has nothing to load. A paste always
  // loads, e.g. to ask again for the obfuscated values it masks.
  if (edited && !dirty.value) {
    error.value = ''
    return
  }
  busy.value = true
  try {
    const message = await props.load(line, { edited })
    if (message) {
      error.value = message
      return
    }
    editing.value = false
    error.value = ''
    // The form's command, as it's written from the form. If loading changed
    // it, the watch above shows it once it's rebuilt.
    await nextTick()
    text.value = props.command
  } finally {
    busy.value = false
  }
}

async function copy() {
  try {
    await writeClipboard(text.value.trim())
    copied.value = true
    clearTimeout(copiedTimer)
    copiedTimer = setTimeout(() => {
      copied.value = false
    }, 1500)
  } catch (copyError) {
    console.error('Failed to copy command:', copyError)
  }
}

onBeforeUnmount(() => clearTimeout(copiedTimer))
</script>

<style scoped>
.cs-line-input :deep(textarea) {
  font-family: 'IBM Plex Mono', ui-monospace, monospace;
  font-size: 13px;
  line-height: 1.5;
  /* Long values without spaces (e.g. hex blocks) wrap too */
  overflow-wrap: anywhere;
}
/* Edits that aren't in the form yet */
.cs-line-dirty :deep(.v-field__outline) {
  --v-field-border-opacity: 1;
  color: rgb(var(--v-theme-warning));
}
</style>
