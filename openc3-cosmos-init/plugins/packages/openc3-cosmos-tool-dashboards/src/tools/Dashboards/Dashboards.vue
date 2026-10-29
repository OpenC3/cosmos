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
          <v-tooltip
            v-if="!isPhone || !current"
            location="bottom"
            :disabled="isPhone"
          >
            <template #activator="{ props: tooltipProps }">
              <v-btn
                v-bind="tooltipProps"
                variant="text"
                :prepend-icon="
                  isPhone ? undefined : 'mdi-view-dashboard-outline'
                "
                :icon="isPhone ? 'mdi-view-dashboard-outline' : undefined"
                :append-icon="isPhone ? undefined : 'mdi-chevron-down'"
                class="text-medium-emphasis flex-shrink-0"
                :aria-label="isPhone ? 'All dashboards' : undefined"
                :aria-keyshortcuts="SHORTCUT.aria"
                data-test="dashboard-navigator-btn"
                @click="navigatorOpen = true"
              >
                <template v-if="!isPhone">Dashboards</template>
              </v-btn>
            </template>
            All dashboards <kbd class="db-kbd ml-1">{{ SHORTCUT.label }}</kbd>
          </v-tooltip>
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
          @update="setSettings"
        />
        <v-text-field
          :model-value="model.title"
          label="Dashboard title"
          density="compact"
          variant="outlined"
          hide-details
          style="max-width: 280px; min-width: 180px"
          data-test="dashboard-title-input"
          @update:model-value="setTitle"
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
            :disabled="!canUndo"
            data-test="editor-undo"
            @click="undo"
          />
          <v-btn
            icon="mdi-redo"
            variant="text"
            size="small"
            aria-label="Redo"
            title="Redo (Ctrl+Shift+Z)"
            :disabled="!canRedo"
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

    <!-- Overall health across the top: the worst status of any panel, in
         its status color. Out of limits, it names the worst panel and goes
         to it. -->
    <div
      v-if="current && !editing && healthBanner"
      :class="['health-banner', `st-${health.level}`]"
      role="status"
      aria-live="polite"
      data-test="dashboard-health"
    >
      <!-- Centered on the banner; the button keeps the right column -->
      <div class="health-center">
        <status-symbol :level="health.level" decorative class="health-symbol" />
        <span class="health-label font-weight-bold text-uppercase">{{
          healthBanner.label
        }}</span>
        <span v-if="healthBanner.detail" class="health-detail text-truncate">
          {{ healthBanner.detail }}
        </span>
      </div>
      <v-btn
        v-if="healthBanner.worst"
        size="small"
        variant="text"
        append-icon="mdi-arrow-right"
        class="health-go flex-shrink-0"
        :title="`Scroll to ${healthBanner.worst}`"
        data-test="dashboard-health-go"
        @click="goToWorst"
      >
        <template v-if="!isPhone">{{ healthBanner.worst }}</template>
        <template v-else>Show</template>
      </v-btn>
    </div>

    <!-- The same playback banner and controls as Telemetry Viewer. The
         Playback button in the header goes back to live. -->
    <template v-if="playback.on && !editing">
      <!-- A gap from the health banner, when there is one above -->
      <playback-banner
        :class="['rounded-0', { 'mt-2': current && healthBanner }]"
      />
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

    <main
      v-else-if="!editing"
      :class="[
        isPhone ? 'pa-3' : 'pa-4',
        'position-relative',
        { 'is-opening': opening },
      ]"
    >
      <!-- Switching dashboards: the new one lays out underneath, hidden,
           until it's ready -->
      <div
        v-if="opening"
        class="opening-screen d-flex flex-column align-center ga-3 pt-16 text-medium-emphasis"
        role="status"
        data-test="dashboard-opening"
      >
        <v-progress-circular indeterminate color="secondary" />
        Loading {{ opening }}…
      </div>
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
        @layout="moveOrResize"
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
  <!-- Dialogs start fresh each time they open (a new :key), so their forms
       are set up from the props in setup rather than by watching open -->
  <dashboard-dialog
    :key="`dashboard-${dashboardDialogOpens}`"
    v-model="dashboardDialog"
    :mode="dashboardDialogMode"
    :initial-target="dashboardDialogTarget"
    :initial-name="dashboardDialogName"
    :existing="dashboards"
    @submit="onDashboardDialog"
  />
  <panel-dialog
    :key="`panel-${panelDialogOpens}`"
    v-model="panelDialog"
    :panel="editPanel"
    :is-new="editPanelIsNew"
    @save="savePanel"
  />
  <code-dialog
    v-model="codeDialog"
    :text="codeText"
    :path="filePath"
    @apply="applyCode"
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
import { onBeforeRouteLeave, onBeforeRouteUpdate } from 'vue-router'
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
import DashboardDialog from './dialogs/DashboardDialog.vue'
import DashboardNavigator from './navigator/DashboardNavigator.vue'
import { dashboardUrl, isStarred, toggleStar } from './navigator/navigatorStore'
import PanelDialog from './dialogs/PanelDialog.vue'
import CodeDialog from './dialogs/CodeDialog.vue'
import { useDashboardHistory } from './composables/useDashboardHistory'
import { routeKey, useDashboardFile } from './composables/useDashboardFile'
import { usePlayback } from './composables/usePlayback'
import { cloneData } from './composables/clone'
import { loadPanelPlugins } from './composables/panelPlugins'
import { PANEL_TYPES, defaultPanelType } from './panels/registry'
import { TlmPoller } from './composables/tlmPoller'
import { ItemInfo } from './composables/itemInfo'
import {
  emptyDashboard,
  newPanel,
  panelUid,
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

const display = useDisplay()
const notify = inject('notify')
const dialog = inject('dialog')
const gridRef = useTemplateRef('grid')

const title = 'Dashboards (Beta)'
// Services: markRaw keeps Vue from proxying their internals; the parts
// panels watch (poller.values, itemInfo.state) are reactive already
const poller = markRaw(new TlmPoller())
const itemInfo = markRaw(new ItemInfo())
// One streaming connection shared by every panel
const cable = markRaw(new Cable())
// Playback: replay every panel from a past time
const { playback, setPlaybackTime, goLive } = usePlayback(poller)
// Picked in the header, shared by every dashboard
const timeRange = reactive({ seconds: loadTimeRange() })
const hover = reactive({ time: null, source: null })
// Enterprise version history (VersionStore) is on for this install
const versionsEnabled = ref(false)
const historyOpen = ref(false)
const timeZone = ref('local')
const model = ref(emptyDashboard(''))
const loading = ref(true)
const dashboardDialog = ref(false)
// Bumped on every open, so the dialogs remount with fresh forms
const dashboardDialogOpens = ref(0)
const panelDialogOpens = ref(0)
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

// Undo / redo and unsaved changes, over snapshots taken after each edit
const history = useDashboardHistory(model, { apply: replaceModel })
const { canUndo, canRedo, undo, redo } = history
const {
  dashboards,
  current,
  opening,
  currentKey,
  filePath,
  savedText,
  fileText,
  errors,
  saving,
  loadList,
  initialKey,
  selectDashboard,
  open,
  save,
  duplicate,
  createDashboard,
  deleteDashboard,
} = useDashboardFile({
  model,
  editing,
  history,
  notify,
  ask,
  confirmDiscard,
  startEditing,
  firstValues: () => poller.nextPoll(),
})

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
// The navigator's shortcut (onKeydown takes either modifier), as Macs and
// everything else write it
const SHORTCUT = /Mac|iPhone|iPad/.test(window.navigator.platform)
  ? { label: '⌘K', aria: 'Meta+K' }
  : { label: 'Ctrl+K', aria: 'Control+K' }
const isDesktop = computed(() => breakpoint.value === 'desktop')
// A copy starts in the same target as its source, named NAME_COPY
const dashboardDialogTarget = computed(() => {
  const key = duplicateKey.value || currentKey.value
  return key ? key.split('/')[0] : null
})
const dashboardDialogName = computed(() =>
  duplicateKey.value ? `${duplicateKey.value.split('/')[1]}_COPY` : '',
)
const dirty = computed(() => !!current.value && history.changed.value)
// The code dialog shows the file as written, comments and lines with
// problems included (the problems' line numbers point into it), until the
// dashboard changes; then the text made from the dashboard. Only made
// while the dialog is open.
const codeText = computed(() => {
  if (!codeDialog.value) return ''
  return fileText.value !== null && !dirty.value
    ? fileText.value
    : serializeDashboard(model.value)
})
const style = computed(() => dashboardStyle(model.value.settings))
// A number, so replacing the model with the same period (undo, code
// edits, reopening) doesn't restart the poller
const pollingPeriod = computed(() => {
  const seconds = Number(model.value.settings.POLLING_PERIOD?.[0])
  return Number.isFinite(seconds) && seconds > 0 ? seconds : 1
})
// The health banner: { label, detail, worst } where worst is the title of
// the panel to go to when something is out of limits. Null when no panel
// shows a status.
const healthBanner = computed(() => {
  const { level, critical, caution, worstTitle } = health.value
  const panels = (count) => `${count} panel${count === 1 ? '' : 's'}`
  if (critical || caution) {
    const parts = []
    if (critical) parts.push(`${panels(critical)} critical`)
    if (caution) parts.push(`${panels(caution)} caution`)
    return {
      label: critical ? 'Critical' : 'Caution',
      detail: parts.join(' · '),
      worst: worstTitle || 'Worst panel',
    }
  }
  if (level === 'off') {
    return { label: 'Stale', detail: 'No current telemetry', worst: null }
  }
  if (level === 'normal') {
    return { label: 'Nominal', detail: null, worst: null }
  }
  // Just opened: the panels haven't reported yet. Hold the banner's place
  // (neutral, not the last dashboard's status) so the grid doesn't jump
  // when they do.
  if (showsStatus.value) {
    return { label: 'Waiting for telemetry', detail: null, worst: null }
  }
  return null
})
// Panels that report a status: ones with items, limits or a screen
const showsStatus = computed(() =>
  model.value.panels.some(
    (panel) => panel.items?.length || panel.targets?.length || panel.screen,
  ),
)
const starred = computed(() => isStarred(currentKey.value))
const starHelp = computed(() => {
  const where = `the dashboard navigator (${SHORTCUT.label})`
  return starred.value
    ? `Starred: listed under Starred in ${where}. Stars are saved in this browser only.`
    : `Star to list this dashboard under Starred in ${where}. Stars are saved in this browser only.`
})
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
  const key = initialKey()
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
function openDashboardDialog(mode, key = null) {
  dashboardDialogMode.value = mode
  duplicateKey.value = key
  dashboardDialogOpens.value++
  dashboardDialog.value = true
}
function onDashboardDialog(location) {
  if (dashboardDialogMode.value === 'duplicate') {
    duplicate(duplicateKey.value, location)
  } else {
    createDashboard(location)
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
function startEditing() {
  goLive()
  history.reset()
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
  if (dirty.value) history.revert()
  panelDialog.value = false
  codeDialog.value = false
  editing.value = false
}
// A whole new model from the code dialog or undo; keep panel identities
function replaceModel(newModel) {
  reuseUids(model.value.panels, newModel.panels)
  model.value = newModel
  errors.value = []
  fileText.value = null
}
// Each edit below ends with history.commit(), once the model has changed
function applyCode(newModel) {
  replaceModel(newModel)
  history.commit()
}
function setSettings(settings) {
  model.value.settings = settings
  history.commit()
}
function setTitle(title) {
  model.value.title = title
  history.commit()
}
function applyPositions(layout) {
  for (const panel of model.value.panels) {
    const rect = layout[panel.uid]
    if (rect) Object.assign(panel, rect)
  }
}
// The grid's drags, resizes and keyboard nudges
function moveOrResize(layout) {
  applyPositions(layout)
  history.commit()
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
  panelDialogOpens.value++
  panelDialog.value = true
  if (!editing.value) startEditing()
}
function configurePanel(panel) {
  editPanel.value = panel
  editPanelIsNew.value = false
  panelDialogOpens.value++
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
  history.commit()
}
function duplicatePanel(panel) {
  const copy = cloneData(panel)
  copy.uid = panelUid()
  Object.assign(
    copy,
    firstFit(model.value.panels, copy.type, copy.w, copy.h, columns.value),
  )
  model.value.panels.push(copy)
  history.commit()
}
function deletePanel(panel) {
  model.value.panels = model.value.panels.filter((p) => p.uid !== panel.uid)
  reflow()
  history.commit()
}
</script>

<style scoped>
/* The health banner: a strip across the top tinted in its status color,
   with a solid bar down the left edge. Out of limits it's stronger so it
   reads from across the room. */
.health-banner {
  /* --status comes from st-<level> (dashboards.scss) */
  --health: var(--status, rgb(var(--v-theme-on-surface)));
  display: grid;
  /* Equal side columns keep the text centered on the whole banner */
  grid-template-columns: 1fr minmax(0, auto) 1fr;
  align-items: center;
  gap: 12px;
  min-height: 40px;
  padding: 4px 16px;
  background: color-mix(in srgb, var(--health) 10%, transparent);
  border-bottom: 1px solid color-mix(in srgb, var(--health) 35%, transparent);
  box-shadow: inset 4px 0 0 var(--health);
}
.health-banner.st-caution {
  background: color-mix(in srgb, var(--health) 18%, transparent);
}
.health-banner.st-critical {
  background: color-mix(in srgb, var(--health) 26%, transparent);
  box-shadow: inset 6px 0 0 var(--health);
}
.health-center {
  grid-column: 2;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  min-width: 0;
}
.health-symbol {
  flex-shrink: 0;
  transform: scale(1.25);
}
.health-label {
  flex-shrink: 0;
  color: var(--health);
  letter-spacing: 0.12em;
}
.health-detail {
  min-width: 0;
  color: rgba(var(--v-theme-on-surface), 0.85);
}
.health-go {
  grid-column: 3;
  justify-self: end;
  color: var(--health);
}
/* Switching dashboards: the grid fades out and back in rather than
   popping, and the spinner only shows when it takes a moment, so quick
   switches don't flash it */
main > :not(.opening-screen) {
  transition: opacity 0.15s;
}
.is-opening > :not(.opening-screen) {
  opacity: 0;
  pointer-events: none;
}
.opening-screen {
  position: absolute;
  inset: 0;
  z-index: 1;
  animation: opening-appear 0.15s 0.25s both;
}
@keyframes opening-appear {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
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
