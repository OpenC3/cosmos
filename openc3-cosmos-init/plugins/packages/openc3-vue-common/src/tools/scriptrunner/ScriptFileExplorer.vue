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
# VS Code style file tree shown alongside the Script Runner editor.
# The tree is flattened into rows and rendered with v-virtual-scroll so
# large script collections stay responsive. Expanded folders persist in
# localStorage so the tree looks the same the next time it's opened.
-->
<template>
  <v-sheet
    class="script-explorer d-flex flex-column h-100 border-e"
    data-test="script-explorer"
  >
    <div class="d-flex align-center px-2">
      <span class="text-overline">
        {{ mode === 'files' ? 'Files' : 'Library' }}
      </span>
      <v-spacer />
      <v-tooltip :open-delay="600" location="bottom" text="Files">
        <template #activator="{ props: tooltipProps }">
          <v-btn
            v-bind="tooltipProps"
            icon="mdi-file-tree"
            variant="text"
            size="x-small"
            :color="mode === 'files' ? 'primary' : undefined"
            aria-label="Files"
            data-test="explorer-mode-files"
            @click="mode = 'files'"
          />
        </template>
      </v-tooltip>
      <v-tooltip :open-delay="600" location="bottom" text="Library">
        <template #activator="{ props: tooltipProps }">
          <v-btn
            v-bind="tooltipProps"
            icon="mdi-bookshelf"
            variant="text"
            size="x-small"
            :color="mode === 'library' ? 'primary' : undefined"
            aria-label="Library"
            data-test="explorer-mode-library"
            @click="mode = 'library'"
          />
        </template>
      </v-tooltip>
      <v-divider vertical class="mx-1 my-2" />
      <v-tooltip
        :open-delay="600"
        location="bottom"
        :text="mode === 'files' ? 'Collapse Folders' : 'Collapse Collections'"
      >
        <template #activator="{ props: tooltipProps }">
          <v-btn
            v-bind="tooltipProps"
            icon="mdi-collapse-all-outline"
            variant="text"
            size="x-small"
            :aria-label="
              mode === 'files' ? 'Collapse Folders' : 'Collapse Collections'
            "
            data-test="explorer-collapse"
            @click="mode === 'files' ? collapseAll() : library?.collapseAll()"
          />
        </template>
      </v-tooltip>
      <v-tooltip :open-delay="600" location="bottom" text="Refresh">
        <template #activator="{ props: tooltipProps }">
          <v-btn
            v-bind="tooltipProps"
            icon="mdi-refresh"
            variant="text"
            size="x-small"
            aria-label="Refresh Explorer"
            data-test="explorer-refresh"
            @click="mode === 'files' ? refresh() : library?.refresh()"
          />
        </template>
      </v-tooltip>
      <v-tooltip :open-delay="600" location="bottom" text="Hide Explorer">
        <template #activator="{ props: tooltipProps }">
          <v-btn
            v-bind="tooltipProps"
            icon="mdi-chevron-double-left"
            variant="text"
            size="x-small"
            aria-label="Hide Explorer"
            data-test="explorer-hide"
            @click="emit('hide')"
          />
        </template>
      </v-tooltip>
    </div>
    <v-progress-linear
      :active="loading || libraryLoading || !!loadingFile"
      indeterminate
      color="primary"
      height="2"
    />
    <script-procedure-library
      v-if="mode === 'library'"
      ref="library"
      :active-file="activeFile"
      :executing-file="executingFile"
      :running-files="runningFiles"
      :loading-file="loadingFile"
      :script-active="scriptActive"
      @select="emit('select', $event)"
      @error="emit('error', $event)"
      @contextmenu="showContextMenu"
    />
    <div v-if="mode === 'files'" class="px-2 pb-3">
      <v-text-field
        v-model="search"
        density="compact"
        variant="outlined"
        hide-details
        clearable
        placeholder="Search files"
        prepend-inner-icon="mdi-magnify"
        data-test="explorer-search"
        @keydown.down.prevent="focusRow(rows[0]?.path)"
      />
    </div>
    <!-- v-list moves focus with Up/Down/Home/End, we add Left/Right -->
    <v-list
      v-if="mode === 'files'"
      ref="tree"
      density="compact"
      class="flex-grow-1 py-0 overflow-hidden"
      style="min-height: 0"
      color="primary"
      @keydown="treeKeydown"
    >
      <v-virtual-scroll
        ref="scroller"
        :items="rows"
        :item-height="ROW_HEIGHT"
        height="100%"
        class="explorer-scroll"
      >
        <template #default="{ item }">
          <v-list-item
            :active="isActive(item.node)"
            :variant="isActive(item.node) ? 'flat' : 'text'"
            :base-color="isRunning(item.node) ? 'primary' : undefined"
            :disabled="isDisabled(item.node)"
            :height="ROW_HEIGHT"
            :min-height="ROW_HEIGHT"
            :style="{ paddingInlineStart: `${item.depth * 12 + 4}px` }"
            rounded="0"
            class="py-0"
            :data-test="`explorer-row-${item.node.path}`"
            :data-path="item.node.path"
            @click="rowClick(item.node)"
            @contextmenu="rowContextMenu($event, item.node)"
          >
            <template #title>
              <span>
                {{ item.node.name }}
                <v-tooltip
                  activator="parent"
                  :open-delay="600"
                  location="bottom start"
                  :text="item.node.path"
                />
              </span>
            </template>
            <template #prepend>
              <div class="d-flex align-center me-1">
                <v-icon
                  size="16"
                  :icon="chevronIcon(item)"
                  :class="{ 'opacity-0': !item.node.children }"
                />
                <v-icon size="16" class="ms-1" :icon="nodeIcon(item)" />
              </div>
            </template>
            <template #append>
              <v-progress-circular
                v-if="item.node.path === loadingFile"
                indeterminate
                size="14"
                width="2"
                color="primary"
                data-test="explorer-loading"
              />
              <span
                v-if="item.node.modified"
                class="text-caption font-weight-bold text-warning"
                title="Modified on the server"
              >
                M
              </span>
            </template>
          </v-list-item>
        </template>
      </v-virtual-scroll>
    </v-list>
    <v-menu v-model="contextMenu.show" :target="[contextMenu.x, contextMenu.y]">
      <v-list density="compact" data-test="explorer-context-menu">
        <v-list-item
          title="Save As..."
          prepend-icon="mdi-content-save"
          :disabled="scriptActive || readOnly"
          data-test="explorer-context-save-as"
          @click="emit('save-as', contextMenu.path)"
        />
      </v-list>
    </v-menu>
  </v-sheet>
