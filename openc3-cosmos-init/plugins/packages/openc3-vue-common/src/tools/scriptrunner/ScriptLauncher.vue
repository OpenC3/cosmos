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

<!--
# Landing page shown in the editor area when no script is open. Procedures
# are cards that open on click, like an app launcher.
-->
<template>
  <v-sheet class="h-100 overflow-y-auto pa-6" data-test="script-launcher">
    <div class="d-flex align-center flex-wrap ga-4 mb-4">
      <span class="text-h5">Open a procedure</span>
      <v-spacer />
      <v-text-field
        v-model="query"
        autofocus
        density="compact"
        variant="outlined"
        hide-details
        clearable
        placeholder="Search procedures"
        prepend-inner-icon="mdi-magnify"
        :min-width="240"
        :max-width="360"
        data-test="launcher-search"
      />
      <v-btn
        v-if="!readOnly"
        variant="tonal"
        prepend-icon="mdi-file-plus"
        text="Blank Script"
        data-test="launcher-blank"
        @click="emit('blank')"
      />
    </div>
    <v-progress-linear
      :active="loading"
      indeterminate
      color="primary"
      class="mb-4"
    />
    <template v-for="section in groups" :key="section.title">
      <div class="text-overline">{{ section.title }}</div>
      <v-row dense class="mb-4">
        <v-col
          v-for="item in section.items"
          :key="`${section.title}-${item.path}`"
          cols="12"
          sm="6"
          lg="4"
          xl="3"
        >
          <v-card
            variant="outlined"
            hover
            :loading="item.path === loadingFile"
            :data-test="`launcher-card-${item.path}`"
            @click="emit('select', item.path)"
          >
            <v-card-item>
              <template #prepend>
                <v-icon :icon="fileIcon(item.path)" />
              </template>
              <v-card-title class="text-subtitle-1">
                {{ item.name }}
              </v-card-title>
              <v-card-subtitle>{{ item.location }}</v-card-subtitle>
            </v-card-item>
            <v-card-text class="d-flex pt-0 text-caption text-medium-emphasis">
              <span>{{ item.language }}</span>
              <v-spacer />
              <span>{{ openedLabel(item.path) }}</span>
            </v-card-text>
          </v-card>
        </v-col>
      </v-row>
    </template>
    <div
      v-if="!groups.length && !loading"
      class="text-body-1 text-medium-emphasis"
    >
      {{ query ? 'No matching procedures' : 'No procedures found' }}
    </div>
  </v-sheet>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { formatDistanceToNow } from 'date-fns'
import { fileIcon } from '@/util/fileIcon'
import { searchProcedures } from '@/tools/scriptrunner/scriptFiles'
import { useProcedures } from '@/tools/scriptrunner/useProcedures'

const MAX_RESULTS = 60

const props = defineProps({
  loadingFile: {
    type: String,
    default: null,
  },
  readOnly: Boolean,
})

const emit = defineEmits(['select', 'blank', 'error'])

const { procedures, loading, load, sections, openedAt } = useProcedures()
const query = ref(null)

function openedLabel(path) {
  const time = openedAt.value[path]
  if (!time) return 'Not opened yet'
  return `Opened ${formatDistanceToNow(time, { addSuffix: true })}`
}

const groups = computed(() => {
  if (query.value?.trim()) {
    const items = searchProcedures(procedures.value, query.value, MAX_RESULTS)
    return items.length ? [{ title: 'Results', items }] : []
  }
  return sections()
})

onMounted(() => {
  load().catch((error) => {
    emit('error', `Failed to load procedures. ${error}`)
  })
})
</script>
