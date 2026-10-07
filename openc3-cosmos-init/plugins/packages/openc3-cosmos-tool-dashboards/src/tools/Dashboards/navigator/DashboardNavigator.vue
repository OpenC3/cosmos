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
    :max-width="fullscreen ? undefined : 1000"
    scrollable
  >
    <v-card
      class="dashboards-root navigator"
      :style="fullscreen ? null : { height: '80vh' }"
      data-test="dashboard-navigator"
    >
      <div class="d-flex align-center ga-3 pa-4 border-b">
        <v-text-field
          ref="search"
          v-model="search"
          placeholder="Search dashboards and targets"
          prepend-inner-icon="mdi-magnify"
          density="comfortable"
          variant="solo-filled"
          flat
          hide-details
          clearable
          autofocus
          class="search"
          style="max-width: 520px"
          data-test="navigator-search"
          @keydown.enter="openFirst"
        />
        <v-spacer />
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
      <div v-if="targets.length > 1" class="d-flex align-center ga-3 px-4 pt-3">
        <span class="text-body-2 text-medium-emphasis">Target</span>
        <v-chip-group
          v-model="targetFilter"
          selected-class="bg-secondary"
          data-test="navigator-targets"
        >
          <v-chip
            v-for="target in targets"
            :key="target"
            :value="target"
            variant="outlined"
            filter
          >
            {{ target }}
          </v-chip>
        </v-chip-group>
      </div>
      <v-card-text class="pa-0">
        <div
          v-if="!dashboards.length"
          class="d-flex flex-column align-center ga-3 pa-12 text-body-1 text-medium-emphasis"
        >
          <v-icon icon="mdi-view-dashboard-outline" size="48" />
          No dashboards yet.
          <v-btn
            v-if="!lean"
            variant="outlined"
            prepend-icon="mdi-plus"
            @click="create"
          >
            Create one
          </v-btn>
        </div>
        <div
          v-else-if="!sections.length"
          class="pa-12 text-center text-body-1 text-medium-emphasis"
        >
          No dashboards match "{{ search }}"
        </div>
        <v-list v-else class="py-0 bg-transparent">
          <template v-for="section in sections" :key="section.label">
            <div
              class="d-flex align-center ga-2 px-4 pt-4 pb-2 text-body-2 font-weight-bold text-medium-emphasis text-uppercase"
            >
              <v-icon v-if="section.icon" :icon="section.icon" size="16" />
              {{ section.label }}
            </div>
            <v-list-item
              v-for="key in section.keys"
              :key="`${section.label}-${key}`"
              :class="['px-4 py-3', { current: key === currentKey }]"
              :active="false"
              data-test="navigator-item"
              @click="open(key)"
            >
              <template #prepend>
                <dashboard-avatar
                  :icon="info[key]?.icon"
                  :color="info[key]?.color"
                  class="mr-3"
                />
              </template>
              <div class="d-flex align-center ga-2">
                <span
                  class="text-subtitle-1 font-weight-bold text-high-emphasis"
                >
                  {{ titleOf(key) }}
                </span>
                <v-chip
                  v-if="key === currentKey"
                  size="x-small"
                  color="secondary"
                  variant="flat"
                  label
                >
                  Open
                </v-chip>
              </div>
              <div
                class="d-flex align-center ga-2 flex-wrap text-body-2 text-medium-emphasis"
              >
                <span class="mono">{{ key }}</span>
                <template v-if="info[key]">
                  <span>
                    · {{ info[key].panels }} panel{{
                      info[key].panels === 1 ? '' : 's'
                    }}
                  </span>
                  <span v-if="info[key].targets.length">
                    · {{ info[key].targets.join(', ') }}
                  </span>
                </template>
              </div>
              <template #append>
                <div class="d-flex align-center ga-2">
                  <v-btn
                    v-if="!lean"
                    icon="mdi-content-copy"
                    variant="text"
                    class="text-medium-emphasis"
                    :aria-label="`Duplicate ${key}`"
                    title="Duplicate"
                    data-test="navigator-duplicate"
                    @click.stop="duplicate(key)"
                  />
                  <v-btn
                    v-if="!lean"
                    :icon="isStarred(key) ? 'mdi-star' : 'mdi-star-outline'"
                    :color="isStarred(key) ? 'warning' : undefined"
                    :class="{ 'text-medium-emphasis': !isStarred(key) }"
                    variant="text"
                    :aria-label="
                      isStarred(key) ? `Unstar ${key}` : `Star ${key}`
                    "
                    :aria-pressed="isStarred(key)"
                    :title="isStarred(key) ? 'Unstar' : 'Star to list first'"
                    data-test="navigator-star"
                    @click.stop="toggleStar(key)"
                  />
                </div>
              </template>
            </v-list-item>
          </template>
        </v-list>
      </v-card-text>
      <div
        v-if="!lean"
        class="d-flex align-center ga-2 px-4 py-3 border-t text-body-2 text-medium-emphasis"
      >
        <v-icon icon="mdi-star-outline" size="18" />
        Star a dashboard to keep it at the top. Stars are saved in this browser
        only.
        <v-spacer />
        <span class="d-none d-sm-inline">Enter opens the first match</span>
      </div>
    </v-card>
  </v-dialog>