</template>

<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue'
import { fileIcon } from '@/util/fileIcon'
import {
  isBinary,
  isListed,
  isProcedure,
  loadProcedures,
  loadTargets,
} from '@/tools/scriptrunner/scriptFiles'
import { useProcedures } from '@/tools/scriptrunner/useProcedures'
import ScriptProcedureLibrary from '@/tools/scriptrunner/ScriptProcedureLibrary.vue'

const ROW_HEIGHT = 22
const EXPANDED_KEY = 'script_runner__explorer_expanded'
const MODE_KEY = 'script_runner__explorer_mode'

const props = defineProps({
  // File currently displayed in the editor
  activeFile: {
    type: String,
    default: null,
  },
  // File the running script is currently executing
  executingFile: {
    type: String,
    default: null,
  },
  // Files the running script has touched, the only ones that can be
  // displayed while a script is running
  runningFiles: {
    type: Array,
    default: () => [],
  },
  // File currently being opened, shows a loading indicator
  loadingFile: {
    type: String,
    default: null,
  },
  scriptActive: Boolean,
  readOnly: Boolean,
})

const emit = defineEmits(['select', 'hide', 'error', 'save-as'])

const scroller = ref(null)
const library = ref(null)
const tree = ref(null)
// 'files' shows the folder tree, 'library' lists procedures by name
const mode = ref(localStorage[MODE_KEY] === 'library' ? 'library' : 'files')
const {
  procedures,
  loading: libraryLoading,
  load: loadLibrary,
} = useProcedures()
const items = ref([])
const search = ref(null)
const loading = ref(false)
const expanded = ref(loadExpanded())
const contextMenu = ref({ show: false, x: 0, y: 0, path: null })

// Files get our menu, folders keep the browser's
function rowContextMenu(event, node) {
  if (node.children || isBinary(node.path)) return
  event.preventDefault()
  showContextMenu(event, node.path)
}

