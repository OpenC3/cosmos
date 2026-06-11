<!--
# Copyright 2026 OpenC3, Inc.
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
  <v-card>
    <v-card-title>AI Chat Settings</v-card-title>
    <v-alert v-model="errorLoading" type="error" closable density="compact">
      Error loading previous configuration due to {{ errorText }}
    </v-alert>
    <v-alert v-model="errorSaving" type="error" closable density="compact">
      Error saving due to {{ errorText }}
    </v-alert>
    <v-alert v-model="successSaving" type="success" closable density="compact">
      Saved! (Refresh the page to see changes)
    </v-alert>
    <v-card-text class="pb-0">
      <v-switch
        v-model="aiChatEnabled"
        label="Enable the in-app AI Chatbot (Enterprise). When disabled, the AI
        chat button and drawer are hidden for all users."
        color="primary"
        data-test="ai-chat-enabled"
      />
    </v-card-text>
    <v-card-actions>
      <v-btn
        color="primary"
        variant="flat"
        data-test="save-ai-chat"
        @click="save"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import Settings from './settings.js'

const AI_CHAT_SETTING = 'ai_chat'

export default {
  mixins: [Settings],
  data() {
    return {
      aiChatEnabled: true,
    }
  },
  created() {
    this.loadSetting(AI_CHAT_SETTING)
  },
  methods: {
    save: function () {
      this.saveSetting(AI_CHAT_SETTING, this.aiChatEnabled)
    },
    parseSetting: function (response) {
      if (response !== null && response !== undefined) {
        this.aiChatEnabled = response
      }
    },
  },
}
</script>
