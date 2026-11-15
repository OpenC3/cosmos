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
  <v-dialog v-model="show" width="960" scrollable>
    <v-card data-test="code-dialog">
      <dialog-toolbar title="Dashboard Code" @close="show = false" />
      <v-card-text class="pa-3">
        <code-pane
          :text="text"
          :path="path"
          :rows="28"
          @apply="(model) => $emit('apply', model)"
        />
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script setup>
import DialogToolbar from '../components/DialogToolbar.vue'
import CodePane from '../editor/CodePane.vue'

// The dashboard as text. Edits apply live (when they parse) and the dashboard
// behind the dialog updates as you type; Undo reverts them.
defineProps({
  text: { type: String, required: true },
  path: { type: String, default: '' },
})
defineEmits(['apply'])
const show = defineModel({ type: Boolean })
</script>
