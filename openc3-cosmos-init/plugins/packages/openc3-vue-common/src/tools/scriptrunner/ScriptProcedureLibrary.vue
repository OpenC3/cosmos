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
  <!-- Headers and items are flattened into rows and rendered with
       v-virtual-scroll so large libraries stay responsive -->
  <v-list
    density="compact"
    class="flex-grow-1 py-0 overflow-hidden"
    style="min-height: 0"
    color="primary"
    data-test="procedure-library"
  >
    <v-virtual-scroll
      :items="rows"
      item-key="key"
      height="100%"
      class="explorer-scroll"
    >
      <template #default="{ item: row }">
        <v-list-subheader
          v-if="row.header && row.section.grouped"
          class="library-section"
          :data-test="`library-section-${row.section.title}`"
          @click="toggleSection(row.section.title)"
        >
          <v-icon
            size="16"
            class="me-1"
            :icon="
              collapsed.has(row.section.title)
                ? 'mdi-chevron-right'
                : 'mdi-chevron-down'
            "
          />
          {{ row.section.title }}
        </v-list-subheader>
        <v-list-subheader v-else-if="row.header">
          {{ row.section.title }}
        </v-list-subheader>
        <v-list-item
          v-else
          :subtitle="row.section.grouped ? row.item.folders : row.item.location"
          :active="row.item.path === activeFile"
          :variant="row.item.path === activeFile ? 'flat' : 'text'"
          :base-color="runningSet.has(row.item.path) ? 'primary' : undefined"
          :disabled="scriptActive && !runningSet.has(row.item.path)"
          :data-test="`library-item-${row.item.path}`"
          @click="emit('select', row.item.path)"
          @contextmenu.prevent="emit('contextmenu', $event, row.item.path)"
        >
          <template #title>
            <span>
              {{ row.item.name }}
              <v-tooltip
                activator="parent"
                :open-delay="600"
                location="bottom start"
                :text="row.item.path"
              />
            </span>
          </template>
          <template #prepend>
            <v-icon :icon="itemIcon(row.item)" size="small" />
          </template>
          <template #append>
            <v-progress-circular
              v-if="row.item.path === loadingFile"
              indeterminate
              size="14"
              width="2"
              color="primary"
            />
            <span v-else class="text-caption text-medium-emphasis">
              {{ row.item.language }}
            </span>
          </template>
        </v-list-item>
      </template>
    </v-virtual-scroll>
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

const COLLAPSED_KEY = 'script_runner__library_collapsed'
// Typing narrows the results further
const MAX_RESULTS = 100

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

const emit = defineEmits(['select', 'error', 'contextmenu'])

const { procedures, loading, load, sections } = useProcedures()
const query = ref(null)
const collapsed = ref(loadCollapsed())

function loadCollapsed() {
  try {
    return new Set(JSON.parse(localStorage[COLLAPSED_KEY] || '[]'))
  } catch {
    return new Set()
  }
}

function saveCollapsed() {
  localStorage[COLLAPSED_KEY] = JSON.stringify([...collapsed.value])
}

function toggleSection(title) {
  if (collapsed.value.has(title)) {
    collapsed.value.delete(title)
  } else {
    collapsed.value.add(title)
  }
  saveCollapsed()
}

function collapseAll() {
  collapsed.value = new Set(sections().map((section) => section.title))
  saveCollapsed()
}

const runningSet = computed(() => new Set(props.runningFiles))

function itemIcon(item) {
  if (item.path === props.executingFile) return 'mdi-play-circle'
  return fileIcon(item.path)
}

const groups = computed(() => {
  if (query.value?.trim()) {
    const items = searchProcedures(procedures.value, query.value, MAX_RESULTS)
    return items.length ? [{ title: 'Results', items }] : []
  }
  return sections()
})

// One row per header and per visible item for the virtual scroller
const rows = computed(() => {
  const result = []
  for (const section of groups.value) {
    result.push({ key: `header-${section.title}`, header: true, section })
    if (section.grouped && collapsed.value.has(section.title)) continue
    for (const item of section.items) {
      result.push({ key: `${section.title}-${item.path}`, section, item })
    }
  }
  return result
})

function refresh() {
  return load().catch((error) => {
    emit('error', `Failed to load procedures. ${error}`)
  })
}

onMounted(refresh)

defineExpose({ refresh, collapseAll })
</script>

<style scoped>
.library-section {
  cursor: pointer;
  user-select: none;
}
</style>
