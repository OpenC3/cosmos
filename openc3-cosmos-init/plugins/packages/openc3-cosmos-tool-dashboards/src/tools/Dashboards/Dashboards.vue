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
  <top-bar :title="title" :menus="menus" />
  <div class="dashboards-root">
    <!-- Same header viewing and editing; the Code button is shared -->
    <header
      class="dashboard-header d-flex flex-wrap align-center ga-3 px-4 py-2 border-b"
      :data-test="editing ? 'editor-header' : undefined"
    >
      <template v-if="!editing">
        <nav
          aria-label="Breadcrumb"
          class="d-flex align-center ga-2 text-body-1 flex-grow-1 min-w-0"
        >
          <!-- On phones the dashboard's name is the switcher instead -->
          <v-btn
            v-if="!isPhone || !current"
            variant="text"
            :prepend-icon="isPhone ? undefined : 'mdi-view-dashboard-outline'"
            :icon="isPhone ? 'mdi-view-dashboard-outline' : undefined"
            :append-icon="isPhone ? undefined : 'mdi-chevron-down'"
            class="text-medium-emphasis flex-shrink-0"
            :aria-label="isPhone ? 'All dashboards' : undefined"
            title="All dashboards (Ctrl+K)"
            data-test="dashboard-navigator-btn"
            @click="navigatorOpen = true"
          >
            <template v-if="!isPhone">Dashboards</template>
          </v-btn>
          <template v-if="current">
            <span v-if="!isPhone" class="text-disabled">/</span>
            <component
              :is="isPhone ? 'button' : 'div'"
              v-ripple="isPhone"
              :type="isPhone ? 'button' : undefined"
              :class="[
                'd-flex align-center ga-2 min-w-0',
                { 'phone-switcher rounded-lg pa-1 ml-n1 text-left': isPhone },
              ]"
              :aria-label="
                isPhone ? `${model.title}, switch dashboard` : undefined
              "
              data-test="dashboard-switcher"
              @click="isPhone && (navigatorOpen = true)"
            >
              <dashboard-avatar
                :icon="style.icon"
                :color="style.color"
                :size="32"
              />
              <span
                class="font-weight-bold text-truncate"
                data-test="dashboard-title"
              >
                {{ model.title }}
              </span>
              <v-icon v-if="isPhone" icon="mdi-chevron-down" size="20" />
            </component>
            <v-tooltip v-if="!isPhone" location="bottom" :text="starHelp">
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  :icon="starred ? 'mdi-star' : 'mdi-star-outline'"
                  :color="starred ? 'warning' : undefined"
                  variant="text"
                  size="small"
                  :aria-label="starred ? 'Unstar dashboard' : 'Star dashboard'"
                  :aria-pressed="starred"
                  data-test="dashboard-star"
                  @click="toggleStar(currentKey)"
                />
              </template>
            </v-tooltip>
            <!-- Overall health: the worst status of any panel. Click to go
                 to the worst panel. -->
            <v-chip
              v-if="healthText"
              size="small"
              variant="tonal"
              :class="['health flex-shrink-0', `h-${health.level}`]"
              :title="`Dashboard health: ${healthText}`"
              data-test="dashboard-health"
              @click="goToWorst"
            >
              <status-symbol :level="health.level" decorative class="mr-2" />
              {{ healthText }}
            </v-chip>
          </template>
        </nav>
        <v-btn
          v-if="!isPhone"
          :variant="playback.on ? 'flat' : 'outlined'"
          :color="playback.on ? 'secondary' : undefined"
          prepend-icon="mdi-history"
          :disabled="!current"
          :aria-pressed="playback.on"
          data-test="dashboard-playback"
          @click="playback.on ? goLive() : (playback.on = true)"
        >
          Playback
        </v-btn>
      </template>
      <template v-else>
        <dashboard-style-picker
          :settings="model.settings"
          @update="(settings) => (model.settings = settings)"
        />
        <v-text-field
          :model-value="model.title"
          label="Dashboard title"
          density="compact"
          variant="outlined"
          hide-details
          style="max-width: 280px; min-width: 180px"
          data-test="dashboard-title-input"
          @update:model-value="(title) => (model.title = title)"
        />
        <v-chip
          size="small"
          variant="text"
          :class="dirty ? 'text-warning' : 'text-medium-emphasis'"
          data-test="dashboard-status"
        >
          {{ dirty ? 'Unsaved changes' : 'Saved' }}
        </v-chip>
        <v-spacer />
        <v-btn
          variant="outlined"
          prepend-icon="mdi-plus-box-outline"
          data-test="panel-add"
          @click="addPanel"
        >
          Add panel
        </v-btn>
      </template>
      <v-btn
        v-if="editing || !isPhone"
        variant="outlined"
        prepend-icon="mdi-code-tags"
        :disabled="!current"
        data-test="dashboard-code-btn"
        @click="openCode"
      >
        Code
      </v-btn>
      <template v-if="!editing">
        <v-btn
          v-if="!isPhone"
          color="primary"
          variant="flat"
          prepend-icon="mdi-pencil"
          :disabled="!current"
          data-test="dashboard-edit"
          @click="startEditing()"
        >
          Edit
        </v-btn>
        <time-range-picker
          v-if="current"
          :model-value="timeRange.seconds"
          :compact="isPhone"
          @update:model-value="setTimeRange"
        />
      </template>
      <template v-else>
        <div class="d-flex">
          <v-btn
            icon="mdi-undo"
            variant="text"
            size="small"
            aria-label="Undo"
            title="Undo (Ctrl+Z)"
            :disabled="!history.canUndo"
            data-test="editor-undo"
            @click="undo"
          />
          <v-btn
            icon="mdi-redo"
            variant="text"
            size="small"
            aria-label="Redo"
            title="Redo (Ctrl+Shift+Z)"
            :disabled="!history.canRedo"
            data-test="editor-redo"
            @click="redo"
          />
        </div>
        <v-btn
          variant="outlined"
          prepend-icon="mdi-content-save"
          :disabled="!dirty"
          :loading="saving"
          data-test="dashboard-save"
          @click="save"
        >
          Save
        </v-btn>
        <v-btn
          variant="outlined"
          prepend-icon="mdi-close"
          :disabled="saving"
          data-test="dashboard-cancel"
          @click="cancelEditing"
        >
          Cancel
        </v-btn>
        <v-btn
          color="primary"
          variant="flat"
          prepend-icon="mdi-check"
          :loading="saving"
          data-test="dashboard-done"
          @click="done"
        >
          Save and Done
        </v-btn>
      </template>
    </header>

    <!-- The same playback banner and controls as Telemetry Viewer. The
         Playback button in the header goes back to live. -->
    <template v-if="playback.on && !editing">
      <playback-banner class="rounded-0" />
      <div class="px-4 py-3 border-b" data-test="playback-bar">
        <!-- Centered, wrapped lines too (class lands on the controls' row) -->
        <playback-controls
          :model-value="playback.time"
          class="justify-center"
          :time-zone="timeZone"
          :loading="poller.clock.loading > 0"
          storage-key="dashboards"
          @update:model-value="setPlaybackTime"
        />
      </div>
    </template>

    <v-alert
      type="warning"
      variant="tonal"
      density="compact"
      icon="mdi-flask-outline"
      class="rounded-0"
      data-test="dashboards-beta-banner"
    >
      <span class="font-weight-bold">Dashboards is in beta.</span>
      Panels, the editor and the dashboard file format can change in any release
      without notice, and dashboards made now may need updating.
    </v-alert>

    <v-alert
      v-if="errors.length"
      type="warning"
      variant="tonal"
      density="compact"
      closable
      class="ma-4 mb-0"
      data-test="dashboard-errors"
      @click:close="errors = []"
    >
      {{ currentKey }} has {{ errors.length }} problem{{
        errors.length === 1 ? '' : 's'
      }}.
      <a v-if="!isPhone" href="#" @click.prevent="openCode">
        Open the code to fix
      </a>
      <div v-for="(error, index) in errors" :key="index" class="text-caption">
        Line {{ error.lineNumber }}: {{ error.message }}
      </div>
    </v-alert>

    <div
      v-if="!current"
      class="d-flex flex-column align-center ga-3 py-16 text-medium-emphasis"
    >
      <v-icon icon="mdi-view-dashboard-outline" size="48" />
      <div>
        {{ loading ? 'Loading…' : 'Open a dashboard or create a new one.' }}
      </div>
      <v-btn
        v-if="!loading && dashboards.length"
        variant="outlined"
        prepend-icon="mdi-view-dashboard-outline"
        data-test="dashboard-choose"
        @click="navigatorOpen = true"
      >
        Choose a dashboard
      </v-btn>
    </div>

    <main v-else-if="!editing" :class="isPhone ? 'pa-3' : 'pa-4'">
      <dashboard-grid ref="grid" :panels="model.panels" :columns="columns" />
      <div
        v-if="!model.panels.length"
        class="d-flex flex-column align-center ga-3 py-12 text-medium-emphasis"
      >
        <div>This dashboard has no panels yet.</div>
        <v-btn
          v-if="!isPhone"
          variant="outlined"
          prepend-icon="mdi-pencil"
          @click="startEditing()"
        >
          Add panels
        </v-btn>
      </div>
    </main>

    <main v-else class="pa-4">
      <dashboard-grid
        :panels="model.panels"
        :columns="columns"
        editing
        @configure="configurePanel"
        @layout="applyPositions"
        @duplicate="duplicatePanel"
        @delete="deletePanel"
      >
        <template #after="{ nextRow }">
          <button
            key="add-panel"
            type="button"
            class="add-panel d-flex align-center justify-center ga-2 rounded-lg border border-dashed cursor-pointer text-medium-emphasis"
            :style="{
              gridColumn: '1 / span 3',
              gridRow: `${nextRow + 1} / span 2`,
            }"
            data-test="panel-add-tile"
            @click="addPanel"
          >
            <v-icon icon="mdi-plus" />
            Add panel
          </button>
        </template>
      </dashboard-grid>
    </main>
  </div>

  <dashboard-navigator
    v-model="navigatorOpen"
    :dashboards="dashboards"
    :current-key="currentKey"
    :fullscreen="isPhone"
    :lean="isPhone"
    @open="selectDashboard"
    @new="openDashboardDialog('new')"
    @duplicate="openDashboardDialog('duplicate', $event)"
  />
  <dashboard-dialog
    v-model="dashboardDialog"
    :mode="dashboardDialogMode"
    :initial-target="dashboardDialogTarget"
    :initial-name="dashboardDialogName"
    :existing="dashboards"
    @submit="onDashboardDialog"
  />
  <panel-dialog
    v-model="panelDialog"
    :panel="editPanel"
    :is-new="editPanelIsNew"
    @save="savePanel"
  />
  <code-dialog
    v-model="codeDialog"
    :text="codeText"
    :path="filePath"
    @apply="applyModel"
  />
  <version-history-dialog
    v-if="historyOpen"
    v-model="historyOpen"
    :filename="filePath"
    :url="dashboardUrl(currentKey)"
    noun="dashboard"
    :current-body="savedText"
    :describe="describeDashboardChange"
    @restored="open(currentKey)"
  />
  <item-details
    v-if="detailsItem"
    :model-value="detailsOpen"
    :item="detailsItem"
    :sheet="isPhone"
    :show-grapher="isDesktop"
    @update:model-value="setDetailsOpen"
  />
