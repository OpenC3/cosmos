<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" persistent width="600" @keydown.esc="cancelHandler">
    <v-card>
      <v-form v-model="valid" @submit.prevent="submitHandler">
        <v-toolbar height="24">
          <v-spacer />
          <span> User Input Required </span>
          <v-spacer />
        </v-toolbar>
        <div class="pa-2">
          <v-card-text>
            <div class="question">{{ question }}</div>
            <v-text-field
              v-model="inputValue"
              autofocus
              data-test="ask-value-input"
              :type="password ? 'password' : 'text'"
              :rules="rules"
            />
          </v-card-text>
        </div>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn
            variant="outlined"
            data-test="ask-cancel"
            @click="cancelHandler"
          >
            Cancel
          </v-btn>
          <v-btn
            variant="flat"
            type="submit"
            data-test="ask-ok"
            :disabled="!valid"
            @click.prevent="submitHandler"
          >
            Ok
          </v-btn>
        </v-card-actions>
      </v-form>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  question: {
    type: String,
    required: true,
  },
  default: {
    type: String,
    default: null,
  },
  password: {
    type: Boolean,
    default: false,
  },
  answerRequired: {
    type: Boolean,
    default: true,
  },
})

const emit = defineEmits(['response'])

const show = defineModel({ type: Boolean })

const inputValue = ref(props.default || '')
const valid = ref(!!props.default || !props.answerRequired)

const rules = computed(() => {
  return props.answerRequired ? [(v) => !!v || 'Required'] : [(v) => true]
})

function submitHandler() {
  emit('response', inputValue.value)
}

function cancelHandler() {
  emit('response', 'Cancel')
}
</script>

<style lang="scss" scoped>
.question {
  font-size: 1rem;
  white-space: pre-line;
}
</style>
