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
    scrollable
  >
    <v-card
      class="dashboards-root d-flex flex-column"
      :style="fullscreen ? null : { height: '80vh' }"
      data-test="dashboard-navigator"
    >
      <div class="d-flex align-center ga-3 pa-3 border-b">
        <v-text-field
          v-model="search"
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
        <!-- Places, then one folder per target -->
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
              v-for="place in places"
              :key="place.value"
              :active="place.value === activeView"
              :prepend-icon="place.icon"
              :title="place.label"
              :data-test="`navigator-place-${place.value}`"
              @click="view = place.value"
            >
              <template #append>
                <span class="text-caption text-medium-emphasis num">
                  {{ place.count }}
                </span>
              </template>
            </v-list-item>
            <v-list-subheader>Folders</v-list-subheader>
            <v-list-item
              v-for="folder in folders"
              :key="folder.target"
              :active="`folder:${folder.target}` === activeView"
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
          <v-list
            v-else
            class="db-current-list flex-grow-1 min-h-0 pa-0 bg-transparent"
          >
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
                  :highlighted="index === highlight"
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
        <span> <kbd>↑</kbd> <kbd>↓</kbd> move · <kbd>Enter</kbd> opens </span>
        <v-spacer />
        <span>Stars and recents are saved in this browser only</span>
      </div>
    </v-card>
  </v-dialog>
</template>

<script>
import modelShow from '../mixins/modelShow'
import NavigatorRow from './NavigatorRow.vue'
import { navigator, toggleStar } from './navigatorStore'

// Matches NavigatorRow's min-height
const ROW_HEIGHT = 56