</template>

<script setup>
import {
  computed,
  defineAsyncComponent,
  inject,
  markRaw,
  onMounted,
  onUnmounted,
  provide,
  reactive,
  ref,
  useTemplateRef,
  watch,
} from 'vue'
import {
  onBeforeRouteLeave,
  onBeforeRouteUpdate,
  useRoute,
  useRouter,
} from 'vue-router'
import { useDisplay } from 'vuetify'
import { Api, Cable } from '@openc3/js-common/services'
import {
  PlaybackBanner,
  PlaybackControls,
  TopBar,
} from '@openc3/vue-common/components'
import '@fontsource/ibm-plex-sans/400.css'
import '@fontsource/ibm-plex-sans/500.css'
import '@fontsource/ibm-plex-sans/600.css'
import '@fontsource/ibm-plex-mono/400.css'
import '@fontsource/ibm-plex-mono/500.css'
import './styles/dashboards.scss'
import DashboardGrid from './DashboardGrid.vue'
import DashboardAvatar from './components/DashboardAvatar.vue'
import DashboardStylePicker from './components/DashboardStylePicker.vue'
import { dashboardStyle } from './dashboardStyle'
import ItemDetails from './components/ItemDetails.vue'
import TimeRangePicker from './components/TimeRangePicker.vue'
import StatusSymbol from './components/StatusSymbol.vue'
import { loadTimeRange, saveTimeRange } from './composables/timeRange'
import { readString, writeString } from './composables/storage'
import DashboardDialog from './dialogs/DashboardDialog.vue'
import DashboardNavigator from './navigator/DashboardNavigator.vue'
import {
  dashboardUrl,
  fetchDashboardText,
  forget,
  isStarred,
  remember,
  toggleStar,
  visited,
} from './navigator/navigatorStore'
import PanelDialog from './dialogs/PanelDialog.vue'
import CodeDialog from './dialogs/CodeDialog.vue'
import { History } from './editor/history'
import { loadPanelPlugins } from './composables/panelPlugins'
import { PANEL_TYPES, defaultPanelType } from './panels/registry'
import { clearCommandCache } from './panels/commandParams'
import { TlmPoller } from './composables/tlmPoller'
import { ItemInfo } from './composables/itemInfo'
import {
  emptyDashboard,
  newPanel,
  panelUid,
  parseDashboard,
  reuseUids,
  serializeDashboard,
} from './dashboardParser'
import { describeDashboardChange } from './dashboardChanges'
import { GRID_COLUMNS, breakpointFor, firstFit, resolveLayout } from './layout'

