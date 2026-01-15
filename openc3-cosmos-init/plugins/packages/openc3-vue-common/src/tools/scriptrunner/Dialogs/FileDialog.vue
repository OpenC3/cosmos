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
          <span> File Dialog </span>
          <v-spacer />
        </v-toolbar>
        <div class="pa-2">
          <v-card-text>
            <v-row>
              <span class="text-h6">{{ title }}</span>
            </v-row>
            <v-row v-if="message">
              <span
                class="ma-3"
                style="white-space: pre-line"
                v-text="message"
              />
            </v-row>
            <v-row class="my-1">
              <v-file-input
                v-model="inputValue"
                label="Choose File"
                :rules="rules"
                autofocus
                data-test="file-input"
                :accept="filter"
                small-chips
                :multiple="multiple"
              />
            </v-row>
          </v-card-text>
        </div>
        <v-card-actions class="px-2">
          <v-spacer />
          <v-btn
            variant="outlined"
            data-test="file-cancel"
            @click="cancelHandler"
          >
            Cancel
          </v-btn>
          <v-btn
            variant="flat"
            type="submit"
            data-test="file-ok"
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
  title: {
    type: String,
    required: true,
  },
  message: {
    type: String,
    default: null,
  },
  filter: {
    type: String,
    default: '*',
  },
  multiple: {
    type: Boolean,
    default: false,
  },
})

const show = defineModel({ type: Boolean, default: false })

const emit = defineEmits(['response'])

const inputValue = ref(null)
const valid = ref(null)

const rules = computed(() => [
  (value) => {
    if (props.multiple) {
      return value.length != 0 || 'Required'
    } else {
      return !!value || 'Required'
    }
  },
])

const submitHandler = () => {
  // Ensure we send back an array of file names even in the single case
  // to make it easier to deal with a consistent result
  let files = inputValue.value
  if (!Array.isArray(files)) {
    files = [files]
  }
  emit('response', files)
}

const cancelHandler = () => {
  emit('response', 'Cancel')
}
</script>

<style scoped>
.title {
  font-size: 1.125rem;
  font-weight: bold;
  padding-bottom: 5px;
}
</style>
