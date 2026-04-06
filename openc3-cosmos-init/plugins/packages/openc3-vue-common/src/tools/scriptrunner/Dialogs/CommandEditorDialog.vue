<!--
# Copyright 2026, OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog
    v-model="show"
    max-width="1200"
    persistent
    scrollable
    @keydown.esc="close"
  >
    <v-card>
      <v-card-title class="d-flex align-center">
        <span>Insert Command</span>
        <v-spacer />
        <v-btn icon="mdi-close" variant="text" @click="close" />
      </v-card-title>
      <v-card-text class="pa-0">
        <div v-if="dialogError" class="error-message">
          <v-icon class="mr-2" color="error">mdi-alert-circle</v-icon>
          <span class="flex-grow-1">{{ dialogError }}</span>
          <v-btn
            icon="mdi-close"
            size="small"
            variant="text"
            color="error"
            class="ml-2"
            @click="dialogError = null"
          />
        </div>
        <command-editor
          ref="commandEditorRef"
          :initial-target-name="targetName"
          :initial-packet-name="packetName"
          :cmd-string="cmdString"
          :send-disabled="false"
          :show-command-button="false"
          @build-cmd="$emit('build-cmd', $event)"
        />
      </v-card-text>
      <v-card-actions>
        <v-spacer />
        <v-btn variant="outlined" @click="close"> Cancel </v-btn>
        <v-btn color="primary" variant="flat" @click="handleInsert">
          Insert Command
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { ref, useTemplateRef } from 'vue'
import CommandEditor from '@/components/CommandEditor.vue'

const emit = defineEmits(['build-cmd', 'close', 'insert'])

const commandEditorRef = useTemplateRef('commandEditorRef')
const show = ref(false)
const targetName = ref(null)
const packetName = ref(null)
const cmdString = ref(null)
const dialogError = ref(null)
const isEditing = ref(false)
const editLine = ref(null)

function open(options = {}) {
  cmdString.value = options.cmdString || null
  isEditing.value = options.isEditing || false
  editLine.value = options.editLine === undefined ? null : options.editLine
  targetName.value = options.targetName || null
  packetName.value = options.packetName || null
  dialogError.value = null
  show.value = true
}

function close() {
  show.value = false
  emit('close')
}

function handleInsert() {
  let commandString = ''
  try {
    commandString = commandEditorRef.value?.getCmdString()
    const parts = commandString.split(' ')
    targetName.value = parts[0]
    packetName.value = parts[1]
  } catch (error) {
    dialogError.value = error.message || 'Please fix command parameters'
    return
  }

  emit('insert', {
    commandString,
    isEditing: isEditing.value,
    editLine: editLine.value,
  })
  close()
}

defineExpose({
  open,
  close,
})
</script>

<style scoped>
.error-message {
  display: flex;
  align-items: center;
  padding: 12px 16px;
  background-color: rgba(var(--v-theme-error), 0.1);
  border-left: 4px solid rgb(var(--v-theme-error));
  margin: 16px;
  border-radius: 4px;
}
</style>
