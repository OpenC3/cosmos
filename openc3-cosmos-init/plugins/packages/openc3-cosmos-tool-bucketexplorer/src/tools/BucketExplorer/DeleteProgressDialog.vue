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
  <v-dialog
    :model-value="modelValue"
    :max-width="complete ? 600 : 400"
    persistent
    no-click-animation
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span>{{ complete ? 'Delete Results' : 'Deleting Files' }}</span>
        <v-spacer />
      </v-toolbar>
      <v-card-text>
        <div v-if="!complete" class="pa-3">
          <div class="mb-2" data-test="delete-progress-text">
            {{ done }} / {{ total }} files
          </div>
          <v-progress-linear
            :model-value="total ? (done / total) * 100 : 0"
            color="success"
            height="14"
            striped
            data-test="delete-progress-bar"
          />
        </div>
        <div v-else class="pa-3" data-test="delete-results">
          <div
            :class="
              failed.length > 0
                ? 'mb-2 d-flex align-center'
                : 'd-flex align-center'
            "
          >
            <rux-status
              :status="failed.length > 0 ? 'caution' : 'normal'"
              class="mr-2 status-icon"
            />
            <span>
              Deleted {{ total - failed.length }} of {{ total }} file{{
                total > 1 ? 's' : ''
              }}
            </span>
          </div>
          <div v-if="failed.length > 0">
            <div class="mt-3 mb-1 text-error">
              Failed ({{ failed.length }}):
            </div>
            <v-list
              density="compact"
              max-height="300"
              class="failed-list"
              data-test="delete-failed-list"
            >
              <v-list-item
                v-for="(name, index) in failed"
                :key="index"
                :title="name"
              >
                <template #prepend>
                  <rux-status status="critical" class="mr-2 status-icon" />
                </template>
              </v-list-item>
            </v-list>
          </div>
          <v-row class="mt-4">
            <v-spacer />
            <v-btn
              color="primary"
              class="mx-2"
              data-test="delete-results-ok"
              @click="$emit('update:modelValue', false)"
            >
              OK
            </v-btn>
          </v-row>
        </div>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
export default {
  props: {
    modelValue: {
      type: Boolean,
      default: false,
    },
    total: {
      type: Number,
      default: 0,
    },
    done: {
      type: Number,
      default: 0,
    },
    failed: {
      type: Array,
      default: () => [],
    },
    complete: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update:modelValue'],
}
</script>

<style scoped>
.failed-list {
  background-color: rgba(var(--v-theme-error), 0.05);
  border: 1px solid rgba(var(--v-theme-error), 0.2);
  border-radius: 4px;
}
.status-icon {
  display: inline-flex;
  align-items: center;
  line-height: 1;
}
</style>