// Monaco-based, so only loaded when opened
const VersionHistoryDialog = defineAsyncComponent(() =>
  import('@openc3/vue-common/tools/versionhistory').then(
    (module) => module.VersionHistoryDialog,
  ),
)

const LAST_KEY = 'dashboards__last'

// 'TARGET/NAME' from the page URL, or null when it doesn't name one
function routeKey({ target, dashboard }) {
  return target && dashboard
    ? `${target.toUpperCase()}/${dashboard.toUpperCase()}`
    : null
}

const route = useRoute()
const router = useRouter()
const display = useDisplay()
const notify = inject('notify')
const dialog = inject('dialog')
const gridRef = useTemplateRef('grid')

const title = 'Dashboards (Beta)'
// Services: markRaw keeps Vue from proxying their internals; the parts
// panels watch (poller.values, itemInfo.state) are reactive already
const poller = markRaw(new TlmPoller())
const itemInfo = markRaw(new ItemInfo())
const history = markRaw(new History())
// One streaming connection shared by every panel
const cable = markRaw(new Cable())
// Playback: replay every panel from a past time
const playback = reactive({ on: false, time: null })
// Picked in the header, shared by every dashboard
const timeRange = reactive({ seconds: loadTimeRange() })
const hover = reactive({ time: null, source: null })
// Enterprise version history (VersionStore) is on for this install
const versionsEnabled = ref(false)
const historyOpen = ref(false)
const timeZone = ref('local')
const dashboards = ref([])
const current = ref(null) // { target, name }
const model = ref(emptyDashboard(''))
const savedText = ref('')
// The file as it was opened, until the dashboard changes
const fileText = ref(null)
const errors = ref([])
const loading = ref(true)
const saving = ref(false)
const dashboardDialog = ref(false)
const dashboardDialogMode = ref('new')
// 'TARGET/NAME' being duplicated
const duplicateKey = ref(null)
const navigatorOpen = ref(false)
// Editor
const editing = ref(false)
const panelDialog = ref(false)
const editPanel = ref(null)
const editPanelIsNew = ref(false)
const codeDialog = ref(false)
// Item details sheet
const detailsItem = ref(null)
const detailsOpen = ref(false)

