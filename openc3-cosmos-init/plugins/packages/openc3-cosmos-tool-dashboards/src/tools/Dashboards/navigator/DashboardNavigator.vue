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

<template>
  <v-dialog
    v-model="show"
    :fullscreen="fullscreen"
    :max-width="fullscreen ? undefined : 1040"
    :content-class="fullscreen ? undefined : 'db-top-dialog'"
    scrollable
    @after-enter="reveal(highlight)"
    @after-leave="reset"
  >
    <v-card
      class="dashboards-root d-flex flex-column"
      :style="fullscreen ? null : { maxHeight: '84vh' }"
      data-test="dashboard-navigator"
    >
      <div class="d-flex align-center ga-3 pa-3 border-b">
        <v-text-field
          :model-value="search"
          placeholder="Search all dashboards"
          prepend-inner-icon="mdi-magnify"
          density="comfortable"
          variant="outlined"
          color="secondary"
          hide-details
          clearable
          :autofocus="!fullscreen"
          class="search"
          data-test="navigator-search"
          @keydown="onKey"
          @update:model-value="setSearch"
        />
        <v-btn
          v-if="!lean"
          variant="outlined"
          size="large"
          prepend-icon="mdi-plus"
          data-test="navigator-new"
          @click="create"
        >
          New
        </v-btn>
        <v-btn
          icon="mdi-close"
          variant="text"
          aria-label="Close"
          @click="show = false"
        />
      </div>
      <div class="d-flex flex-grow-1 min-h-0">
        <!-- Starred, then one folder per target -->
        <nav
          v-if="showPlaces"
          :class="[
            'overflow-y-auto',
            lean ? 'flex-grow-1' : 'places flex-shrink-0 border-e',
          ]"
          aria-label="Dashboard folders"
        >
          <v-list
            density="compact"
            nav
            color="secondary"
            class="bg-transparent"
          >
            <v-list-item
              :active="activeView === 'starred'"
              :class="{
                'key-focus': placesFocused && activeView === 'starred',
              }"
              prepend-icon="mdi-star-outline"
              title="Starred"
              data-test="navigator-place-starred"
              @click="view = 'starred'"
            >
              <template #append>
                <span class="text-caption text-medium-emphasis num">
                  {{ starred.length }}
                </span>
              </template>
            </v-list-item>
            <v-list-subheader>Folders</v-list-subheader>
            <v-list-item
              v-for="folder in folders"
              :key="folder.target"
              :active="`folder:${folder.target}` === activeView"
              :class="{
                'key-focus':
                  placesFocused && `folder:${folder.target}` === activeView,
              }"
              :prepend-icon="
                `folder:${folder.target}` === activeView
                  ? 'mdi-folder-open-outline'
                  : 'mdi-folder-outline'
              "
              :disabled="!folder.count"
              :data-test="`navigator-folder-${folder.target}`"
              @click="view = `folder:${folder.target}`"
            >
              <v-list-item-title class="mono">
                {{ folder.target }}/
              </v-list-item-title>
              <template #append>
                <span class="text-caption text-medium-emphasis num">
                  {{ folder.count }}
                </span>
              </template>
            </v-list-item>
          </v-list>
        </nav>
        <section
          v-if="showRows"
          class="d-flex flex-column flex-grow-1 min-w-0"
          data-test="navigator-pane"
        >
          <div class="d-flex align-center ga-2 px-4 py-2 border-b">
            <v-btn
              v-if="lean"
              icon="mdi-arrow-left"
              variant="text"
              size="small"
              aria-label="Folders"
              @click="back"
            />
            <v-icon :icon="heading.icon" size="18" />
            <span
              class="text-subtitle-1 font-weight-bold"
              :class="heading.class"
            >
              {{ heading.label }}
            </span>
            <span
              v-if="heading.path"
              class="mono text-body-2 text-medium-emphasis text-truncate"
            >
              {{ heading.path }}
            </span>
            <v-spacer />
            <span
              class="text-body-2 text-medium-emphasis text-no-wrap"
              data-test="navigator-count"
            >
              {{ rows.length }} dashboard{{ rows.length === 1 ? '' : 's' }}
            </span>
          </div>
          <div
            v-if="!rows.length"
            class="d-flex flex-column align-center ga-3 pa-12 text-body-1 text-medium-emphasis text-center"
          >
            <v-icon :icon="empty.icon" size="48" />
            {{ empty.text }}
            <v-btn
              v-if="!dashboards.length && !lean"
              variant="outlined"
              prepend-icon="mdi-plus"
              @click="create"
            >
              Create one
            </v-btn>
          </div>
          <v-list v-else class="flex-grow-1 min-h-0 pa-0 bg-transparent">
            <v-virtual-scroll
              ref="scroller"
              :items="rows"
              :item-height="ROW_HEIGHT"
              class="h-100"
            >
              <template #default="{ item, index }">
                <navigator-row
                  :dashboard-key="item"
                  :starred="starredKeys.has(item)"
                  :current="item === currentKey"
                  :highlighted="!placesFocused && index === highlight"
                  :show-folder="!activeView.startsWith('folder:')"
                  :lean="lean"
                  @open="open(item)"
                  @star="toggleStar(item)"
                  @duplicate="duplicate(item)"
                  @folder="openFolder(item)"
                />
              </template>
            </v-virtual-scroll>
          </v-list>
        </section>
      </div>
      <div
        v-if="!lean"
        class="d-flex align-center ga-4 px-4 py-2 border-t text-body-2 text-medium-emphasis"
      >
        <span>
          <kbd class="db-kbd">↑</kbd> <kbd class="db-kbd">↓</kbd> move ·
          <kbd class="db-kbd">←</kbd> <kbd class="db-kbd">→</kbd> folders /
          dashboards · <kbd class="db-kbd">Enter</kbd> opens
        </span>
        <v-spacer />
        <span>Stars are saved in this browser only</span>
      </div>
    </v-card>
  </v-dialog>