function showContextMenu(event, path) {
  contextMenu.value = { show: true, x: event.clientX, y: event.clientY, path }
}

function loadExpanded() {
  try {
    return new Set(JSON.parse(localStorage[EXPANDED_KEY] || '[]'))
  } catch {
    return new Set()
  }
}

function saveExpanded() {
  localStorage[EXPANDED_KEY] = JSON.stringify([...expanded.value])
}

const runningSet = computed(() => new Set(props.runningFiles))

// Precompute which nodes match the search so filtering stays linear
const matching = computed(() => {
  const term = search.value?.toLowerCase()
  if (!term) return null
  const result = new Set()
  const walk = (node) => {
    let match = node.path.toLowerCase().includes(term)
    if (node.children) {
      for (const child of node.children) {
        // Evaluate every child so nested matches are all recorded
        match = walk(child) || match
      }
    }
    if (match) result.add(node)
    return match
  }
  items.value.forEach(walk)
  return result
})

const rows = computed(() => {
  const result = []
  const walk = (nodes, depth) => {
    for (const node of nodes) {
      if (matching.value && !matching.value.has(node)) continue
      const open = !!(
        node.children &&
        (matching.value || expanded.value.has(node.path))
      )
      result.push({ node, depth, open, path: node.path })
      if (open) walk(node.children, depth + 1)
    }
  }
  walk(items.value, 0)
  return result
})

function nodeIcon(item) {
  if (item.node.children) {
    return item.open ? 'mdi-folder-open' : 'mdi-folder'
  }
  if (item.node.path === props.executingFile) {
    return 'mdi-play-circle'
  }
  return fileIcon(item.node.name)
}

function isDisabled(node) {
  if (node.children) return false
  if (isBinary(node.path)) return true
  return props.scriptActive && !runningSet.value.has(node.path)
}

function isActive(node) {
  return !node.children && node.path === props.activeFile
}

function isRunning(node) {
  return !node.children && runningSet.value.has(node.path)
}

function chevronIcon(item) {
  return item.open ? 'mdi-chevron-down' : 'mdi-chevron-right'
}

function toggle(node) {
  if (expanded.value.has(node.path)) {
    expanded.value.delete(node.path)
  } else {
    expanded.value.add(node.path)
  }
  saveExpanded()
}

function rowClick(node) {
  if (node.children) {
    // Searching force-opens every matching folder so toggling does nothing
    if (!matching.value) toggle(node)
    return
  }
  emit('select', node.path)
}

// Scroll a row into view (the virtual scroller may not have rendered it)
// and give it keyboard focus
async function focusRow(path) {
  const index = rows.value.findIndex((row) => row.path === path)
  if (index === -1) return
  scroller.value?.scrollToIndex(index)
  await nextTick()
  await new Promise((resolve) => requestAnimationFrame(resolve))
  tree.value?.$el
    .querySelector(`[data-path="${CSS.escape(path)}"]`)
    ?.focus({ preventScroll: true })
}

// VS Code style: Right opens a folder or moves into it, Left closes a
// folder or moves to the parent folder
function treeKeydown(event) {
  if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return
  const path = event.target.closest?.('[data-path]')?.dataset.path
  const index = rows.value.findIndex((row) => row.path === path)
  if (index === -1) return
  event.preventDefault()
  const { node, open } = rows.value[index]
  if (event.key === 'ArrowRight') {
    if (!node.children) return
    if (!open) {
      if (!matching.value) toggle(node)
    } else if (rows.value[index + 1]?.depth > rows.value[index].depth) {
      void focusRow(rows.value[index + 1].path)
    }
  } else if (node.children && open && !matching.value) {
    toggle(node)
  } else {
    const parent = path.split('/').slice(0, -1).join('/')
    if (parent) void focusRow(parent)
  }
}

function collapseAll() {
  expanded.value.clear()
  saveExpanded()
}