// On while editing: panels keep showing telemetry but don't send
// commands (reactive unwraps the computed, so panels read editing.on)
const editMode = reactive({ on: computed(() => editing.value) })

// Worst panel status and counts, from the viewing DashboardGrid
const health = computed(
  () =>
    gridRef.value?.health ?? {
      level: null,
      critical: 0,
      caution: 0,
      worstUid: null,
    },
)
// The grid's width in columns: COLUMNS 24 for big monitors
const columns = computed(() => model.value.columns || GRID_COLUMNS)
const breakpoint = computed(() => breakpointFor(display.width.value))
const isPhone = computed(() => breakpoint.value === 'phone')
const isDesktop = computed(() => breakpoint.value === 'desktop')
const currentKey = computed(() =>
  current.value ? `${current.value.target}/${current.value.name}` : null,
)
// A copy starts in the same target as its source, named NAME_COPY
const dashboardDialogTarget = computed(() => {
  const key = duplicateKey.value || currentKey.value
  return key ? key.split('/')[0] : null
})
const dashboardDialogName = computed(() =>
  duplicateKey.value ? `${duplicateKey.value.split('/')[1]}_COPY` : '',
)
const filePath = computed(() =>
  current.value
    ? `${current.value.target}/dashboards/${current.value.name.toLowerCase()}.txt`
    : '',
)
const text = computed(() => serializeDashboard(model.value))
const dirty = computed(() => !!current.value && text.value !== savedText.value)
// The code dialog shows the file as written, comments and lines with
// problems included (the problems' line numbers point into it), until the
// dashboard changes; then the text made from the dashboard
const codeText = computed(() =>
  fileText.value !== null && !dirty.value ? fileText.value : text.value,
)
const style = computed(() => dashboardStyle(model.value.settings))
// A number, so replacing the model with the same period (undo, code
// edits, reopening) doesn't restart the poller
const pollingPeriod = computed(() => {
  const seconds = Number(model.value.settings.POLLING_PERIOD?.[0])
  return Number.isFinite(seconds) && seconds > 0 ? seconds : 1
})
// "2 critical · 1 caution", or one word when nothing is out of limits
const healthText = computed(() => {
  const { level, critical, caution } = health.value
  const parts = []
  if (critical) parts.push(`${critical} critical`)
  if (caution) parts.push(`${caution} caution`)
  if (parts.length) return parts.join(' · ')
  if (level === 'off') return 'Stale'
  if (level === 'normal') return 'Nominal'
  return null
})
const starred = computed(() => isStarred(currentKey.value))
const starHelp = computed(() =>
  starred.value
    ? 'Starred: listed under Starred in the dashboard navigator (Ctrl+K). Stars are saved in this browser only.'
    : 'Star to list this dashboard under Starred in the dashboard navigator (Ctrl+K). Stars are saved in this browser only.',
)
// Everything else has a button on the page
const menus = computed(() => {
  // Phones only view dashboards
  if (isPhone.value) return []
  return [
    {
      label: 'File',
      items: [
        {
          label: 'New Dashboard',
          icon: 'mdi-plus',
          command: () => openDashboardDialog('new'),
        },
        // Enterprise: who changed what, when, with diffs and restore
        ...(versionsEnabled.value
          ? [
              {
                label: 'Version History',
                icon: 'mdi-history',
                disabled: !current.value || editing.value,
                command: () => (historyOpen.value = true),
              },
            ]
          : []),
        {
          label: 'Delete Dashboard',
          icon: 'mdi-delete',
          disabled: !current.value,
          command: () => deleteDashboard(),
        },
      ],
    },
  ]
})

