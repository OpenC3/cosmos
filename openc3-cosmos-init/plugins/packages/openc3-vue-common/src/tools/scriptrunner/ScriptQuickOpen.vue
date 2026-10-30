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
# Ctrl/Cmd-O quick open palette. Procedures are listed by name and target
# rather than by file path so users don't need to know the folder layout.
-->
<template>
  <v-dialog v-model="show" max-width="640" class="align-start">
    <v-card class="mt-12" data-test="quick-open">
      <v-text-field
        v-model="query"
        autofocus
        flat
        hide-details
        variant="solo"
        placeholder="Search procedures by name or target"
        prepend-inner-icon="mdi-magnify"
        data-test="quick-open-search"
        @keydown.down.prevent="move(1)"
        @keydown.up.prevent="move(-1)"
        @keydown.enter.prevent="openActive"
      />
      <v-progress-linear
        :active="loading"
        indeterminate
        color="primary"
        height="2"
      />
      <v-divider />
      <v-list
        density="compact"
        max-height="400"
        class="py-0"
        color="primary"
        data-test="quick-open-results"
      >
        <v-list-subheader v-if="!query && results.length">
          Recently opened
        </v-list-subheader>
        <v-list-item
          v-for="(item, index) in results"
          :key="item.path"
          :ref="(el) => (itemRefs[index] = el)"
          :title="item.name"
          :subtitle="item.location"
          :active="index === activeIndex"
          :variant="index === activeIndex ? 'flat' : 'text'"
          :data-test="`quick-open-item-${item.path}`"
          @click="open(item)"
          @mousemove="activeIndex = index"
        >
          <template #prepend>
            <v-icon :icon="fileIcon(item.path)" size="small" />
          </template>
          <template #append>
            <span class="text-caption text-medium-emphasis">
              {{ item.language }}
            </span>
          </template>
        </v-list-item>
        <v-list-item
          v-if="!results.length && !loading"
          :title="
            query ? 'No matching procedures' : 'Type to search procedures'
          "
          disabled
        />
      </v-list>
      <v-divider />
      <div class="d-flex ga-4 px-4 py-1 text-caption text-medium-emphasis">
        <span>↑↓ to navigate</span>
        <span>Enter to open</span>
        <span>Esc to close</span>
      </div>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { computed, nextTick, ref, watch } from 'vue'
import { fileIcon } from '@/util/fileIcon'
import {
  isListed,
  searchProcedures,
  toProcedure,
} from '@/tools/scriptrunner/scriptFiles'
import { useProcedures } from '@/tools/scriptrunner/useProcedures'

const MAX_RESULTS = 50

const props = defineProps({
  modelValue: Boolean,
  // Recently opened filenames, newest first
  recent: {
    type: Array,
    default: () => [],
  },
  // While a script runs only the files it has loaded can be shown
  runningFiles: {
    type: Array,
    default: () => [],
  },
  scriptActive: Boolean,
})

const emit = defineEmits(['update:modelValue', 'select', 'error'])

const show = computed({
  get: () => props.modelValue,
  set: (value) => emit('update:modelValue', value),
})
const query = ref('')
const { procedures, loading, load } = useProcedures()
const activeIndex = ref(0)
const itemRefs = ref([])

const available = computed(() => {
  if (!props.scriptActive) return procedures.value
  const running = new Set(props.runningFiles)
  return procedures.value.filter((item) => running.has(item.path))
})

const results = computed(() => {
  if (!query.value.trim()) {
    const byPath = new Map(available.value.map((item) => [item.path, item]))
    // Before the first load finishes show recents as-is, after that only
    // the ones that still exist (and are viewable while running)
    const loaded = procedures.value.length > 0
    return props.recent
      .filter((path) => isListed(path) && (!loaded || byPath.has(path)))
      .map((path) => byPath.get(path) || toProcedure(path))
  }
  return searchProcedures(available.value, query.value, MAX_RESULTS)
})

async function move(delta) {
  if (!results.value.length) return
  const count = results.value.length
  activeIndex.value = (activeIndex.value + delta + count) % count
  await nextTick()
  itemRefs.value[activeIndex.value]?.$el?.scrollIntoView({ block: 'nearest' })
}

function open(item) {
  show.value = false
  emit('select', item.path)
}

function openActive() {
  const item = results.value[activeIndex.value]
  if (item) open(item)
}

watch(results, () => {
  activeIndex.value = 0
  itemRefs.value = []
})

watch(show, (value) => {
  if (value) {
    query.value = ''
    // Show the previous list right away and refresh it in the background
    load().catch((error) => {
      emit('error', `Failed to load procedures. ${error}`)
    })
  }
})
</script>
