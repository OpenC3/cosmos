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
  <div
    style="
      background-color: var(--color-background-base-default);
      margin: 0px;
      padding: 0px;
    "
  >
    <v-row no-gutters justify="right">
      <v-tabs v-model="activeTab" density="compact">
        <v-tab value="script" text="Script" data-test="script-tab" />
        <v-tab value="messages" text="Messages" data-test="messages-tab" />
      </v-tabs>
      <v-tooltip
        location="bottom"
        :text="filenameSelect"
        :disabled="!filenameSelect || filenameSelect.length <= 45"
      >
        <template #activator="{ props }">
          <div v-bind="props" style="width: 32rem">
            <v-select
              id="inline-filename"
              v-model="filenameSelect"
              :items="fileList"
              :disabled="fileList.length <= 1"
              label="Filename"
              data-test="filename"
              density="compact"
              variant="outlined"
              hide-details
              @update:model-value="$emit('file-name-changed', $event)"
            />
          </div>
        </template>
      </v-tooltip>
    </v-row>

    <v-tabs-window v-model="activeTab">
      <v-tabs-window-item value="script">
        <v-row>
          <v-col
            class="v-col-10"
            style="margin: 15px 0px 0px 0px; padding: 0px"
          >
            <pre
              ref="editor"
              class="editor"
              style="height: 200px"
              @contextmenu.prevent="
                $emit('show-execute-selection-menu', $event)
              "
            ></pre>
          </v-col>
          <v-col
            class="v-col-2"
            style="
              display: flex;
              justify-content: center;
              align-items: center;
              background-color: var(--color-background-surface-default);
            "
          >
            <div v-if="startOrGoButton === 'Start'">
              <v-btn
                class="mx-1"
                color="primary"
                text="Start"
                data-test="start-button"
                :disabled="startOrGoDisabled || !executeUser"
                :hidden="suiteRunner"
                @click="$emit('start')"
              />
            </div>
            <div v-else>
              <v-btn
                color="primary"
                class="ma-2"
                text="Go"
                :disabled="startOrGoDisabled"
                data-test="go-button"
                @click="$emit('go')"
              />
              <v-btn
                color="primary"
                class="ma-2"
                :text="pauseOrRetryButton"
                :disabled="pauseOrRetryDisabled"
                data-test="pause-retry-button"
                @click="$emit('pause-or-retry')"
              />

              <v-btn
                color="primary"
                class="ma-2"
                text="Stop"
                data-test="stop-button"
                :disabled="stopDisabled"
                @click="$emit('stop')"
              />
            </div>
          </v-col>
        </v-row>
      </v-tabs-window-item>

      <v-tabs-window-item value="messages">
        <div style="height: 200px; overflow: hidden">
          <script-log-messages
            v-model="messages"
            :newest-on-top="messagesNewestOnTop"
            @sort="$emit('message-order-changed', $event)"
          />
        </div>
      </v-tabs-window-item>
    </v-tabs-window>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import ScriptLogMessages from '@/tools/scriptrunner/ScriptLogMessages.vue'

defineEmits([
  'file-name-changed',
  'go',
  'message-order-changed',
  'pause-or-retry',
  'show-execute-selection-menu',
  'start',
  'stop',
])

defineProps({
  executeUser: {
    type: Boolean,
    default: true,
  },
  fileList: {
    type: Array,
    default: () => [],
  },
  messagesNewestOnTop: {
    type: Boolean,
    default: true,
  },
  pauseOrRetryButton: {
    type: String,
    required: true,
  },
  pauseOrRetryDisabled: {
    type: Boolean,
    default: false,
  },
  startOrGoButton: {
    type: String,
    required: true,
  },
  startOrGoDisabled: {
    type: Boolean,
    default: false,
  },
  stopDisabled: {
    type: Boolean,
    default: false,
  },
  suiteRunner: {
    type: Boolean,
    default: false,
  },
})

const messages = defineModel('messages', { type: Array, required: true })
const filenameSelect = defineModel('filenameSelect', {
  type: String,
  required: true,
})

const editor = ref(null)
const activeTab = ref('script')

function getEditor() {
  return editor.value
}

defineExpose({
  getEditor,
})
</script>

<style scoped>
.editor {
  height: 100%;
  width: 100%;
  position: relative;
  font-size: 16px;
}
</style>