provide('poller', poller)
provide('itemInfo', itemInfo)
provide('cable', cable)
provide('openDetails', openDetails)
provide('editing', editMode)
// { on, time }: panels show telemetry as of `time` while playback is on
provide('timeline', playback)
// { seconds }: how much history graphs and sparklines show
provide('timeRange', timeRange)
// { time, source }: the time under the mouse on any graph or sparkline
// (seconds) and the panel uid it came from, so they all show it
provide('hover', hover)
provide(
  'timeZone',
  computed(() => timeZone.value),
)
// The grid's COLUMNS, 12 or 24, for the panel dialog
provide('columns', columns)

// Leaving with unsaved edits asks first; resolving false cancels
onBeforeRouteLeave(() => confirmDiscard())
// Browser back / forward between dashboards too. The URL already names the
// dashboard being opened, so open() leaves it alone.
onBeforeRouteUpdate(async (to) => {
  if (!(await confirmDiscard())) return false
  const key = routeKey(to.params)
  if (!loading.value && key && key !== currentKey.value) {
    open(key, { syncUrl: false })
  }
})

// The period is part of the model, which the style picker, the code
// dialog, undo and opening all replace, so the poller follows it here
watch(pollingPeriod, (seconds) => poller.start(seconds))
// Every edit, from any part of the editor, lands in the undo history
watch(text, (value) => {
  if (editing.value) history.record(value)
})