// Build the children of a target node from its flat list of procedures
function buildTarget(target, files) {
  const root = { name: target, path: target, children: [] }
  for (const { path, modified } of files) {
    const parts = path.split('/')
    let parent = root
    for (let i = 1; i < parts.length; i++) {
      const partPath = parts.slice(0, i + 1).join('/')
      const isFile = i === parts.length - 1
      let child = parent.children.find((c) => c.name === parts[i])
      if (!child) {
        child = { name: parts[i], path: partPath }
        if (isFile) {
          child.modified = modified
        } else {
          child.children = []
        }
        parent.children.push(child)
      }
      parent = child
    }
  }
  // Folders first, then files, each alphabetical like VS Code
  const sortNode = (node) => {
    node.children.sort((a, b) => {
      if (!!a.children !== !!b.children) return a.children ? -1 : 1
      return a.name.localeCompare(b.name)
    })
    node.children.forEach((c) => c.children && sortNode(c))
  }
  sortNode(root)
  return root
}

async function loadTarget(target) {
  const files = await loadProcedures(target)
  const index = items.value.findIndex((item) => item.path === target)
  if (files.length === 0) {
    if (index !== -1) items.value.splice(index, 1)
    return
  }
  const node = buildTarget(target, files)
  if (index === -1) {
    items.value.push(node)
  } else {
    items.value[index] = node
  }
}

// Reload a single target, or every target when none is given
async function refresh(target = null) {
  loading.value = true
  try {
    if (target) {
      await loadTarget(target)
    } else {
      const targets = await loadTargets()
      // Keep the target order stable regardless of load order
      items.value = items.value.filter((item) => targets.includes(item.path))
      await Promise.all(targets.map(loadTarget))
      items.value.sort(
        (a, b) => targets.indexOf(a.path) - targets.indexOf(b.path),
      )
    }
  } catch (error) {
    emit('error', `Failed to load scripts. ${error}`)
  } finally {
    loading.value = false
  }
  await revealActive()
}

function findNode(path) {
  const target = path.split('/')[0]
  let node = items.value.find((item) => item.path === target)
  while (node && node.path !== path) {
    node = node.children?.find(
      (c) => path === c.path || path.startsWith(`${c.path}/`),
    )
  }
  return node
}

// Make sure a file that was just saved shows up in the tree
async function refreshFile(path) {
  if (!path || !isProcedure(path)) return
  if (isListed(path) && !procedures.value.some((p) => p.path === path)) {
    loadLibrary().catch(() => {}) // Library shows its own load errors
  }
  // Saving a plugin file creates a modified copy on the server, so reload
  // the target to pick up the 'M' marker the first time it's saved
  if (findNode(path)?.modified) return
  await refresh(path.split('/')[0])
}

// Expand the parents of the active file and scroll it into view.
// This is how the explorer follows the running script between files.
async function revealActive() {
  const path = props.activeFile
  if (!path || !findNode(path)) return
  const parts = path.split('/')
  let changed = false
  for (let i = 1; i < parts.length; i++) {
    const folder = parts.slice(0, i).join('/')
    if (!expanded.value.has(folder)) {
      expanded.value.add(folder)
      changed = true
    }
  }
  if (changed) saveExpanded()
  await nextTick()
  const index = rows.value.findIndex((row) => row.path === path)
  if (index !== -1) scroller.value?.scrollToIndex(index)
}

watch(() => props.activeFile, revealActive)

watch(mode, (value) => {
  localStorage[MODE_KEY] = value
  // The tree was unmounted so scroll back to the active file
  if (value === 'files') void revealActive()
})

onMounted(() => refresh())

defineExpose({ refresh, refreshFile })
</script>

<style scoped>
/* Hide the scrollbar until the tree is hovered or focused, like VS Code.
   Keep the gutter so rows don't shift when it appears. scrollbar-color
   itself doesn't animate everywhere, so fade a registered color property
   that it reads from instead. */
@property --explorer-thumb {
  syntax: '<color>';
  inherits: false;
  initial-value: transparent;
}
/* :deep so the library's scroller (a child component) matches */
.script-explorer :deep(.explorer-scroll) {
  --explorer-thumb: transparent;
  scrollbar-gutter: stable;
  scrollbar-color: var(--explorer-thumb) transparent;
  transition: --explorer-thumb 0.4s ease-out 0.3s;
}
.script-explorer :deep(.explorer-scroll:hover),
.script-explorer :deep(.explorer-scroll:focus-within) {
  --explorer-thumb: rgba(var(--v-theme-on-surface), 0.3);
  transition: --explorer-thumb 0.15s ease-in;
}
</style>
