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
      <v-toolbar height="24">
        <v-spacer />
        <span>{{ heading }}</span>
        <v-spacer />
        <v-btn
          icon="mdi-close-box"
          variant="text"
          density="compact"
          @click="show = false"
        />
      </v-toolbar>
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

<script>
import modelShow from '../mixins/modelShow'
import { OpenC3Api } from '@openc3/js-common/services'

// Where a dashboard is saved: its target and file name. Used to create a new
// dashboard ('new') or copy an existing one ('duplicate').
export default {
  mixins: [modelShow],
  props: {
    mode: { type: String, default: 'new' },
    // Target and name filled in when the dialog opens
    initialTarget: { type: String, default: null },
    initialName: { type: String, default: '' },
    // 'TARGET/NAME' of every existing dashboard, to prevent overwrites
    existing: { type: Array, default: () => [] },
  },
  emits: ['submit'],
  data() {
    return { targets: [], target: null, name: '' }
  },
  computed: {
    heading() {
      return this.mode === 'duplicate' ? 'Duplicate Dashboard' : 'New Dashboard'
    },
    error() {
      if (!this.name) return ''
      if (!/^[A-Za-z0-9_-]+$/.test(this.name))
        return 'Use letters, numbers, - and _ only'
      if (this.existing.includes(`${this.target}/${this.name.toUpperCase()}`)) {
        return 'A dashboard with this name already exists'
      }
      return ''
    },
  },
  watch: {
    modelValue(open) {
      if (!open) return
      if (this.initialTarget) this.target = this.initialTarget
      this.name = this.initialName
    },
  },
  async created() {
    this.targets = (await new OpenC3Api().get_target_names()).sort()
    this.target = this.initialTarget || this.targets[0] || null
  },
  methods: {
    submit() {
      if (this.error || !this.name || !this.target) return
      this.$emit('submit', {
        target: this.target,
        name: this.name.toUpperCase(),
      })
      this.name = ''
      this.show = false
    },
  },
}
</script>
