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
  <v-menu
    v-model="open"
    :close-on-content-click="false"
    location="bottom end"
    @update:model-value="opened"
    @after-enter="focusInput"
  >
    <template #activator="{ props: activator }">
      <v-btn
        v-bind="activator"
        icon="mdi-clipboard-text-outline"
        variant="text"
        :disabled="disabled"
        title="Paste a command"
        aria-label="Paste a command"
        data-test="paste-command"
      />
    </template>
    <!-- Enter anywhere in the box loads, as the menu can move focus to
         its content as it opens -->
    <v-card
      class="cs-paste pa-4"
      data-test="paste-command-card"
      @keydown.enter="enter"
    >
      <label for="cs-paste-input" class="cs-paste-label d-block mb-2">
        Paste a command to load it into the form, then press Send.
      </label>
      <v-text-field
        id="cs-paste-input"
        ref="input"
        v-model="text"
        class="mono"
        placeholder="cmd(&quot;INST COLLECT with TYPE 'NORMAL'&quot;)"
        density="compact"
        variant="outlined"
        autocomplete="off"
        spellcheck="false"
        hide-details="auto"
        :error-messages="error"
        data-test="paste-command-input"
        @update:model-value="error = ''"
      />
      <div class="d-flex justify-end ga-2 mt-3">
        <v-btn variant="text" @click="open = false"> Cancel </v-btn>
        <v-btn
          color="primary"
          variant="flat"
          :loading="busy"
          :disabled="!text.trim()"
          data-test="paste-command-load"
          @click="submit"
        >
          Load
        </v-btn>
      </div>
    </v-card>
  </v-menu>
</template>

<script setup>
import { nextTick, ref } from 'vue'

// Loads one pasted command into the form. It never sends: the form's Send
// button does. Opened from its button or the File menu (v-model), or with
// text already pasted (openWith, for Mod+V on the page).
const props = defineProps({
  // async (text) => an error message, or null once the form is loaded
  load: {
    type: Function,
    required: true,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
})
const open = defineModel({ type: Boolean, default: false })

const text = ref('')
const error = ref('')
const busy = ref(false)
const input = ref(null)

// Open with text, e.g. pasted while nothing had focus, ready to Load
function openWith(pasted) {
  text.value = pasted
  open.value = true
  opened(true)
}
defineExpose({ openWith })

function opened(isOpen) {
  if (!isOpen) return
  error.value = ''
  nextTick(focusInput)
}

// Select what's there so a paste replaces it. Again once the menu has
// opened, as it can't take focus before its content renders.
function focusInput() {
  const el = input.value?.$el.querySelector('input')
  el?.focus()
  el?.select()
}

// Enter on the buttons presses them instead
function enter(event) {
  if (event.target.closest('button')) return
  event.preventDefault()
  submit()
}

async function submit() {
  if (!text.value.trim() || busy.value) return
  busy.value = true
  try {
    const message = await props.load(text.value)
    if (message) {
      error.value = message
    } else {
      text.value = ''
      open.value = false
    }
  } finally {
    busy.value = false
  }
}
</script>

<style scoped>
.cs-paste {
  width: min(640px, calc(100vw - 32px));
  /* Teleported out of .cmd-sender, so it sets the Command Sender type */
  font-family: 'IBM Plex Sans', system-ui, sans-serif;
  font-size: 13px;
}
.cs-paste-label {
  font-size: 14px;
}
.cs-paste :deep(input) {
  font-family: 'IBM Plex Mono', ui-monospace, monospace;
  font-size: 13px;
}
</style>
