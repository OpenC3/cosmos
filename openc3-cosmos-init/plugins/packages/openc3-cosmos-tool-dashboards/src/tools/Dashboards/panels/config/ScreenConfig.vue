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
        v-model="draftNew.target"
        :items="allTargets"
        label="Target"
        density="compact"
        variant="outlined"
        hide-details
        style="max-width: 200px"
        data-test="config-new-screen-target"
      />
      <v-autocomplete
        v-model="draftNew.packet"
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
      />
      <v-text-field
        v-model="draftNew.name"
        label="Screen name"
        density="compact"
        variant="outlined"
        :error-messages="newProblem && draftNew.name ? newProblem : []"
        :hide-details="!(newProblem && draftNew.name)"
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
          class="position-absolute"
          style="top: 0"
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

<script>
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
export default {
  components: { ScreenEditor },
  props: {
    panel: { type: Object, required: true },
  },
  emits: ['update'],
  data() {
    return {
      // TARGET => [SCREEN, ...]
      screens: {},
      target: this.panel.screen?.targetName || null,
      // The saved definition, null while loading
      original: null,
      loadError: null,
      // New screen form
      creating: false,
      allTargets: [],
      packets: [],
      draftNew: { target: null, packet: null, name: '' },
      generating: false,
    }
  },
  computed: {
    filename() {
      const name = this.panel.screen?.screenName
      return name ? `${name.toLowerCase()}.txt` : 'screen.txt'
    },
    loading() {
      return !!this.panel.screen && this.original === null && !this.loadError
    },
    // Covers the editor when there's no screen text to edit
    overlay() {
      if (!this.panel.screen) return 'Pick or create a screen to edit it here'
      return this.loadError
    },
    editorKey() {
      return screenKey(this.panel.screen)
    },
    text() {
      return this.panel.screenText ?? this.original ?? ''
    },
    edited() {
      return (
        typeof this.panel.screenText === 'string' &&
        this.panel.screenText !== this.original
      )
    },
    newProblem() {
      const { target, name } = this.draftNew
      if (!target) return 'Pick a target'
      if (!name) return 'Name the screen'
      if (!/^[A-Za-z0-9_-]+$/.test(name)) {
        return 'Letters, numbers, - and _ only'
      }
      if ((this.screens[target] || []).includes(name.toUpperCase())) {
        return `${target} already has a ${name.toUpperCase()} screen`
      }
      return null
    },
  },
  watch: {
    editorKey: {
      immediate: true,
      handler() {
        this.load()
      },
    },
    'draftNew.target'(target) {
      this.packets = []
      this.draftNew.packet = null
      if (!target) return
      this.api
        .get_all_tlm_names(target)
        .then((names) => {
          if (target === this.draftNew.target) this.packets = names
        })
        .catch(() => {})
    },
    // Name a generated screen after its packet until the user types one
    'draftNew.packet'(packet, previous) {
      const named = this.draftNew.name.toUpperCase()
      if (packet && (!named || named === previous)) this.draftNew.name = packet
    },
  },
  async created() {
    this.api = new OpenC3Api()
    // A copy: create() lists a new screen here before it's saved
    this.screens = { ...(await listScreens()) }
  },
  methods: {
    selectTarget(target) {
      this.target = target
      // A target with one screen needs no second pick
      const names = this.screens[target] || []
      this.selectScreen(names.length === 1 ? names[0] : null)
    },
    selectScreen(screenName) {
      this.$emit('update', {
        screen: screenName ? { targetName: this.target, screenName } : null,
        screenText: null,
        screenNew: false,
      })
    },
    startCreate() {
      this.draftNew = { target: this.target, packet: null, name: '' }
      this.creating = true
      if (!this.allTargets.length) {
        targetNames()
          .then((names) => {
            this.allTargets = names
          })
          .catch(() => {})
      }
    },
    async create() {
      if (this.newProblem) return
      const { target, packet } = this.draftNew
      const screenName = this.draftNew.name.toUpperCase()
      this.generating = true
      try {
        const text = await newScreenText(this.api, target, packet)
        // Listed now so it can be picked again before it's saved
        this.screens[target] = [
          ...(this.screens[target] || []),
          screenName,
        ].sort()
        this.target = target
        this.$emit('update', {
          screen: { targetName: target, screenName },
          screenText: text,
          screenNew: true,
        })
        this.creating = false
      } catch (error) {
        this.loadError = `Unable to read ${target} ${packet}: ${error.message || error}`
      } finally {
        this.generating = false
      }
    },
    async load() {
      this.original = null
      this.loadError = null
      const screen = this.panel.screen
      if (!screen) return
      // Not written yet: the draft's text is all there is
      if (this.panel.screenNew) {
        this.original = ''
        return
      }
      const key = screenKey(screen)
      try {
        const text = await loadScreen(screen)
        if (key !== this.editorKey) return
        this.original = text
        // Once the editor has the new text, Undo can't go back into the
        // previous screen
        await this.$nextTick()
        this.$refs.editor?.editor?.session.getUndoManager().reset()
      } catch {
        if (key === this.editorKey) {
          this.loadError = `Screen ${key.replace('/', ' ')} not found`
        }
      }
    },
    // Edits matching the file are dropped from the draft; a new screen
    // keeps its text whatever it is
    edit(text) {
      // The editor echoes the text it's given while a screen loads
      if (!this.panel.screen || this.original === null) return
      this.$emit('update', {
        screenText:
          text === this.original && !this.panel.screenNew ? null : text,
      })
    },
    revert() {
      this.$emit('update', { screenText: null })
    },
  },
}
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