// Find and open dashboards like a file explorer: Starred, Recent and All on
// the left, then a folder per target, since each dashboard is a file saved
// in a target (TARGET/dashboards/name.txt). Search covers every folder, and
// the folders then count the matches. Rows scroll virtually and fetch their
// titles as they're shown, so hundreds of dashboards stay quick.
export default {
  components: { NavigatorRow },
  mixins: [modelShow],
  props: {
    dashboards: { type: Array, default: () => [] },
    currentKey: { type: String, default: null },
    fullscreen: Boolean,
    // Phones: just find and open dashboards, no creating or duplicating.
    // The folders and the list take turns on the screen.
    lean: Boolean,
  },
  emits: ['open', 'new', 'duplicate'],
  setup() {
    return { ROW_HEIGHT }
  },
  data() {
    return {
      search: '',
      // 'starred', 'recent', 'all' or 'folder:TARGET'; null until chosen
      view: null,
      // Row the arrow keys are on
      highlight: 0,
    }
  },
  computed: {
    starredKeys() {
      return new Set(navigator.starred)
    },
    query() {
      return (this.search || '').trim().toLowerCase()
    },
    // Dashboards matching the search, in name order
    matches() {
      const words = this.query.split(/\s+/).filter(Boolean)
      const keys = words.length
        ? this.dashboards.filter((key) => {
            const haystack =
              `${key} ${navigator.info[key]?.title || ''}`.toLowerCase()
            return words.every((word) => haystack.includes(word))
          })
        : this.dashboards
      return [...keys].sort()
    },
    // Keeps starred and recent in their own orders
    starred() {
      const keys = new Set(this.matches)
      return navigator.starred.filter((key) => keys.has(key))
    },
    recent() {
      const keys = new Set(this.matches)
      return navigator.recent.filter((key) => keys.has(key))
    },
    places() {
      return [
        {
          value: 'starred',
          label: 'Starred',
          icon: 'mdi-star-outline',
          count: this.starred.length,
        },
        {
          value: 'recent',
          label: 'Recent',
          icon: 'mdi-history',
          count: this.recent.length,
        },
        {
          value: 'all',
          label: 'All dashboards',
          icon: 'mdi-view-dashboard-outline',
          count: this.matches.length,
        },
      ]
    },
    // Every target with dashboards, counting the matches
    folders() {
      const counts = {}
      for (const key of this.dashboards) counts[key.split('/')[0]] = 0
      for (const key of this.matches) counts[key.split('/')[0]]++
      return Object.keys(counts)
        .sort()
        .map((target) => ({ target, count: counts[target] }))
    },
    // Searching shows every match unless a folder is picked
    activeView() {
      if (this.view) return this.view
      if (this.query) return 'all'
      if (this.lean) return null
      return this.defaultView
    },
    defaultView() {
      if (navigator.starred.length) return 'starred'
      if (this.currentKey) return `folder:${this.currentKey.split('/')[0]}`
      return 'all'
    },
    rows() {
      const view = this.activeView
      if (view === 'starred') return this.starred
      if (view === 'recent') return this.recent
      if (view?.startsWith('folder:')) {
        const prefix = `${view.slice(7)}/`
        return this.matches.filter((key) => key.startsWith(prefix))
      }
      return this.matches
    },
    heading() {
      const view = this.activeView
      if (view?.startsWith('folder:')) {
        const target = view.slice(7)
        return {
          icon: 'mdi-folder-open-outline',
          label: target,
          path: `${target}/dashboards/`,
          class: 'mono',
        }
      }
      const place = this.places.find((p) => p.value === view)
      if (view === 'all' && this.query) {
        return { icon: 'mdi-magnify', label: 'Search results' }
      }
      return { icon: place?.icon, label: place?.label }
    },
    empty() {
      if (!this.dashboards.length) {
        return {
          icon: 'mdi-view-dashboard-outline',
          text: 'No dashboards yet.',
        }
      }
      if (this.query) {
        return {
          icon: 'mdi-magnify',
          text: `No dashboards match "${this.search}"`,
        }
      }
      if (this.activeView === 'starred') {
        return {
          icon: 'mdi-star-outline',
          text: 'Star a dashboard to keep it here.',
        }
      }
      return { icon: 'mdi-history', text: 'Dashboards you open show here.' }
    },
    // Phones show the folders, or the list once one's picked or searching
    showPlaces() {
      return !this.lean || this.activeView === null
    },
    showRows() {
      return !this.lean || this.activeView !== null
    },
  },
  watch: {
    modelValue(open) {
      if (open) {
        this.search = ''
        if (this.lean) this.view = null
      }
    },
    // A new search starts from every match; the folders narrow it
    query(query, before) {
      if (!before && query) this.view = null
    },
    rows() {
      this.highlight = 0
    },
  },
  methods: {
    toggleStar,
    open(key) {
      this.$emit('open', key)
      this.show = false
    },
    openFolder(key) {
      this.view = `folder:${key.split('/')[0]}`
    },
    back() {
      this.view = null
      this.search = ''
    },
    onKey(event) {
      const last = this.rows.length - 1
      if (event.key === 'Enter') {
        const key = this.rows[this.highlight]
        if (key) this.open(key)
        return
      }
      const step = { ArrowDown: 1, ArrowUp: -1 }[event.key]
      if (!step || last < 0) return
      event.preventDefault()
      this.highlight = Math.min(last, Math.max(0, this.highlight + step))
      this.reveal(this.highlight)
    },
    // Scroll just enough to show the row, rather than to the top
    reveal(index) {
      const box = this.$refs.scroller?.$el
      if (!box) return
      const top = index * ROW_HEIGHT
      if (top < box.scrollTop) box.scrollTop = top
      else if (top + ROW_HEIGHT > box.scrollTop + box.clientHeight) {
        box.scrollTop = top + ROW_HEIGHT - box.clientHeight
      }
    },
    create() {
      this.$emit('new')
      this.show = false
    },
    duplicate(key) {
      this.$emit('duplicate', key)
      this.show = false
    },
  },
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
kbd {
  padding: 0 4px;
  border: 1px solid rgba(var(--v-border-color), var(--v-border-opacity));
  border-radius: 4px;
  font-family: inherit;
  font-size: 0.85em;
}
</style>
