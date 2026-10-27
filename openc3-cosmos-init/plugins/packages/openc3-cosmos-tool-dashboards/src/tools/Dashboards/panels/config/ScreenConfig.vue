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
  <div class="screen-config d-flex flex-column">
    <div class="d-flex align-center ga-2 mb-3">
      <span class="text-subtitle-2">Screen</span>
      <span class="text-caption text-medium-emphasis">
        A Telemetry Viewer screen, shown as it is in Telemetry Viewer
      </span>
    </div>
    <div v-if="!creating" class="d-flex align-center ga-3">
      <v-autocomplete
        :model-value="target"
        :items="Object.keys(screens)"
        label="Target"
        density="compact"
        variant="outlined"
        hide-details
        style="max-width: 240px"
        data-test="config-screen-target"
        @update:model-value="selectTarget"
      />
      <v-autocomplete
        :model-value="panel.screen?.screenName"
        :items="screens[target] || []"
        label="Screen"
        density="compact"
        variant="outlined"
        hide-details
        :disabled="!target"
        data-test="config-screen-name"
        @update:model-value="selectScreen"
      />
      <v-btn
        variant="outlined"
        prepend-icon="mdi-file-plus-outline"
        data-test="config-screen-new"
        @click="startCreate"
      >
        New screen
      </v-btn>
    </div>
    <form
      v-else
      class="d-flex align-start ga-3"
      data-test="config-screen-new-form"
      @submit.prevent="create"
    >
      <v-autocomplete
        :model-value="draftNew.target"
        :items="allTargets"
        label="Target"
        density="compact"
        variant="outlined"
        hide-details
        style="max-width: 200px"
        data-test="config-new-screen-target"
        @update:model-value="setNewTarget"
      />
      <v-autocomplete
        :model-value="draftNew.packet"
        :items="packets"
        label="Start from packet (optional)"
        placeholder="Blank screen"
        persistent-placeholder
        clearable
        density="compact"
        variant="outlined"
        hide-details
        :disabled="!draftNew.target"
        style="max-width: 260px"
        data-test="config-new-screen-packet"
        @update:model-value="setNewPacket"
      />
      <v-text-field
        v-model="draftNew.name"
        label="Screen name"
        density="compact"
        variant="outlined"
        :error-messages="nameErrors"
        :hide-details="!nameErrors.length"
        autofocus
        data-test="config-new-screen-name"
      />
      <v-btn
        type="submit"
        color="primary"
        variant="flat"
        :disabled="!!newProblem"
        :loading="generating"
        data-test="config-new-screen-create"
      >
        Create
      </v-btn>
      <v-btn variant="text" @click="creating = false">Cancel</v-btn>
    </form>
    <!-- Always laid out at full size, with one editor that stays mounted:
         picking or loading a screen only changes its text and the overlay,
         so nothing jumps or flashes -->
    <div v-show="!creating" class="d-flex flex-column flex-grow-1">
      <div class="definition-bar d-flex align-center ga-2 mt-3 mb-1">
        <span class="text-subtitle-2">Screen definition</span>
        <v-chip
          v-if="panel.screenNew || edited"
          size="small"
          variant="text"
          class="text-warning"
          data-test="config-screen-unsaved"
        >
          {{
            panel.screenNew
              ? 'New: the screen file is created when the panel is saved'
              : 'Unsaved: written to the screen file when the panel is saved'
          }}
        </v-chip>
        <v-spacer />
        <v-btn
          v-if="edited && !panel.screenNew"
          variant="text"
          size="small"
          prepend-icon="mdi-undo"
          data-test="config-screen-revert"
          @click="revert"
        >
          Revert
        </v-btn>
      </div>
      <!-- The editor is absolutely positioned in a box that takes the height
           left, so Ace gets a definite size however the dialog lays out -->
      <div class="editor-box position-relative">
        <screen-editor
          ref="editor"
          class="position-absolute"
          style="inset: 0"
          :model-value="text"
          :filename="filename"
          :file-controls="false"
          fill
          data-test="config-screen-editor"
          @update:model-value="edit"
        />
        <v-progress-linear
          v-if="loading"
          indeterminate
          color="secondary"
          class="position-absolute top-0"
        />
        <div
          v-if="overlay"
          :class="[
            'overlay position-absolute d-flex align-center justify-center pa-4 text-center text-body-2',
            loadError ? 'text-error' : 'text-medium-emphasis',
          ]"
          :data-test="loadError ? 'config-screen-error' : undefined"
        >
          {{ overlay }}
        </div>
      </div>
      <div class="text-caption text-medium-emphasis">
        Changes apply to the screen everywhere it's shown, including Telemetry
        Viewer.
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, nextTick, ref, useTemplateRef, watch } from 'vue'
import { OpenC3Api } from '@openc3/js-common/services'
import { ScreenEditor } from '@openc3/vue-common/components'
import { targetNames } from '../../composables/targets'
import { listScreens, loadScreen, newScreenText, screenKey } from '../screens'

// Picks or creates the screen a SCREEN panel shows and edits its definition
// with Telemetry Viewer's screen editor (keyword autocomplete and docs).
// Edits ride on the panel draft as `screenText` (and `screenNew` for a screen
// that doesn't exist yet), so they survive switching to the Code tab and
// Cancel drops them; the panel dialog writes the screen file on Add / Apply
// (SCREEN's beforeSave in registry.js). Fills the dialog (fillDialog).
const props = defineProps({
  panel: { type: Object, required: true },
})
const emit = defineEmits(['update'])

const api = new OpenC3Api()
const editorRef = useTemplateRef('editor')

