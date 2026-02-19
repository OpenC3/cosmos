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
  <v-dialog v-model="show" persistent width="600" @keydown.esc="cancel">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span>Script Environment Variables</span>
        <v-spacer />
      </v-toolbar>
      <div class="pa-2">
        <v-card-text>
          <environment-chooser v-model="selected" />
        </v-card-text>
      </div>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn
          variant="outlined"
          data-test="environment-dialog-cancel"
          @click="cancel"
        >
          Cancel
        </v-btn>
        <v-btn
          variant="flat"
          data-test="environment-dialog-save"
          :disabled="!!inputError"
          @click="updateEnvironment"
        >
          Save
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { EnvironmentChooser } from '@/components'

const props = defineProps({
  inputEnvironment: {
    type: Array,
    required: true,
  },
})

const show = defineModel({ type: Boolean, required: true })
const emit = defineEmits(['environment'])

const selected = ref([])

function loadEnvironment() {
  selected.value = [...props.inputEnvironment]
}

function updateEnvironment() {
  emit('environment', selected.value)
  show.value = !show.value
}

function cancel() {
  show.value = !show.value
}

onMounted(() => {
  loadEnvironment()
})
</script>