</template>

<script setup>
import { computed, ref, shallowRef, useTemplateRef } from 'vue'
import NavigatorRow from './NavigatorRow.vue'
import { loadSummaries, navigator, toggleStar } from './navigatorStore'

// Matches NavigatorRow's min-height
const ROW_HEIGHT = 56

// Find and open dashboards like a file explorer: Starred on the left, then
// a folder per target, since each dashboard is a file saved
// in a target (TARGET/dashboards/name.txt). Search covers every folder, and
// the folders then count the matches. Rows scroll virtually and fetch their
// titles as they're shown, so hundreds of dashboards stay quick.
const props = defineProps({
  dashboards: { type: Array, default: () => [] },
  currentKey: { type: String, default: null },
  fullscreen: Boolean,
  // Phones: just find and open dashboards, no creating or duplicating.
  // The folders and the list take turns on the screen.
  lean: Boolean,
})
const emit = defineEmits(['open', 'new', 'duplicate'])
const show = defineModel({ type: Boolean })
// Every dashboard's title, icon and panel count, in one request
loadSummaries()

const scroller = useTemplateRef('scroller')
// Which side the arrow keys move in: 'places' (Starred and the folders) or
// 'rows' (the dashboards). Searching always moves in the results.
// Starts in the dashboards, on the one that's open (see highlight)
const pane = ref('rows')
const search = ref('')
// 'starred' or 'folder:TARGET'; null until chosen
const view = ref(null)
// Row the arrow keys are on, for the rows it was moved on: any new rows
// start back at the top
const cursor = shallowRef({ rows: null, index: 0 })
const highlight = computed(() => {
  if (cursor.value.rows === rows.value) return cursor.value.index
  // Until the keys move it: the open dashboard, when it's listed
  return Math.max(0, rows.value.indexOf(props.currentKey))
})

