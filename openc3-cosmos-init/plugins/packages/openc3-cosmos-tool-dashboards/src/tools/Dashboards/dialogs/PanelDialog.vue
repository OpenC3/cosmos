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
  <v-dialog
    v-model="show"
    persistent
    width="1100"
    max-width="96vw"
    scrollable
    @keydown.esc="show = false"
  >
    <v-card
      v-if="draft"
      :style="fill ? { height: '92vh' } : { maxHeight: '90vh' }"
      data-test="panel-dialog"
    >
      <dialog-toolbar
        :title="isNew ? 'Add Panel' : 'Configure Panel'"
        @close="show = false"
      />
      <v-tabs v-model="tab" density="compact">
        <v-tab value="settings" data-test="panel-tab-settings">Settings</v-tab>
        <v-tab value="code" data-test="panel-tab-code">Code</v-tab>
      </v-tabs>
      <v-divider />
      <v-card-text
        :class="{ 'd-flex flex-column': fill && tab === 'settings' }"
      >
        <panel-settings
          v-if="tab === 'settings'"
          :class="{ 'flex-grow-1': fill }"
          :fill="fill"
          :panel="draft"
          @update="update"
          @resize="resize"
        />
        <code-pane
          v-else
          :text="code"
          path="Panel code"
          hint="Edits here and in Settings change the same panel"
          :parse="parsePanel"
          :rows="18"
          @apply="applyCode"
        />
      </v-card-text>
      <v-divider />
      <v-card-actions class="px-2">
        <span
          v-if="problem || saveError"
          class="text-caption text-error px-2"
          data-test="panel-dialog-error"
        >
          {{ problem || saveError }}
        </span>
        <v-spacer />
        <v-btn variant="outlined" @click="show = false">Cancel</v-btn>
        <v-btn
          variant="flat"
          :disabled="!!problem"
          :loading="saving"
          data-test="panel-save"
          @click="save"
        >
          {{ isNew ? 'Add' : 'Apply' }}
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { computed, inject, ref, unref, watch } from 'vue'
import DialogToolbar from '../components/DialogToolbar.vue'
import PanelSettings from '../editor/PanelSettings.vue'
import CodePane from '../editor/CodePane.vue'
import { PANEL_TYPES, panelProblem } from '../panels/registry'
import { clampRect } from '../layout'
import {
  parsePanel as parsePanelText,
  serializePanel,
} from '../dashboardParser'

// Edits a copy of a panel, as settings or as its PANEL ... END code; the
// dashboard only changes on Add / Apply
const props = defineProps({
  panel: { type: Object, default: null },
  isNew: Boolean,
})
const emit = defineEmits(['save'])
const show = defineModel({ type: Boolean })
// The dashboard's grid width (COLUMNS)
const injectedColumns = inject('columns', 12)
const columns = computed(() => unref(injectedColumns))

const draft = ref(null)
const tab = ref('settings')
const saving = ref(false)
const saveError = ref(null)

const code = computed(() => serializePanel(draft.value))
const problem = computed(() => (draft.value ? panelProblem(draft.value) : null))
// Types like SCREEN give their content editor the rest of a tall dialog
const fill = computed(() => !!PANEL_TYPES[draft.value?.type]?.fillDialog)

// Kept: the parent opens the dialog through v-model, with no open event to
// hook, and the form starts over from the props as they are at that moment
watch(
  show,
  (open) => {
    if (open && props.panel) {
      draft.value = JSON.parse(JSON.stringify(props.panel))
      tab.value = 'settings'
      saveError.value = null
    }
  },
  { immediate: true },
)

function update(change) {
  // A new panel takes the new type's default size
  if (props.isNew && change.type && change.type !== draft.value.type) {
    Object.assign(draft.value, PANEL_TYPES[change.type].defaults)
  }
  Object.assign(draft.value, change)
  // Grown to the new type's minimum size
  if (change.type) {
    Object.assign(draft.value, clampRect(draft.value, columns.value))
  }
}
function parsePanel(text) {
  return parsePanelText(text, columns.value)
}
// Code edits replace the draft but keep it the same panel
function applyCode(panel) {
  if (!panel) return
  // Unsaved screen edits stay while it's the same screen
  const sameScreen =
    JSON.stringify(panel.screen) === JSON.stringify(draft.value.screen)
  draft.value = {
    ...panel,
    uid: draft.value.uid,
    screenText: sameScreen ? draft.value.screenText : null,
    screenNew: sameScreen ? draft.value.screenNew : false,
  }
}
function resize({ w, h }) {
  Object.assign(draft.value, clampRect({ ...draft.value, w, h }, columns.value))
}
// Type hooks run first (a SCREEN panel writes its screen file); edits
// that aren't part of the dashboard are dropped from the panel
async function save() {
  saving.value = true
  saveError.value = null
  try {
    await PANEL_TYPES[draft.value.type].beforeSave?.(draft.value)
  } catch (error) {
    saveError.value = `Unable to save: ${error.message || error}`
    return
  } finally {
    saving.value = false
  }
  const { screenText, screenNew, ...panel } = draft.value
  emit('save', panel)
  show.value = false
}
</script>
