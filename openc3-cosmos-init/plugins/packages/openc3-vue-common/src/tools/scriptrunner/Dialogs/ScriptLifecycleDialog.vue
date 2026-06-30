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
  <v-dialog v-model="show" scrollable width="1100">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span> Script Lifecycle </span>
        <v-spacer />
      </v-toolbar>
      <v-card-text style="max-height: 80vh; overflow: auto">
        <v-row no-gutters class="align-center mt-2">
          <span class="mr-2">{{ filename }}</span>
          <v-chip
            :color="stateColor(state)"
            variant="flat"
            size="small"
            data-test="lifecycle-state-chip"
            class="ml-2"
          >
            {{ stateLabel(state) }}
          </v-chip>
        </v-row>
        <div v-if="error" class="text-red mt-2" data-test="lifecycle-error">
          {{ error }}
        </div>
        <template v-if="allowedStates.length !== 0">
          <v-row no-gutters class="mt-4">
            <v-select
              v-model="newState"
              label="Move to"
              :items="allowedStates"
              item-title="text"
              item-value="value"
              density="compact"
              variant="outlined"
              hide-details
              style="max-width: 250px"
              data-test="lifecycle-new-state"
            />
          </v-row>
          <v-textarea
            v-model="comment"
            class="mt-4"
            label="Comment (optional)"
            rows="2"
            density="compact"
            variant="outlined"
            counter="1000"
            maxlength="1000"
            data-test="lifecycle-comment"
          />
        </template>
        <div v-else class="mt-4">
          You do not have permission to change this script's lifecycle.
          <template v-if="state === 'review'">
            Only admins can approve scripts.
          </template>
          <template v-else-if="state === 'approved'">
            Only admins can move approved scripts back to review.
          </template>
        </div>
        <v-data-table
          class="mt-4"
          :headers="historyHeaders"
          :items="sortedHistory"
          :items-per-page="10"
          density="compact"
          data-test="lifecycle-history"
        >
          <template #item.time="{ item }">
            {{ timeFilters.formatTimestamp(item.time, timeZone) }}
          </template>
          <template #item.from="{ item }">
            {{ stateLabel(item.from) }} &rarr; {{ stateLabel(item.to) }}
          </template>
          <template #no-data>
            <span> No lifecycle changes yet </span>
          </template>
        </v-data-table>
      </v-card-text>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn
          variant="outlined"
          text="Cancel"
          data-test="lifecycle-cancel"
          @click="show = false"
        />
        <v-btn
          v-if="allowedStates.length !== 0"
          variant="flat"
          color="primary"
          text="Submit"
          :disabled="!newState"
          data-test="lifecycle-submit"
          @click="submit"
        />
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { computed, ref } from 'vue'
import { Api } from '@openc3/js-common/services'
import { useTimeFilters } from '@/composables'
import {
  LIFECYCLE_STATE_LABELS,
  lifecycleStateColor as stateColor,
  lifecycleStateLabel as stateLabel,
} from '@/tools/scriptrunner/useScriptLifecycle'

const props = defineProps({
  filename: {
    type: String,
    required: true,
  },
  state: {
    type: String,
    required: true,
  },
  history: {
    type: Array,
    default: () => [],
  },
  isAdmin: {
    type: Boolean,
    default: false,
  },
  canEdit: {
    type: Boolean,
    default: false,
  },
  timeZone: {
    type: String,
    default: 'local',
  },
})

const emit = defineEmits(['updated'])

const show = defineModel({ type: Boolean, required: true })

const timeFilters = useTimeFilters()

const newState = ref(null)
const comment = ref('')
const error = ref(null)
const historyHeaders = [
  { title: 'Date / Time', key: 'time' },
  { title: 'Change', key: 'from' },
  { title: 'User', key: 'user' },
  { title: 'Comment', key: 'comment' },
]

// Transitions available to this user from the current state.
// dev <-> review requires edit permission, review <-> approved requires admin.
const allowedStates = computed(() => {
  let states = []
  switch (props.state) {
    case 'development':
      if (props.canEdit) {
        states.push('review')
      }
      if (props.isAdmin) {
        states.push('approved')
      }
      break
    case 'review':
      if (props.canEdit) {
        states.push('development')
      }
      if (props.isAdmin) {
        states.push('approved')
      }
      break
    case 'approved':
      if (props.isAdmin) {
        states.push('review', 'development')
      }
      break
  }
  return states.map((state) => {
    return { text: LIFECYCLE_STATE_LABELS[state], value: state }
  })
})

const sortedHistory = computed(() => {
  return [...props.history].reverse() // newest first
})

function submit() {
  error.value = null
  Api.post(`/script-api/scripts/${props.filename}/lifecycle`, {
    data: {
      state: newState.value,
      comment: comment.value.trim(),
    },
  })
    .then((response) => {
      newState.value = null
      comment.value = ''
      emit('updated', response.data)
    })
    .catch((err) => {
      error.value =
        err.response?.data?.message || `Failed to change lifecycle: ${err}`
    })
}
</script>