init()

async function init() {
  itemInfo.start()
  poller.start()
  // Enterprise reports whether version history is on; Core has none
  Api.get('/openc3-api/info')
    .then(({ data }) => {
      versionsEnabled.value = !!(data?.enterprise && data?.script_versions)
    })
    .catch(() => {})
  // Playback times are entered and shown in the COSMOS time zone setting
  itemInfo.api
    .get_setting('time_zone')
    .then((zone) => {
      if (zone) timeZone.value = zone
    })
    .catch(() => {})
  // Plugin panel types must be registered before any dashboard is parsed
  const [problems] = await Promise.all([loadPanelPlugins(), loadList()])
  if (problems.length) {
    notify.caution({
      title: 'Some plugin panels did not load',
      body: problems.join('; '),
    })
  }
  const last = readString(LAST_KEY)
  const key =
    routeKey(route.params) ||
    (dashboards.value.includes(last) ? last : dashboards.value[0])
  if (key) await open(key)
  loading.value = false
}

onMounted(() => {
  window.addEventListener('beforeunload', beforeUnload)
  window.addEventListener('keydown', onKeydown)
})
onUnmounted(() => {
  window.removeEventListener('beforeunload', beforeUnload)
  window.removeEventListener('keydown', onKeydown)
  poller.stop()
  itemInfo.stop()
  cable.disconnect()
})