const query = computed(() => (search.value || '').trim().toLowerCase())
// Dashboards matching the search, in name order
const matches = computed(() => {
  const words = query.value.split(/\s+/).filter(Boolean)
  const keys = words.length
    ? props.dashboards.filter((key) => {
        const haystack =
          `${key} ${navigator.info[key]?.title || ''}`.toLowerCase()
        return words.every((word) => haystack.includes(word))
      })
    : props.dashboards
  return [...keys].sort()
})
// Keeps starred in the order they were starred
const starred = computed(() => {
  const keys = new Set(matches.value)
  return navigator.starred.filter((key) => keys.has(key))
})
// For each row's star
const starredKeys = computed(() => new Set(navigator.starred))
// Every target with dashboards, counting the matches
const folders = computed(() => {
  const counts = {}
  for (const key of props.dashboards) counts[key.split('/')[0]] = 0
  for (const key of matches.value) counts[key.split('/')[0]]++
  return Object.keys(counts)
    .sort()
    .map((target) => ({ target, count: counts[target] }))
})
// Starred, else the current dashboard's folder, else the first folder
const defaultView = computed(() => {
  if (navigator.starred.length) return 'starred'
  const target =
    props.currentKey?.split('/')[0] ??
    folders.value.find((folder) => folder.count)?.target
  return target ? `folder:${target}` : 'starred'
})
// Searching shows every match ('search') unless a folder is picked
const activeView = computed(() => {
  if (view.value) return view.value
  if (query.value) return 'search'
  if (props.lean) return null
  return defaultView.value
})
const rows = computed(() => {
  const active = activeView.value
  if (active === 'starred') return starred.value
  if (active?.startsWith('folder:')) {
    const prefix = `${active.slice(7)}/`
    return matches.value.filter((key) => key.startsWith(prefix))
  }
  return matches.value
})
const heading = computed(() => {
  const active = activeView.value
  if (active?.startsWith('folder:')) {
    const target = active.slice(7)
    return {
      icon: 'mdi-folder-open-outline',
      label: target,
      path: `${target}/dashboards/`,
      class: 'mono',
    }
  }
  if (active === 'search') {
    return { icon: 'mdi-magnify', label: 'Search results' }
  }
  return { icon: 'mdi-star-outline', label: 'Starred' }
})
const empty = computed(() => {
  if (!props.dashboards.length) {
    return {
      icon: 'mdi-view-dashboard-outline',
      text: 'No dashboards yet.',
    }
  }
  if (query.value) {
    return {
      icon: 'mdi-magnify',
      text: `No dashboards match "${search.value}"`,
    }
  }
  if (activeView.value === 'starred') {
    return {
      icon: 'mdi-star-outline',
      text: 'Star a dashboard to keep it here.',
    }
  }
  return { icon: 'mdi-folder-outline', text: 'No dashboards in this folder.' }
})
const placesFocused = computed(
  () =>
    (pane.value === 'places' || !rows.value.length) &&
    !query.value &&
    !props.lean,
)
// Starred, then the folders with dashboards, as listed
const placeViews = computed(() => [
  'starred',
  ...folders.value
    .filter((folder) => folder.count)
    .map((folder) => `folder:${folder.target}`),
])
// Phones show the folders, or the list once one's picked or searching
const showPlaces = computed(() => !props.lean || activeView.value === null)
const showRows = computed(() => !props.lean || activeView.value !== null)

// A new search starts from every match; the folders narrow it
function setSearch(value) {
  const before = query.value
  search.value = value
  if (!before && query.value) view.value = null
}
// Closed: the next open starts with a fresh search
function reset() {
  search.value = ''
  pane.value = 'rows'
  cursor.value = { rows: null, index: 0 }
  if (props.lean) view.value = null
}
function open(key) {
  emit('open', key)
  show.value = false
}
function openFolder(key) {
  view.value = `folder:${key.split('/')[0]}`
}
function back() {
  view.value = null
  search.value = ''
}
// Like a file explorer: up / down move in the focused pane (Starred and
// the folders, or the dashboards), right / left switch panes, and Enter
// goes into a folder or opens a dashboard. While searching the dashboards
// pane has the keys, so left / right still move the text cursor.
function onKey(event) {
  const step = { ArrowDown: 1, ArrowUp: -1 }[event.key]
  if (placesFocused.value) {
    if (step) {
      event.preventDefault()
      const views = placeViews.value
      const at = views.indexOf(activeView.value)
      view.value =
        views[at < 0 ? 0 : Math.min(views.length - 1, Math.max(0, at + step))]
    } else if (
      (event.key === 'ArrowRight' || event.key === 'Enter') &&
      rows.value.length
    ) {
      event.preventDefault()
      pane.value = 'rows'
    }
    return
  }
  if (event.key === 'Enter') {
    const key = rows.value[highlight.value]
    if (key) open(key)
    return
  }
  if (event.key === 'ArrowLeft' && !search.value) {
    event.preventDefault()
    pane.value = 'places'
    return
  }
  const last = rows.value.length - 1
  if (!step || last < 0) return
  event.preventDefault()
  const index = Math.min(last, Math.max(0, highlight.value + step))
  cursor.value = { rows: rows.value, index }
  reveal(index)
}
// Scroll just enough to show the row, rather than to the top
function reveal(index) {
  const box = scroller.value?.$el
  if (!box) return
  const top = index * ROW_HEIGHT
  if (top < box.scrollTop) box.scrollTop = top
  else if (top + ROW_HEIGHT > box.scrollTop + box.clientHeight) {
    box.scrollTop = top + ROW_HEIGHT - box.clientHeight
  }
}
function create() {
  emit('new')
  show.value = false
}
function duplicate(key) {
  emit('duplicate', key)
  show.value = false
}
</script>

<style scoped>
.places {
  width: 220px;
}
.search :deep(input) {
  font-size: 16px;
}
/* It's focused whenever the navigator opens, so keep the focus outline as
   thin as the resting one rather than a heavy white ring */
.search :deep(.v-field--focused .v-field__outline) {
  --v-field-border-width: 1px;
}
.key-focus {
  outline: 1px solid rgba(var(--v-theme-secondary), 0.6);
  outline-offset: -1px;
}
</style>