</template>

<script>
import modelShow from '../mixins/modelShow'
import DashboardAvatar from '../components/DashboardAvatar.vue'
import { isStarred, loadInfo, navigator, toggleStar } from './navigatorStore'

// Find, open and duplicate dashboards: search across titles, names and
// targets, filter by target, with starred dashboards up top.
export default {
  components: { DashboardAvatar },
  mixins: [modelShow],
  props: {
    dashboards: { type: Array, default: () => [] },
    currentKey: { type: String, default: null },
    fullscreen: Boolean,
    // Phones: just find and open dashboards, no creating or starring
    lean: Boolean,
  },
  emits: ['open', 'new', 'duplicate'],
  data() {
    return { search: '', targetFilter: null }
  },
  computed: {
    info() {
      return navigator.info
    },
    // Targets a dashboard is saved with or shows data from
    targets() {
      const targets = new Set()
      for (const key of this.dashboards) {
        targets.add(key.split('/')[0])
        for (const target of this.info[key]?.targets || []) targets.add(target)
      }
      return [...targets].sort()
    },
    filtered() {
      const query = (this.search || '').trim().toLowerCase()
      return this.dashboards.filter((key) => {
        const info = this.info[key]
        if (this.targetFilter) {
          const inTarget =
            key.startsWith(`${this.targetFilter}/`) ||
            info?.targets.includes(this.targetFilter)
          if (!inTarget) return false
        }
        if (!query) return true
        const haystack = [key, info?.title, ...(info?.targets || [])]
          .join(' ')
          .toLowerCase()
        return query.split(/\s+/).every((word) => haystack.includes(word))
      })
    },
    sections() {
      const keys = this.filtered
      if (this.search || this.targetFilter) {
        return keys.length ? [{ label: 'Results', keys }] : []
      }
      const sections = []
      const starred = navigator.starred.filter((key) => keys.includes(key))
      if (starred.length) {
        sections.push({ label: 'Starred', icon: 'mdi-star', keys: starred })
      }
      const byTarget = {}
      for (const key of keys) {
        const target = key.split('/')[0]
        ;(byTarget[target] ||= []).push(key)
      }
      for (const target of Object.keys(byTarget).sort()) {
        sections.push({ label: target, keys: byTarget[target] })
      }
      return sections
    },
  },
  watch: {
    modelValue(open) {
      if (open) {
        this.search = ''
        loadInfo(this.dashboards)
      }
    },
  },
  methods: {
    isStarred,
    toggleStar,
    titleOf(key) {
      return this.info[key]?.title || key.split('/')[1]
    },
    open(key) {
      this.$emit('open', key)
      this.show = false
    },
    openFirst() {
      const first = this.sections[0]?.keys[0]
      if (first) this.open(first)
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
.search :deep(input) {
  font-size: 16px;
}
.navigator :deep(.v-list-item) {
  border-left: 3px solid transparent;
}
.navigator :deep(.v-list-item.current) {
  border-left-color: rgb(var(--v-theme-secondary));
  background: rgba(var(--v-theme-on-surface), 0.05);
}
</style>
