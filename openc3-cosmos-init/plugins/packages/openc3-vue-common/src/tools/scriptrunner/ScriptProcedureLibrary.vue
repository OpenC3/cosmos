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
# Explorer view that lists procedures by name grouped by target
# instead of as a folder tree
-->
<template>
  <div class="px-2 pb-3">
    <v-text-field
      v-model="query"
      density="compact"
      variant="outlined"
      hide-details
      clearable
      placeholder="Search procedures"
      prepend-inner-icon="mdi-magnify"
      data-test="library-search"
    />
  </div>
  <v-list
    density="compact"
    class="flex-grow-1 py-0"
    color="primary"
    data-test="procedure-library"
  >
    <template v-for="section in groups" :key="section.title">
      <v-list-subheader>{{ section.title }}</v-list-subheader>
      <v-list-item
        v-for="item in section.items"
        :key="`${section.title}-${item.path}`"
        :title="item.name"
        :subtitle="section.grouped ? item.folders : item.location"
        :active="item.path === activeFile"
        :variant="item.path === activeFile ? 'flat' : 'text'"
        :base-color="runningSet.has(item.path) ? 'primary' : undefined"
        :disabled="scriptActive && !runningSet.has(item.path)"
        :data-test="`library-item-${item.path}`"
        @click="emit('select', item.path)"
      >
        <template #prepend>
          <v-icon :icon="itemIcon(item)" size="small" />
        </template>
        <template #append>
          <v-progress-circular
            v-if="item.path === loadingFile"
            indeterminate
            size="14"
            width="2"
            color="primary"
          />
          <span v-else class="text-caption text-medium-emphasis">
            {{ item.language }}
          </span>
        </template>
      </v-list-item>
    </template>
    <v-list-item
      v-if="!groups.length && !loading"
      :title="query ? 'No matching procedures' : 'No procedures found'"
      disabled
    />
  </v-list>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue'
import { fileIcon } from '@/util/fileIcon'
import { searchProcedures } from '@/tools/scriptrunner/scriptFiles'
import { useProcedures } from '@/tools/scriptrunner/useProcedures'

const props = defineProps({
  activeFile: {
    type: String,
    default: null,
  },
  executingFile: {
    type: String,
    default: null,
  },
  runningFiles: {
    type: Array,
    default: () => [],
  },
  loadingFile: {
    type: String,
    default: null,
  },
  scriptActive: Boolean,
})

const emit = defineEmits(['select', 'error'])

const { procedures, loading, load, sections } = useProcedures()
const query = ref(null)

const runningSet = computed(() => new Set(props.runningFiles))

function itemIcon(item) {
  if (item.path === props.executingFile) return 'mdi-play-circle'
  return fileIcon(item.path)
}

const groups = computed(() => {
  if (query.value?.trim()) {
    const items = searchProcedures(procedures.value, query.value)
    return items.length ? [{ title: 'Results', items }] : []
  }
  return sections()
})

function refresh() {
  return load().catch((error) => {
    emit('error', `Failed to load procedures. ${error}`)
  })
}

onMounted(refresh)

defineExpose({ refresh })
</script>