function goToWorst() {
  if (health.value.worstUid != null) {
    gridRef.value?.scrollToPanel(health.value.worstUid)
  }
}
// The time range picked in the header, remembered in this browser
function setTimeRange(seconds) {
  timeRange.seconds = seconds
  saveTimeRange(seconds)
}
// The poller looks values up at the playback time instead of polling
function setPlaybackTime(time) {
  playback.time = time
  poller.setPlaybackTime(time)
}
function setDetailsOpen(open) {
  detailsOpen.value = open
  if (!open) {
    // Let the sheet animate closed before tearing it down
    setTimeout(() => {
      if (!detailsOpen.value) detailsItem.value = null
    }, 300)
  }
}
function beforeUnload(event) {
  if (dirty.value) event.preventDefault()
}
// Ctrl/Cmd+K opens the navigator. While editing, Ctrl/Cmd+Z undoes and
// Ctrl/Cmd+Shift+Z or Ctrl+Y redoes, outside text fields.
function onKeydown(event) {
  if (!(event.ctrlKey || event.metaKey)) return
  if (event.key.toLowerCase() === 'k' && !editing.value) {
    event.preventDefault()
    navigatorOpen.value = true
    return
  }
  if (!editing.value) return
  if (event.target.closest('input, textarea, [contenteditable]')) return
  const key = event.key.toLowerCase()
  if (key === 'z' && !event.shiftKey) {
    event.preventDefault()
    undo()
  } else if ((key === 'z' && event.shiftKey) || key === 'y') {
    event.preventDefault()
    redo()
  }
}
// Confirm dialog as true / false (dialog.confirm rejects on cancel)
async function ask(message, options) {
  try {
    await dialog.confirm(message, options)
    return true
  } catch {
    return false
  }
}
function confirmDiscard() {
  if (!dirty.value) return Promise.resolve(true)
  return ask(`Discard unsaved changes to ${model.value.title}?`, {
    okText: 'Discard',
    cancelText: 'Keep editing',
    okClass: 'error',
  })
}
async function loadList() {
  try {
    const response = await Api.get('/openc3-api/dashboards')
    dashboards.value = response.data.map((path) => {
      const [target, , file] = path.split('/')
      return `${target}/${file.replace(/\.txt$/, '').toUpperCase()}`
    })
  } catch (error) {
    console.error('Error loading dashboards:', error)
  }
}
async function selectDashboard(key) {
  if (!key || key === currentKey.value) return
  if (!(await confirmDiscard())) return
  open(key)
}
async function open(key, { syncUrl = true } = {}) {
  // Panels share command definitions; opening a dashboard refetches them
  // so changed definitions show without a page reload
  clearCommandCache()
  const [target, name] = key.split('/')
  let fetched
  try {
    fetched = await fetchDashboardText(key)
  } catch {
    notify.caution({ title: 'Unknown dashboard', body: key })
    return
  }
  const parsed = parseDashboard(fetched)
  load({ target, name }, parsed.model, parsed.errors, fetched)
  rememberCurrent({ syncUrl })
}
function load(dashboard, newModel, newErrors = [], newFileText = null) {
  current.value = dashboard
  model.value = newModel
  errors.value = newErrors
  fileText.value = newFileText
  editing.value = false
  savedText.value = text.value
}
// Navigator summary, reopen-on-launch and the URL all follow
// the dashboard that's showing
function rememberCurrent({ syncUrl = true } = {}) {
  const { target, name } = current.value
  remember(currentKey.value, model.value)
  visited(currentKey.value)
  writeString(LAST_KEY, currentKey.value)
  if (
    syncUrl &&
    (route.params.target !== target || route.params.dashboard !== name)
  ) {
    router.replace({
      name: 'Dashboards',
      params: { target, dashboard: name },
    })
  }
}
function post(target, dashboard, body) {
  return Api.post('/openc3-api/dashboard', {
    data: { scope: window.openc3Scope, target, dashboard, text: body },
  })
}
async function save() {
  if (!current.value) return
  saving.value = true
  const body = text.value
  try {
    await post(current.value.target, current.value.name, body)
    savedText.value = body
    fileText.value = null
    remember(currentKey.value, model.value)
    notify.normal({ title: 'Saved dashboard', body: currentKey.value })
  } catch (error) {
    notify.serious({
      title: 'Error saving dashboard',
      body: error.message,
    })
  } finally {
    saving.value = false
  }
}
function openDashboardDialog(mode, key = null) {
  dashboardDialogMode.value = mode
  duplicateKey.value = key
  dashboardDialog.value = true
}
function onDashboardDialog(location) {
  if (dashboardDialogMode.value === 'duplicate') {
    duplicate(duplicateKey.value, location)
  } else {
    createDashboard(location)
  }
}
// Copy a saved dashboard to a new target / name and open the copy
async function duplicate(key, { target, name }) {
  try {
    await post(target, name, await fetchDashboardText(key))
  } catch (error) {
    notify.serious({
      title: 'Error duplicating dashboard',
      body: error.message,
    })
    return
  }
  await loadList()
  await selectDashboard(`${target}/${name}`)
}
async function createDashboard({ target, name, columns }) {
  if (!(await confirmDiscard())) return
  const dashboardTitle = name
    .toLowerCase()
    .split(/[_-]/)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')
  load({ target, name }, emptyDashboard(dashboardTitle, columns))
  savedText.value = ''
  await save()
  await loadList()
  rememberCurrent()
  startEditing()
}
async function deleteDashboard() {
  if (!current.value) return
  const ok = await ask(
    `Delete ${currentKey.value}? Dashboards installed by a plugin go back to the plugin's version.`,
    { okText: 'Delete', cancelText: 'Cancel', okClass: 'error' },
  )
  if (!ok) return
  try {
    await Api.delete(dashboardUrl(currentKey.value))
    notify.normal({
      title: 'Deleted dashboard',
      body: currentKey.value,
    })
  } catch (error) {
    notify.serious({
      title: 'Error deleting dashboard',
      body: error.message,
    })
    return
  }
  const deleted = currentKey.value
  savedText.value = text.value // nothing left to discard
  await loadList()
  if (dashboards.value.includes(deleted)) {
    await open(deleted) // plugin version restored
  } else {
    forget(deleted)
    current.value = null
    model.value = emptyDashboard('')
    savedText.value = ''
    fileText.value = null
    editing.value = false
    writeString(LAST_KEY, null)
    router.replace({ name: 'Dashboards', params: {} })
  }
}

