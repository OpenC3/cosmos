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
  <v-dialog v-model="show" persistent width="560" @keydown.esc="show = false">
    <v-card>
      <dialog-toolbar :title="heading" @close="show = false" />
      <v-card-text class="d-flex flex-column ga-4 pt-4">
        <div class="text-body-2 text-medium-emphasis">
          Dashboards are saved with a target, like screens, but can show items
          from any target.
        </div>
        <v-select
          v-model="target"
          label="Saved with target"
          :items="targets"
          density="compact"
          variant="outlined"
          hide-details
          data-test="dashboard-dialog-target"
        />
        <v-text-field
          v-model="name"
          label="Dashboard name (without .txt)"
          autofocus
          density="compact"
          variant="outlined"
          :error-messages="error"
          data-test="dashboard-dialog-name"
          @keyup.enter="submit"
        />
        <!-- A copy keeps its source's grid -->
        <div v-if="mode === 'new'">
          <div class="text-body-2 mb-2">Grid columns</div>
          <v-btn-toggle
            v-model="columns"
            mandatory
            divided
            variant="outlined"
            density="compact"
            color="secondary"
            data-test="dashboard-dialog-columns"
          >
            <v-btn :value="12" prepend-icon="mdi-monitor">12 columns</v-btn>
            <v-btn :value="24" prepend-icon="mdi-monitor-screenshot">
              24 columns
            </v-btn>
          </v-btn-toggle>
          <div class="text-caption text-medium-emphasis mt-2">
            Fits most screens. Choose 24 for big monitors and ultra wide
            screens.
          </div>
        </div>
      </v-card-text>
      <v-divider />
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn variant="outlined" @click="show = false">Cancel</v-btn>
        <v-btn
          variant="flat"
          :disabled="!!error || !name"
          data-test="dashboard-dialog-submit"
          @click="submit"
        >
          {{ mode === 'duplicate' ? 'Duplicate' : 'Create' }}
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import DialogToolbar from '../components/DialogToolbar.vue'
import { targetNames } from '../composables/targets'
import { GRID_COLUMNS } from '../layout'

// Where a dashboard is saved: its target and file name, and for a new one its
// grid (COLUMNS). Used to create a new dashboard ('new') or copy an existing
// one ('duplicate').
const props = defineProps({
  mode: { type: String, default: 'new' },
  // Target and name filled in when the dialog opens
  initialTarget: { type: String, default: null },
  initialName: { type: String, default: '' },
  // 'TARGET/NAME' of every existing dashboard, to prevent overwrites
  existing: { type: Array, default: () => [] },
})
const emit = defineEmits(['submit'])
const show = defineModel({ type: Boolean })

const targets = ref([])
const target = ref(null)
const name = ref('')
const columns = ref(GRID_COLUMNS)

const heading = computed(() =>
  props.mode === 'duplicate' ? 'Duplicate Dashboard' : 'New Dashboard',
)
const error = computed(() => {
  if (!name.value) return ''
  if (!/^[A-Za-z0-9_-]+$/.test(name.value))
    return 'Use letters, numbers, - and _ only'
  if (props.existing.includes(`${target.value}/${name.value.toUpperCase()}`)) {
    return 'A dashboard with this name already exists'
  }
  return ''
})

// Kept: the parent opens the dialog through v-model, with no open event to
// hook, and the form starts over from the props as they are at that moment
watch(show, async (open) => {
  if (!open) return
  if (props.initialTarget) target.value = props.initialTarget
  name.value = props.initialName
  columns.value = GRID_COLUMNS
  // Fetched the first time it opens (cached after that)
  if (!targets.value.length) {
    try {
      targets.value = await targetNames()
    } catch {
      return
    }
  }
  target.value ||= targets.value[0] || null
})

function submit() {
  if (error.value || !name.value || !target.value) return
  emit('submit', {
    target: target.value,
    name: name.value.toUpperCase(),
    columns: columns.value,
  })
  name.value = ''
  show.value = false
}
</script>
