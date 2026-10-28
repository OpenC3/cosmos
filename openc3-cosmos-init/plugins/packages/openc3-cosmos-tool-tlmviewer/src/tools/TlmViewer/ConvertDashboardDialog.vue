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
  <!-- Saves the open screens as a dashboard, then opens it in Dashboards -->
  <v-dialog v-model="show" width="500" @keydown.esc="show = false">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span>Convert to Dashboard</span>
        <v-spacer />
        <v-btn
          icon="mdi-close-box"
          variant="text"
          density="compact"
          data-test="convert-dashboard-close-icon"
          @click="show = false"
        />
      </v-toolbar>
      <v-card-text class="pt-4">
        <p class="mb-4">
          Each of the {{ definitions.length }} open
          {{ definitions.length === 1 ? 'screen' : 'screens' }} becomes a Screen
          panel, {{ SCREEN_WIDTH }} columns by {{ SCREEN_HEIGHT }} rows. You can
          resize them in the dashboard afterwards.
        </p>
        <v-select
          v-model="target"
          :items="targets"
          label="Target"
          hint="The dashboard is saved in TARGET/dashboards"
          persistent-hint
          density="compact"
          variant="outlined"
          class="mb-3"
          data-test="convert-dashboard-target"
          @update:model-value="checkExisting"
        />
        <v-text-field
          :model-value="name"
          label="Dashboard name"
          :error-messages="nameProblem"
          density="compact"
          variant="outlined"
          data-test="convert-dashboard-name"
          @update:model-value="setName"
        />
        <v-alert
          v-if="exists"
          type="warning"
          variant="tonal"
          density="compact"
          class="mt-2"
          data-test="convert-dashboard-exists"
        >
          {{ target }}/{{ name.toUpperCase() }} already exists and will be
          replaced.
        </v-alert>
        <v-alert
          v-if="error"
          type="error"
          variant="tonal"
          density="compact"
          class="mt-2"
        >
          {{ error }}
        </v-alert>
      </v-card-text>
      <v-card-actions class="px-4 pb-4">
        <v-spacer />
        <v-btn variant="outlined" @click="show = false">Cancel</v-btn>
        <v-btn
          variant="flat"
          color="primary"
          :loading="saving"
          :disabled="!!nameProblem || !target || !definitions.length"
          data-test="convert-dashboard-submit"
          @click="convert"
        >
          {{ exists ? 'Replace and Open' : 'Convert and Open' }}
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { computed, ref } from 'vue'
import { Api } from '@openc3/js-common/services'
import {
  SCREEN_HEIGHT,
  SCREEN_WIDTH,
  convertToDashboard,
} from './convertToDashboard'

const props = defineProps({
  // The open screens: [{ target, screen }]
  definitions: { type: Array, required: true },
  // Starting name, e.g. the configuration's
  initialName: { type: String, default: 'TLMVIEWER' },
})
const show = defineModel({ type: Boolean })

// Targets of the open screens, the first screen's first
const targets = computed(() => [
  ...new Set(props.definitions.map((def) => def.target)),
])
const target = ref(targets.value[0] ?? null)
const name = ref(props.initialName.replace(/[^A-Za-z0-9_-]/g, '_'))
const exists = ref(false)
const saving = ref(false)
const error = ref(null)

const nameProblem = computed(() => {
  if (!name.value) return 'Enter a name'
  if (!/^[A-Za-z0-9_-]+$/.test(name.value)) {
    return 'Letters, numbers, - and _ only'
  }
  return null
})

function dashboardUrl() {
  const dashboard = name.value.toUpperCase()
  return `/openc3-api/dashboard/${encodeURIComponent(target.value)}/${encodeURIComponent(dashboard)}`
}

function setName(value) {
  name.value = value
  checkExisting()
}

// Warn before replacing a saved dashboard
let check = 0
async function checkExisting() {
  const current = ++check
  exists.value = false
  if (nameProblem.value || !target.value) return
  try {
    await Api.get(dashboardUrl(), {
      headers: { Accept: 'text/plain', 'Ignore-Errors': '404' },
    })
    if (current === check) exists.value = true
  } catch {
    // Not saved yet
  }
}
checkExisting()

async function convert() {
  saving.value = true
  error.value = null
  const dashboard = name.value.toUpperCase()
  try {
    await Api.post('/openc3-api/dashboard', {
      data: {
        scope: window.openc3Scope,
        target: target.value,
        dashboard,
        text: convertToDashboard(props.definitions, name.value),
      },
    })
    window.location.assign(
      `/tools/dashboards/${encodeURIComponent(target.value)}/${encodeURIComponent(dashboard)}`,
    )
  } catch (e) {
    error.value = `Could not save the dashboard: ${e.message}`
    saving.value = false
  }
}
</script>