// Tapping a value opens its details sheet (not while editing, when taps
// arrange panels)
function openDetails(item) {
  if (editing.value) return
  detailsItem.value = {
    targetName: item.targetName,
    packetName: item.packetName,
    itemName: item.itemName,
  }
  detailsOpen.value = true
}

// Editor
function goLive() {
  playback.on = false
  setPlaybackTime(null)
}
function startEditing() {
  goLive()
  history.reset(text.value)
  editing.value = true
}
// Whole dashboard as text; editing it goes through the editor
function openCode() {
  if (!editing.value) startEditing()
  codeDialog.value = true
}
async function done() {
  if (dirty.value) await save()
  if (!dirty.value) editing.value = false
}
// Drop every unsaved change and go back to the last saved dashboard
async function cancelEditing() {
  if (!(await confirmDiscard())) return
  if (dirty.value) applyText(savedText.value)
  panelDialog.value = false
  codeDialog.value = false
  editing.value = false
}
function undo() {
  const value = history.undo()
  if (value !== null) applyText(value)
}
function redo() {
  const value = history.redo()
  if (value !== null) applyText(value)
}
function applyText(value) {
  applyModel(parseDashboard(value).model)
}
// A whole new model from the code dialog or undo; keep panel identities
function applyModel(newModel) {
  reuseUids(model.value.panels, newModel.panels)
  model.value = newModel
  errors.value = []
  fileText.value = null
}
function applyPositions(layout) {
  for (const panel of model.value.panels) {
    const rect = layout[panel.uid]
    if (rect) Object.assign(panel, rect)
  }
}
// Re-flow around `fixed` after a change
function reflow(fixed = null) {
  applyPositions(resolveLayout(model.value.panels, fixed, null, columns.value))
}
function addPanel() {
  const type = defaultPanelType()
  const { w, h } = PANEL_TYPES[type].defaults
  editPanel.value = newPanel(type, 0, 0, w, h)
  editPanelIsNew.value = true
  panelDialog.value = true
  if (!editing.value) startEditing()
}
function configurePanel(panel) {
  editPanel.value = panel
  editPanelIsNew.value = false
  panelDialog.value = true
}
function savePanel(draft) {
  const panels = model.value.panels
  const index = panels.findIndex((p) => p.uid === draft.uid)
  if (index === -1) {
    // New panels go in the first open spot that fits
    Object.assign(
      draft,
      firstFit(panels, draft.type, draft.w, draft.h, columns.value),
    )
    panels.push(draft)
  } else {
    panels.splice(index, 1, draft)
  }
  reflow(draft.uid)
}
function duplicatePanel(panel) {
  const copy = JSON.parse(JSON.stringify(panel))
  copy.uid = panelUid()
  Object.assign(
    copy,
    firstFit(model.value.panels, copy.type, copy.w, copy.h, columns.value),
  )
  model.value.panels.push(copy)
}
function deletePanel(panel) {
  model.value.panels = model.value.panels.filter((p) => p.uid !== panel.uid)
  reflow()
}
</script>

<style scoped>
/* The health chip in its status color */
.health.h-critical {
  color: var(--color-status-critical);
}
.health.h-caution {
  color: var(--color-status-caution);
}
.health.h-normal {
  color: var(--color-status-normal);
}
.phone-switcher {
  color: inherit;
}
/* Same height viewing and editing so the page doesn't shift */
.dashboard-header {
  min-height: 57px;
}
/* Stronger than the default border; background stays here (not
   bg-transparent) so :hover can change it */
.add-panel {
  --v-border-opacity: 0.3;
  background: transparent;
}
.add-panel:hover {
  background: rgba(var(--v-theme-on-surface), 0.04);
}
</style>
