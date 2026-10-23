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
          v-model="timeRange.seconds"
          :compact="isPhone"
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
          v-model="playback.time"
          class="justify-center"
          :time-zone="timeZone"
          :loading="poller.clock.loading > 0"
          storage-key="dashboards"
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
      <dashboard-grid
        ref="grid"
        :panels="model.panels"
        :columns="columns"
        @health="(value) => (health = value)"
      />
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
    v-model="detailsOpen"
    :item="detailsItem"
    :sheet="isPhone"
    :show-grapher="isDesktop"
  />
</template>

<script>
import { computed, defineAsyncComponent, markRaw, reactive } from 'vue'
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

const LAST_KEY = 'dashboards__last'

// 'TARGET/NAME' from the page URL, or null when it doesn't name one
function routeKey({ target, dashboard }) {
  return target && dashboard
    ? `${target.toUpperCase()}/${dashboard.toUpperCase()}`
    : null
}

export default {
  components: {
    CodeDialog,
    DashboardDialog,
    DashboardAvatar,
    DashboardGrid,
    PlaybackBanner,
    PlaybackControls,
    DashboardStylePicker,
    DashboardNavigator,
    ItemDetails,
    PanelDialog,
    StatusSymbol,
    TimeRangePicker,
    TopBar,
    // Monaco-based, so only loaded when opened
    VersionHistoryDialog: defineAsyncComponent(() =>
      import('@openc3/vue-common/tools/versionhistory').then(
        (module) => module.VersionHistoryDialog,
      ),
    ),
  },
  provide() {
    return {
      poller: this.poller,
      itemInfo: this.itemInfo,
      cable: this.cable,
      openDetails: this.openDetails,
      editing: this.editMode,
      // { on, time }: panels show telemetry as of `time` while playback is on
      timeline: this.playback,
      // { seconds }: how much history graphs and sparklines show
      timeRange: this.timeRange,
      // { time, source }: the time under the mouse on any graph or sparkline
      // (seconds) and the panel uid it came from, so they all show it
      hover: this.hover,
      timeZone: computed(() => this.timeZone),
      // The grid's COLUMNS, 12 or 24, for the panel dialog
      columns: computed(() => this.columns),
    }
  },
  // Leaving with unsaved edits asks first; resolving false cancels
  beforeRouteLeave() {
    return this.confirmDiscard()
  },
  beforeRouteUpdate() {
    return this.confirmDiscard()
  },
  data() {
    return {
      title: 'Dashboards (Beta)',
      // Services: markRaw keeps Vue from proxying their internals; the parts
      // panels watch (poller.values, itemInfo.state) are reactive already
      poller: markRaw(new TlmPoller()),
      itemInfo: markRaw(new ItemInfo()),
      history: markRaw(new History()),
      // One streaming connection shared by every panel
      cable: markRaw(new Cable()),
      // On while editing: panels keep showing telemetry but don't send
      // commands
      editMode: reactive({ on: false }),
      // Playback: replay every panel from a past time
      playback: reactive({ on: false, time: null }),
      // Picked in the header, shared by every dashboard
      timeRange: reactive({ seconds: loadTimeRange() }),
      hover: reactive({ time: null, source: null }),
      // Enterprise version history (VersionStore) is on for this install
      versionsEnabled: false,
      historyOpen: false,
      // Worst panel status and counts, from DashboardGrid
      health: { level: null, critical: 0, caution: 0, worstUid: null },
      timeZone: 'local',
      dashboards: [],
      current: null, // { target, name }
      model: emptyDashboard(''),
      savedText: '',
      // The file as it was opened, until the dashboard changes
      fileText: null,
      errors: [],
      loading: true,
      saving: false,
      dashboardDialog: false,
      dashboardDialogMode: 'new',
      // 'TARGET/NAME' being duplicated
      duplicateKey: null,
      navigatorOpen: false,
      // Editor
      editing: false,
      panelDialog: false,
      editPanel: null,
      editPanelIsNew: false,
      codeDialog: false,
      // Item details sheet
      detailsItem: null,
      detailsOpen: false,
    }
  },
  computed: {
    // The grid's width in columns: COLUMNS 24 for big monitors
    columns() {
      return this.model.columns || GRID_COLUMNS
    },
    breakpoint() {
      return breakpointFor(this.$vuetify.display.width)
    },
    isPhone() {
      return this.breakpoint === 'phone'
    },
    isDesktop() {
      return this.breakpoint === 'desktop'
    },
    currentKey() {
      return this.current ? `${this.current.target}/${this.current.name}` : null
    },
    // A copy starts in the same target as its source, named NAME_COPY
    dashboardDialogTarget() {
      const key = this.duplicateKey || this.currentKey
      return key ? key.split('/')[0] : null
    },
    dashboardDialogName() {
      return this.duplicateKey ? `${this.duplicateKey.split('/')[1]}_COPY` : ''
    },
    filePath() {
      return this.current
        ? `${this.current.target}/dashboards/${this.current.name.toLowerCase()}.txt`
        : ''
    },
    text() {
      return serializeDashboard(this.model)
    },
    dirty() {
      return !!this.current && this.text !== this.savedText
    },
    // The code dialog shows the file as written, comments and lines with
    // problems included (the problems' line numbers point into it), until the
    // dashboard changes; then the text made from the dashboard
    codeText() {
      return this.fileText !== null && !this.dirty ? this.fileText : this.text
    },
    style() {
      return dashboardStyle(this.model.settings)
    },
    // A number, so replacing the model with the same period (undo, code
    // edits, reopening) doesn't restart the poller
    pollingPeriod() {
      const seconds = Number(this.model.settings.POLLING_PERIOD?.[0])
      return Number.isFinite(seconds) && seconds > 0 ? seconds : 1
    },
    // "2 critical · 1 caution", or one word when nothing is out of limits
    healthText() {
      const { level, critical, caution } = this.health
      const parts = []
      if (critical) parts.push(`${critical} critical`)
      if (caution) parts.push(`${caution} caution`)
      if (parts.length) return parts.join(' · ')
      if (level === 'off') return 'Stale'
      if (level === 'normal') return 'Nominal'
      return null
    },
    starred() {
      return isStarred(this.currentKey)
    },
    starHelp() {
      return this.starred
        ? 'Starred: listed under Starred in the dashboard navigator (Ctrl+K). Stars are saved in this browser only.'
        : 'Star to list this dashboard under Starred in the dashboard navigator (Ctrl+K). Stars are saved in this browser only.'
    },
    // Everything else has a button on the page
    menus() {
      // Phones only view dashboards
      if (this.isPhone) return []
      return [
        {
          label: 'File',
          items: [
            {
              label: 'New Dashboard',
              icon: 'mdi-plus',
              command: () => this.openDashboardDialog('new'),
            },
            // Enterprise: who changed what, when, with diffs and restore
            ...(this.versionsEnabled
              ? [
                  {
                    label: 'Version History',
                    icon: 'mdi-history',
                    disabled: !this.current || this.editing,
                    command: () => (this.historyOpen = true),
                  },
                ]
              : []),
            {
              label: 'Delete Dashboard',
              icon: 'mdi-delete',
              disabled: !this.current,
              command: () => this.deleteDashboard(),
            },
          ],
        },
      ]
    },
  },
  watch: {
    // Browser back / forward between dashboards
    '$route.params'(params) {
      const key = routeKey(params)
      if (!this.loading && key && key !== this.currentKey) this.open(key)
    },
    // The poller looks values up at the playback time instead of polling
    'playback.time'(time) {
      this.poller.setPlaybackTime(time)
    },
    'timeRange.seconds'(seconds) {
      saveTimeRange(seconds)
    },
    editing(editing) {
      this.editMode.on = editing
    },
    pollingPeriod(seconds) {
      this.poller.start(seconds)
    },
    // Every edit, from any part of the editor, lands in the undo history
    text(text) {
      if (this.editing) this.history.record(text)
    },
    detailsOpen(open) {
      if (!open) {
        // Let the sheet animate closed before tearing it down
        setTimeout(() => {
          if (!this.detailsOpen) this.detailsItem = null
        }, 300)
      }
    },
  },
  async created() {
    this.itemInfo.start()
    this.poller.start()
    // Enterprise reports whether version history is on; Core has none
    Api.get('/openc3-api/info')
      .then(({ data }) => {
        this.versionsEnabled = !!(data?.enterprise && data?.script_versions)
      })
      .catch(() => {})
    // Playback times are entered and shown in the COSMOS time zone setting
    this.itemInfo.api
      .get_setting('time_zone')
      .then((zone) => {
        if (zone) this.timeZone = zone
      })
      .catch(() => {})
    // Plugin panel types must be registered before any dashboard is parsed
    const [problems] = await Promise.all([loadPanelPlugins(), this.loadList()])
    if (problems.length) {
      this.$notify.caution({
        title: 'Some plugin panels did not load',
        body: problems.join('; '),
      })
    }
    const last = readString(LAST_KEY)
    const key =
      routeKey(this.$route.params) ||
      (this.dashboards.includes(last) ? last : this.dashboards[0])
    if (key) await this.open(key)
    this.loading = false
  },
  mounted() {
    window.addEventListener('beforeunload', this.beforeUnload)
    window.addEventListener('keydown', this.onKeydown)
  },
  unmounted() {
    window.removeEventListener('beforeunload', this.beforeUnload)
    window.removeEventListener('keydown', this.onKeydown)
    this.poller.stop()
    this.itemInfo.stop()
    this.cable.disconnect()
  },
  methods: {
    toggleStar,
    dashboardUrl,
    describeDashboardChange,
    goToWorst() {
      if (this.health.worstUid != null) {
        this.$refs.grid?.scrollToPanel(this.health.worstUid)
      }
    },
    beforeUnload(event) {
      if (this.dirty) event.preventDefault()
    },
    // Ctrl/Cmd+K opens the navigator. While editing, Ctrl/Cmd+Z undoes and
    // Ctrl/Cmd+Shift+Z or Ctrl+Y redoes, outside text fields.
    onKeydown(event) {
      if (!(event.ctrlKey || event.metaKey)) return
      if (event.key.toLowerCase() === 'k' && !this.editing) {
        event.preventDefault()
        this.navigatorOpen = true
        return
      }
      if (!this.editing) return
      if (event.target.closest('input, textarea, [contenteditable]')) return
      const key = event.key.toLowerCase()
      if (key === 'z' && !event.shiftKey) {
        event.preventDefault()
        this.undo()
      } else if ((key === 'z' && event.shiftKey) || key === 'y') {
        event.preventDefault()
        this.redo()
      }
    },
    // Confirm dialog as true / false ($dialog.confirm rejects on cancel)
    async ask(message, options) {
      try {
        await this.$dialog.confirm(message, options)
        return true
      } catch {
        return false
      }
    },
    confirmDiscard() {
      if (!this.dirty) return Promise.resolve(true)
      return this.ask(`Discard unsaved changes to ${this.model.title}?`, {
        okText: 'Discard',
        cancelText: 'Keep editing',
        okClass: 'error',
      })
    },
    async loadList() {
      try {
        const response = await Api.get('/openc3-api/dashboards')
        this.dashboards = response.data.map((path) => {
          const [target, , file] = path.split('/')
          return `${target}/${file.replace(/\.txt$/, '').toUpperCase()}`
        })
      } catch (error) {
        console.error('Error loading dashboards:', error)
      }
    },
    async selectDashboard(key) {
      if (!key || key === this.currentKey) return
      if (!(await this.confirmDiscard())) return
      this.open(key)
    },
    async open(key) {
      // Panels share command definitions; opening a dashboard refetches them
      // so changed definitions show without a page reload
      clearCommandCache()
      const [target, name] = key.split('/')
      let text
      try {
        text = await fetchDashboardText(key)
      } catch {
        this.$notify.caution({ title: 'Unknown dashboard', body: key })
        return
      }
      const { model, errors } = parseDashboard(text)
      this.load({ target, name }, model, errors, text)
      this.rememberCurrent()
    },
    load(current, model, errors = [], fileText = null) {
      this.current = current
      this.model = model
      this.errors = errors
      this.fileText = fileText
      this.editing = false
      this.savedText = this.text
    },
    // Navigator summary, reopen-on-launch and the URL all follow
    // the dashboard that's showing
    rememberCurrent() {
      const { target, name } = this.current
      remember(this.currentKey, this.model)
      visited(this.currentKey)
      writeString(LAST_KEY, this.currentKey)
      if (
        this.$route.params.target !== target ||
        this.$route.params.dashboard !== name
      ) {
        this.$router.replace({
          name: 'Dashboards',
          params: { target, dashboard: name },
        })
      }
    },
    post(target, dashboard, text) {
      return Api.post('/openc3-api/dashboard', {
        data: { scope: window.openc3Scope, target, dashboard, text },
      })
    },
    async save() {
      if (!this.current) return
      this.saving = true
      const text = this.text
      try {
        await this.post(this.current.target, this.current.name, text)
        this.savedText = text
        this.fileText = null
        remember(this.currentKey, this.model)
        this.$notify.normal({ title: 'Saved dashboard', body: this.currentKey })
      } catch (error) {
        this.$notify.serious({
          title: 'Error saving dashboard',
          body: error.message,
        })
      } finally {
        this.saving = false
      }
    },
    openDashboardDialog(mode, key = null) {
      this.dashboardDialogMode = mode
      this.duplicateKey = key
      this.dashboardDialog = true
    },
    onDashboardDialog(location) {
      if (this.dashboardDialogMode === 'duplicate') {
        this.duplicate(this.duplicateKey, location)
      } else {
        this.createDashboard(location)
      }
    },
    // Copy a saved dashboard to a new target / name and open the copy
    async duplicate(key, { target, name }) {
      try {
        await this.post(target, name, await fetchDashboardText(key))
      } catch (error) {
        this.$notify.serious({
          title: 'Error duplicating dashboard',
          body: error.message,
        })
        return
      }
      await this.loadList()
      await this.selectDashboard(`${target}/${name}`)
    },
    async createDashboard({ target, name, columns }) {
      if (!(await this.confirmDiscard())) return
      const title = name
        .toLowerCase()
        .split(/[_-]/)
        .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
        .join(' ')
      this.load({ target, name }, emptyDashboard(title, columns))
      this.savedText = ''
      await this.save()
      await this.loadList()
      this.rememberCurrent()
      this.startEditing()
    },
    async deleteDashboard() {
      if (!this.current) return
      const ok = await this.ask(
        `Delete ${this.currentKey}? Dashboards installed by a plugin go back to the plugin's version.`,
        { okText: 'Delete', cancelText: 'Cancel', okClass: 'error' },
      )
      if (!ok) return
      try {
        await Api.delete(dashboardUrl(this.currentKey))
        this.$notify.normal({
          title: 'Deleted dashboard',
          body: this.currentKey,
        })
      } catch (error) {
        this.$notify.serious({
          title: 'Error deleting dashboard',
          body: error.message,
        })
        return
      }
      const deleted = this.currentKey
      this.savedText = this.text // nothing left to discard
      await this.loadList()
      if (this.dashboards.includes(deleted)) {
        await this.open(deleted) // plugin version restored
      } else {
        forget(deleted)
        this.current = null
        this.model = emptyDashboard('')
        this.savedText = ''
        this.fileText = null
        this.editing = false
        writeString(LAST_KEY, null)
        this.$router.replace({ name: 'Dashboards', params: {} })
      }
    },

    // Tapping a value opens its details sheet (not while editing, when taps
    // arrange panels)
    openDetails(item) {
      if (this.editing) return
      this.detailsItem = {
        targetName: item.targetName,
        packetName: item.packetName,
        itemName: item.itemName,
      }
      this.detailsOpen = true
    },

    // Editor
    goLive() {
      this.playback.on = false
      this.playback.time = null
    },
    startEditing() {
      this.goLive()
      this.history.reset(this.text)
      this.editing = true
    },
    // Whole dashboard as text; editing it goes through the editor
    openCode() {
      if (!this.editing) this.startEditing()
      this.codeDialog = true
    },
    async done() {
      if (this.dirty) await this.save()
      if (!this.dirty) this.editing = false
    },
    // Drop every unsaved change and go back to the last saved dashboard
    async cancelEditing() {
      if (!(await this.confirmDiscard())) return
      if (this.dirty) this.applyText(this.savedText)
      this.panelDialog = false
      this.codeDialog = false
      this.editing = false
    },
    undo() {
      const text = this.history.undo()
      if (text !== null) this.applyText(text)
    },
    redo() {
      const text = this.history.redo()
      if (text !== null) this.applyText(text)
    },
    applyText(text) {
      const { model } = parseDashboard(text)
      this.applyModel(model)
    },
    // A whole new model from the code dialog or undo; keep panel identities
    applyModel(model) {
      reuseUids(this.model.panels, model.panels)
      this.model = model
      this.errors = []
      this.fileText = null
    },
    applyPositions(layout) {
      for (const panel of this.model.panels) {
        const rect = layout[panel.uid]
        if (rect) Object.assign(panel, rect)
      }
    },
    // Re-flow around `fixed` after a change
    reflow(fixed = null) {
      this.applyPositions(
        resolveLayout(this.model.panels, fixed, null, this.columns),
      )
    },
    addPanel() {
      const type = defaultPanelType()
      const { w, h } = PANEL_TYPES[type].defaults
      this.editPanel = newPanel(type, 0, 0, w, h)
      this.editPanelIsNew = true
      this.panelDialog = true
      if (!this.editing) this.startEditing()
    },
    configurePanel(panel) {
      this.editPanel = panel
      this.editPanelIsNew = false
      this.panelDialog = true
    },
    savePanel(draft) {
      const index = this.model.panels.findIndex((p) => p.uid === draft.uid)
      if (index === -1) {
        // New panels go in the first open spot that fits
        Object.assign(
          draft,
          firstFit(
            this.model.panels,
            draft.type,
            draft.w,
            draft.h,
            this.columns,
          ),
        )
        this.model.panels.push(draft)
      } else {
        this.model.panels.splice(index, 1, draft)
      }
      this.reflow(draft.uid)
    },
    duplicatePanel(panel) {
      const copy = JSON.parse(JSON.stringify(panel))
      copy.uid = panelUid()
      Object.assign(
        copy,
        firstFit(this.model.panels, copy.type, copy.w, copy.h, this.columns),
      )
      this.model.panels.push(copy)
    },
    deletePanel(panel) {
      this.model.panels = this.model.panels.filter((p) => p.uid !== panel.uid)
      this.reflow()
    },
  },
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
