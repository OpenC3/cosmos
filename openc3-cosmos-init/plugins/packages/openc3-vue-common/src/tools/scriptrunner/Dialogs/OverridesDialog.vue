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
  <v-dialog v-model="show" width="1000">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span>Overrides</span>
        <v-spacer />
      </v-toolbar>
      <div class="pa-2">
        <v-card-text>
          <v-row class="ma-1">
            <v-btn
              color="primary"
              data-test="overrides-dialog-clear-all"
              @click="clearOverrides"
            >
              Clear All Overrides
            </v-btn>
            <v-spacer />
            <v-text-field
              v-model="search"
              label="Search"
              prepend-inner-icon="mdi-magnify"
              clearable
              variant="outlined"
              density="compact"
              single-line
              hide-details
            />
          </v-row>
          <v-data-table
            :headers="headers"
            :items="overrides"
            :search="search"
            :items-per-page-options="[100]"
            multi-sort
            density="compact"
          >
            <template #item.delete="{ item }">
              <v-btn
                icon="mdi-delete"
                variant="text"
                aria-label="Delete Override"
                @click="deleteOverride(item)"
              />
            </template>
          </v-data-table>
        </v-card-text>
      </div>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn
          variant="flat"
          data-test="overrides-dialog-ok"
          @click="show = !show"
        >
          Ok
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { OpenC3Api } from '@openc3/js-common/services'

const show = defineModel({ type: Boolean, required: true })

const api = new OpenC3Api()
const overrides = ref([])
const search = ref('')
const headers = [
  { text: 'Target', value: 'target_name' },
  { text: 'Packet', value: 'packet_name' },
  { text: 'Item', value: 'item_name' },
  { text: 'Type', value: 'value_type' },
  { text: 'Value', value: 'value' },
  { text: 'Delete', value: 'delete' },
]

async function getOverrides() {
  const result = await api.get_overrides()
  overrides.value = result
}

async function clearOverrides() {
  const items = [
    ...new Map(
      overrides.value.map((item) => [
        // Create a key based on target, packet, item so we remove duplicates
        `${item.target_name}__${item.packet_name}__${item.item_name}`,
        item,
      ]),
    ).values(),
  ]
  for (const item of items) {
    await api.normalize_tlm(
      item.target_name,
      item.packet_name,
      item.item_name,
      'ALL',
    )
    overrides.value = []
  }
}

async function deleteOverride(item) {
  await api.normalize_tlm(
    item.target_name,
    item.packet_name,
    item.item_name,
    item.value_type,
  )
  const index = overrides.value.indexOf(item)
  overrides.value.splice(index, 1)
}

onMounted(() => {
  getOverrides()
})
</script>
