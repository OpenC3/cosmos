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
    <v-card v-if="draft" style="max-height: 90vh" data-test="panel-dialog">
      <v-toolbar height="24">
        <v-spacer />
        <span>{{ isNew ? 'Add Panel' : 'Configure Panel' }}</span>
        <v-spacer />
        <v-btn
          icon="mdi-close-box"
          variant="text"
          density="compact"
          aria-label="Close"
          @click="show = false"
        />
      </v-toolbar>
      <v-tabs v-model="tab" density="compact">
        <v-tab value="settings" data-test="panel-tab-settings">Settings</v-tab>
        <v-tab value="code" data-test="panel-tab-code">Code</v-tab>
      </v-tabs>
      <v-divider />
      <v-card-text>
        <panel-settings
          v-if="tab === 'settings'"
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
        <span v-if="problem" class="text-caption text-error px-2">
          {{ problem }}
        </span>
        <v-spacer />
        <v-btn variant="outlined" @click="show = false">Cancel</v-btn>
        <v-btn
          variant="flat"
          :disabled="!!problem"
          data-test="panel-save"
          @click="save"
        >
          {{ isNew ? 'Add' : 'Apply' }}
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import modelShow from '../mixins/modelShow'
import PanelSettings from '../editor/PanelSettings.vue'
import CodePane from '../editor/CodePane.vue'
import { PANEL_TYPES, panelProblem } from '../panels/registry'
import { clampRect } from '../layout'
import { parsePanel, serializePanel } from '../dashboardParser'

// Edits a copy of a panel, as settings or as its PANEL ... END code; the
// dashboard only changes on Add / Apply
export default {
  components: { CodePane, PanelSettings },
  mixins: [modelShow],
  props: {
    panel: { type: Object, default: null },
    isNew: Boolean,
  },
  emits: ['save'],
  data() {
    return { draft: null, tab: 'settings' }
  },
  computed: {
    code() {
      return serializePanel(this.draft)
    },
    problem() {
      return this.draft ? panelProblem(this.draft) : null
    },
  },
  watch: {
    modelValue: {
      immediate: true,
      handler(open) {
        if (open && this.panel) {
          this.draft = JSON.parse(JSON.stringify(this.panel))
          this.tab = 'settings'
        }
      },
    },
  },
  methods: {
    update(change) {
      // A new panel takes the new type's default size
      if (this.isNew && change.type && change.type !== this.draft.type) {
        Object.assign(this.draft, PANEL_TYPES[change.type].defaults)
      }
      Object.assign(this.draft, change)
    },
    parsePanel,
    // Code edits replace the draft but keep it the same panel
    applyCode(panel) {
      if (!panel) return
      this.draft = { ...panel, uid: this.draft.uid }
    },
    resize({ w, h }) {
      Object.assign(this.draft, clampRect({ ...this.draft, w, h }))
    },
    save() {
      this.$emit('save', this.draft)
      this.show = false
    },
  },
}
</script>