// TARGET => [SCREEN, ...]
const screens = ref({})
const target = ref(props.panel.screen?.targetName || null)
// The saved definition, null while loading
const original = ref(null)
const loadError = ref(null)
// New screen form
const creating = ref(false)
const allTargets = ref([])
const packets = ref([])
const draftNew = ref({ target: null, packet: null, name: '' })
const generating = ref(false)
// Shown in the new screen form, which hides the editor's overlay
const createError = ref(null)

const filename = computed(() => {
  const name = props.panel.screen?.screenName
  return name ? `${name.toLowerCase()}.txt` : 'screen.txt'
})
const loading = computed(
  () => !!props.panel.screen && original.value === null && !loadError.value,
)
// Covers the editor when there's no screen text to edit
const overlay = computed(() => {
  if (!props.panel.screen) return 'Pick or create a screen to edit it here'
  return loadError.value
})
const editorKey = computed(() => screenKey(props.panel.screen))
const text = computed(() => props.panel.screenText ?? original.value ?? '')
const edited = computed(
  () =>
    typeof props.panel.screenText === 'string' &&
    props.panel.screenText !== original.value,
)
const newProblem = computed(() => {
  const { target: newTarget, name } = draftNew.value
  if (!newTarget) return 'Pick a target'
  if (!name) return 'Name the screen'
  if (!/^[A-Za-z0-9_-]+$/.test(name)) {
    return 'Letters, numbers, - and _ only'
  }
  if ((screens.value[newTarget] || []).includes(name.toUpperCase())) {
    return `${newTarget} already has a ${name.toUpperCase()} screen`
  }
  return null
})
const nameErrors = computed(() => {
  if (createError.value) return [createError.value]
  return newProblem.value && draftNew.value.name ? [newProblem.value] : []
})

// A copy: create() lists a new screen here before it's saved
listScreens()
  .then((list) => {
    screens.value = { ...list }
  })
  .catch((error) => {
    console.error('Dashboards screen list failed to load:', error)
  })

function selectTarget(newTarget) {
  target.value = newTarget
  // A target with one screen needs no second pick
  const names = screens.value[newTarget] || []
  selectScreen(names.length === 1 ? names[0] : null)
}

function selectScreen(screenName) {
  emit('update', {
    screen: screenName ? { targetName: target.value, screenName } : null,
    screenText: null,
    screenNew: false,
  })
}

function startCreate() {
  draftNew.value = { target: target.value, packet: null, name: '' }
  packets.value = []
  if (target.value) loadPackets(target.value)
  createError.value = null
  creating.value = true
  if (!allTargets.value.length) {
    targetNames()
      .then((names) => {
        allTargets.value = names
      })
      .catch(() => {})
  }
}

function setNewTarget(newTarget) {
  draftNew.value.target = newTarget
  draftNew.value.packet = null
  packets.value = []
  if (newTarget) loadPackets(newTarget)
}

function loadPackets(newTarget) {
  api
    .get_all_tlm_names(newTarget)
    .then((names) => {
      if (newTarget === draftNew.value.target) packets.value = names
    })
    .catch(() => {})
}

// Name a generated screen after its packet until the user types one
function setNewPacket(packet) {
  const previous = draftNew.value.packet
  draftNew.value.packet = packet
  const named = draftNew.value.name.toUpperCase()
  if (packet && (!named || named === previous)) draftNew.value.name = packet
}

async function create() {
  if (newProblem.value) return
  const { target: newTarget, packet } = draftNew.value
  const screenName = draftNew.value.name.toUpperCase()
  createError.value = null
  generating.value = true
  try {
    const screenText = await newScreenText(api, newTarget, packet)
    // Listed now so it can be picked again before it's saved
    screens.value[newTarget] = [
      ...(screens.value[newTarget] || []),
      screenName,
    ].sort()
    target.value = newTarget
    emit('update', {
      screen: { targetName: newTarget, screenName },
      screenText,
      screenNew: true,
    })
    creating.value = false
  } catch (error) {
    createError.value = `Unable to read ${newTarget} ${packet}: ${error.message || error}`
  } finally {
    generating.value = false
  }
}

async function load() {
  original.value = null
  loadError.value = null
  const screen = props.panel.screen
  if (!screen) return
  // Not written yet: the draft's text is all there is
  if (props.panel.screenNew) {
    original.value = ''
    return
  }
  const key = screenKey(screen)
  try {
    const loaded = await loadScreen(screen)
    if (key !== editorKey.value) return
    original.value = loaded
    // Once the editor has the new text, Undo can't go back into the
    // previous screen
    await nextTick()
    editorRef.value?.editor?.session.getUndoManager().reset()
  } catch {
    if (key === editorKey.value) {
      loadError.value = `Screen ${key.replace('/', ' ')} not found`
    }
  }
}

// Edits matching the file are dropped from the draft; a new screen
// keeps its text whatever it is
function edit(newText) {
  // The editor echoes the text it's given while a screen loads
  if (!props.panel.screen || original.value === null) return
  emit('update', {
    screenText:
      newText === original.value && !props.panel.screenNew ? null : newText,
  })
}

function revert() {
  emit('update', { screenText: null })
}

// Loads the saved file for whichever screen the panel has, however it got
// it (picked or created here, or edited in the Code tab)
watch(editorKey, load, { immediate: true })
</script>

<style scoped>
/* A rule, not the min-h-0 helper: the panel dialog renders outside
   .dashboards-root where the helpers live */
.screen-config {
  min-height: 0;
}
/* The height the rest of the panel settings leave, and at least most of
   the window so the editor is never cramped */
.editor-box {
  flex: 1 1 0;
  min-height: max(400px, 55vh);
}
/* Same height with or without the Revert button, so the editor doesn't
   shift when the first edit shows it */
.definition-bar {
  min-height: 28px;
}
.overlay {
  inset: 0;
  z-index: 1;
  background: rgba(var(--v-theme-surface), 0.92);
}
</style>
