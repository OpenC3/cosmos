<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <top-bar :title="title" :menus="menus" />
  <div v-if="playbackMode === 'playback'" class="playback">Playback Mode</div>
  <v-expansion-panels v-model="panel" class="mb-1">
    <v-expansion-panel>
      <v-expansion-panel-title class="pulse-i"></v-expansion-panel-title>
      <v-expansion-panel-text>
        <div class="pa-4">
          <v-row class="pa-3">
            <v-autocomplete
              v-model="selectedTarget"
              class="mr-4"
              density="compact"
              hide-details
              variant="outlined"
              label="Select Target"
              :items="Object.keys(screens).sort()"
              item-title="label"
              item-value="value"
              style="max-width: 300px"
              data-test="select-target"
            />
            <v-autocomplete
              v-model="selectedScreen"
              class="mr-4"
              density="compact"
              hide-details
              variant="outlined"
              label="Select Screen"
              :items="screens[selectedTarget]"
              style="max-width: 300px"
              data-test="select-screen"
              @update:model-value="screenSelect"
            />
            <v-btn
              class="bg-primary mr-2"
              :disabled="!selectedScreen"
              data-test="show-screen"
              @click="() => showScreen(selectedTarget, selectedScreen)"
            >
              Show
            </v-btn>
            <v-btn
              class="bg-primary mr-2"
              data-test="new-screen"
              @click="() => newScreen(selectedTarget)"
            >
              New Screen
              <v-icon> mdi-file-plus</v-icon>
            </v-btn>
          </v-row>
          <v-row v-if="playbackMode === 'playback'" class="pa-3">
            <v-text-field
              v-model="playbackDate"
              class="mr-4"
              density="compact"
              hide-details
              variant="outlined"
              label="Date"
              type="date"
              style="max-width: 200px"
              data-test="playback-date"
              :disabled="playbackPlaying"
            />
            <v-text-field
              v-model="playbackTime"
              class="mr-4"
              density="compact"
              hide-details
              variant="outlined"
              label="Time"
              type="time"
              step="1"
              style="max-width: 200px"
              data-test="playback-time"
              :disabled="playbackPlaying"
            />
            <v-tooltip
              :text="`Skip Backward ${playbackSkip} secs`"
              :open-delay="2000"
              location="top"
            >
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  icon="mdi-skip-backward"
                  variant="text"
                  aria-label="Skip Backward"
                  data-test="playback-skip-backward"
                  style="margin-top: -5px"
                  @click="playbackSkipBackward"
                ></v-btn>
              </template>
            </v-tooltip>
            <v-tooltip
              :text="`Step Backward ${playbackStep} secs`"
              :open-delay="2000"
              location="top"
            >
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  icon="mdi-step-backward"
                  variant="text"
                  aria-label="Step Backward"
                  data-test="playback-step-backward"
                  style="margin-top: -5px"
                  @click="playbackStepBackward"
                ></v-btn>
              </template>
            </v-tooltip>
            <v-btn
              :icon="playbackPlaying ? 'mdi-pause' : 'mdi-play'"
              variant="text"
              class="bg-primary"
              aria-label="Play / Pause"
              style="margin-top: -5px"
              @click="playbackToggle"
            ></v-btn>
            <v-tooltip
              :text="`Step Forward ${playbackStep} secs`"
              :open-delay="2000"
              location="top"
            >
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  icon="mdi-step-forward"
                  variant="text"
                  aria-label="Step Forward"
                  data-test="playback-step-forward"
                  style="margin-top: -5px"
                  @click="playbackStepForward"
                ></v-btn>
              </template>
            </v-tooltip>
            <v-tooltip
              :text="`Skip Forward ${playbackSkip} secs`"
              :open-delay="2000"
              location="top"
            >
              <template #activator="{ props }">
                <v-btn
                  v-bind="props"
                  icon="mdi-skip-forward"
                  variant="text"
                  aria-label="Skip Forward"
                  data-test="playback-skip-forward"
                  style="margin-top: -5px"
                  @click="playbackSkipForward"
                ></v-btn>
              </template>
            </v-tooltip>
            <v-text-field
              v-model="playbackStep"
              class="mr-4 ml-4"
              density="compact"
              hide-details
              variant="outlined"
              label="Step (Speed)"
              suffix="secs"
              type="number"
              step="1"
              data-test="playback-speed"
              style="max-width: 120px"
            />
            <v-text-field
              v-model="playbackSkip"
              class="mr-4"
              density="compact"
              hide-details
              variant="outlined"
              label="Skip"
              suffix="secs"
              type="number"
              step="1"
              data-test="skip"
              style="max-width: 120px"
            />
          </v-row>
        </div>
      </v-expansion-panel-text>
    </v-expansion-panel>
  </v-expansion-panels>
  <div class="grid">
    <div
      v-for="def in definitions"
      :id="screenId(def.id)"
      :key="def.id"
      ref="gridItem"
      class="item"
    >
      <div class="item-content">
        <openc3-screen
          :ref="`screen-${def.id}`"
          class="openc3-screen"
          :target="def.target"
          :screen="def.screen"
          :definition="def.definition"
          :keywords="keywords"
          :initial-floated="def.floated"
          :initial-top="def.top"
          :initial-left="def.left"
          :initial-z="def.zIndex"
          :time-zone="timeZone"
          :playback-mode="playbackMode"
          :playback-date-time="playbackDateTime"
          @close-screen="closeScreen(def.id)"
          @min-max-screen="refreshLayout"
          @add-new-screen="($event) => showScreen(...$event)"
          @delete-screen="deleteScreen(def)"
          @float-screen="floatScreen(def, ...$event)"
          @unfloat-screen="unfloatScreen(def, ...$event)"
          @drag-screen="dragScreen(def, ...$event)"
          @edit-screen="refreshLayout"
        />
      </div>
    </div>
  </div>
  <!-- Dialogs for opening and saving configs -->
  <open-config-dialog
    v-if="openConfig"
    v-model="openConfig"
    :config-key="configKey"
    @success="openConfiguration"
  />
  <save-config-dialog
    v-if="saveConfig"
    v-model="saveConfig"
    :config-key="configKey"
    @success="saveConfiguration"
  />
  <new-screen-dialog
    v-if="newScreenDialog"
    v-model="newScreenDialog"
    :target="selectedTarget"
    :screens="screens"
    @success="saveNewScreen"
  />
</template>

<script>
import Muuri from 'muuri'
import { Api, OpenC3Api } from '@openc3/js-common/services'
import {
  Config,
  Openc3Screen,
  OpenConfigDialog,
  SaveConfigDialog,
  TopBar,
} from '@openc3/vue-common/components'
import NewScreenDialog from './NewScreenDialog'
import { TimeFilters } from '@openc3/vue-common/util'

export default {
  components: {
    TopBar,
    Openc3Screen,
    NewScreenDialog,
    OpenConfigDialog,
    SaveConfigDialog,
  },
  mixins: [Config, TimeFilters],
  data() {
    return {
      title: 'Telemetry Viewer',
      panel: 0,
      counter: 0,
      definitions: [],
      screens: {},
      selectedTarget: '',
      selectedScreen: '',
      newScreenDialog: false,
      grid: null,
      api: null,
      timeZone: null, // deliberately null so we know when it is set
      keywords: [],
      configKey: 'telemetry_viewer',
      openConfig: false,
      saveConfig: false,
      playbackAvailable: false,
      playbackStep: 1,
      playbackSkip: 10,
      playbackDate: '',
      playbackTime: '',
      playbackDateTime: null,
      playbackMode: 'realtime',
      playbackTimer: null,
      playbackPlaying: false,
    }
  },
  computed: {
    menus: function () {
      return [
        {
          label: 'File',
          items: [
            {
              label: 'Playback Mode',
              checkbox: true,
              checked: this.playbackMode === 'playback',
              disabled: this.playbackAvailable === false,
              command: () => {
                this.playbackMode =
                  this.playbackMode === 'playback' ? 'realtime' : 'playback'
              },
            },
            {
              divider: true,
            },
            {
              label: 'Open Configuration',
              icon: 'mdi-folder-open',
              command: () => {
                this.openConfig = true
              },
            },
            {
              label: 'Save Configuration',
              icon: 'mdi-content-save',
              command: () => {
                this.saveConfig = true
              },
            },
            {
              label: 'Reset Configuration',
              icon: 'mdi-monitor-shimmer',
              command: () => {
                this.panel = 0 // Expand the expansion panel
                this.closeAll()
                this.resetConfigBase()
              },
            },
          ],
        },
      ]
    },
    currentConfig: function () {
      return this.definitions.map((def) => {
        return {
          screen: def.screen,
          target: def.target,
          floated: def.floated,
          top: def.top,
          left: def.left,
          zIndex: def.zIndex,
        }
      })
    },
  },
  watch: {
    selectedTarget: function (newTarget, oldTarget) {
      // When target changes, update screen to first screen of new target
      if (newTarget && newTarget !== oldTarget && this.screens[newTarget]) {
        this.selectedScreen = this.screens[newTarget][0]
      }
    },
    definitions: {
      handler: function () {
        this.saveDefaultConfig(this.currentConfig)
      },
      deep: true,
    },
    playbackMode: function (mode) {
      this.$store.commit('playback', {
        playbackMode: this.playbackMode,
        playbackDateTime: this.playbackDateTime,
        playbackStep: this.playbackStep,
      })
      if (mode === 'playback') {
        // Initialize playback date and time with current values
        // Create a new date 1 hr in the past as a default
        let date = new Date() - 3600000
        this.playbackDate = this.formatDate(date, this.timeZone)
        this.playbackTime = this.formatTime(date, this.timeZone)
      } else {
        this.playbackPause()
      }
    },
    playbackDateTime: function () {
      this.$store.commit('playback', {
        playbackMode: this.playbackMode,
        playbackDateTime: this.playbackDateTime,
        playbackStep: this.playbackStep,
      })
      if (this.playbackDateTime) {
        // If we've exceeded the current time, pause playback
        if (this.playbackDateTime > new Date()) {
          this.playbackPause()
        } else {
          this.playbackDate = this.formatDate(
            this.playbackDateTime,
            this.timeZone,
          )
          this.playbackTime = this.formatTime(
            this.playbackDateTime,
            this.timeZone,
          )
        }
      }
    },
    playbackStep: function () {
      this.$store.commit('playback', {
        playbackMode: this.playbackMode,
        playbackDateTime: this.playbackDateTime,
        playbackStep: this.playbackStep,
      })
      localStorage[`${this.configKey}__step`] = this.playbackStep
    },
    playbackSkip: function () {
      localStorage[`${this.configKey}__skip`] = this.playbackSkip
    },
    playbackDate: function () {
      localStorage[`${this.configKey}__date`] = this.playbackDate
    },
    playbackTime: function () {
      localStorage[`${this.configKey}__time`] = this.playbackTime
    },
  },
  created() {
    // Ensure Offline Access Is Setup For the Current User
    this.api = new OpenC3Api()
    this.api.ensure_offline_access()
    this.api
      .get_setting('time_zone')
      .then((response) => {
        if (response) {
          this.timeZone = response
        }
      })
      .catch((error) => {
        // Do nothing
      })
    Api.get('/openc3-api/tsdb', {
      headers: {
        // Since we're just checking for existence, 404 is possible so ignore it
        'Ignore-Errors': '404',
      },
    })
      .then((_response) => {
        this.playbackAvailable = true
      })
      .catch((_error) => {
        this.playbackAvailable = false
      })
    Api.get('/openc3-api/screens').then((response) => {
      response.data.forEach((filename) => {
        let parts = filename.split('/')
        if (this.screens[parts[0]] === undefined) {
          this.screens[parts[0]] = []
        }
        this.screens[parts[0]].push(parts[2].split('.')[0].toUpperCase())
      })
      // Select the first target and screen as an optimization
      this.selectedTarget = Object.keys(this.screens)[0]
      this.selectedScreen = this.screens[this.selectedTarget][0]

      // Called like /tools/tlmviewer?config=ground
      if (this.$route.query && this.$route.query.config) {
        this.openConfiguration(this.$route.query.config, true) // routed
      } else if (this.$route.params.target && this.$route.params.screen) {
        // If we're passed in a target / packet as part of the route
        this.targetSelect(this.$route.params.target.toUpperCase())
        this.screenSelect(this.$route.params.screen.toUpperCase())
      } else {
        let config = this.loadDefaultConfig()
        // Only apply the config if it's not an empty object (config does not exist)
        if (JSON.stringify(config) !== '{}') {
          this.applyConfig(this.loadDefaultConfig())
        }
      }
    })
    Api.get('/openc3-api/autocomplete/keywords/screen').then((response) => {
      this.keywords = response.data
    })

    if (localStorage[`${this.configKey}__step`]) {
      this.playbackStep = localStorage[`${this.configKey}__step`]
    }
    if (localStorage[`${this.configKey}__skip`]) {
      this.playbackSkip = localStorage[`${this.configKey}__skip`]
    }
    if (localStorage[`${this.configKey}__date`]) {
      this.playbackDate = localStorage[`${this.configKey}__date`]
    }
    if (localStorage[`${this.configKey}__time`]) {
      this.playbackTime = localStorage[`${this.configKey}__time`]
    }
  },
  mounted() {
    this.grid = new Muuri('.grid', {
      dragEnabled: true,
      // Only allow drags starting from the v-toolbar title
      dragHandle: '.v-toolbar',
    })
    this.grid.on('dragEnd', this.refreshLayout)
  },
  beforeUnmount() {
    if (this.playbackTimer) {
      clearInterval(this.playbackTimer)
    }
  },
  methods: {
    targetSelect(target) {
      this.selectedTarget = target
      this.selectedScreen = this.screens[target][0]
    },
    screenSelect(screen) {
      if (screen) {
        this.selectedScreen = screen
        this.showScreen(this.selectedTarget, this.selectedScreen)
      }
    },
    newScreen() {
      this.newScreenDialog = true
    },
    async saveNewScreen(screenName, packetName, targetName) {
      let text = 'SCREEN AUTO AUTO 1.0\n'
      if (packetName && packetName !== 'BLANK') {
        text += '\nVERTICAL\n'
        await this.api.get_tlm(targetName, packetName).then((packet) => {
          packet.items.forEach((item) => {
            text += `  LABELVALUE ${targetName} ${packetName} ${item.name}\n`
          })
          text += 'END\n'
        })
      } else {
        text += '\nLABEL NEW\n'
      }
      Api.post('/openc3-api/screen/', {
        data: {
          scope: window.openc3Scope,
          target: targetName,
          screen: screenName,
          text: text,
        },
      }).then((response) => {
        this.newScreenDialog = false
        if (this.screens[targetName] === undefined) {
          this.screens[targetName] = []
        }
        this.screens[targetName].push(screenName)
        this.screens[targetName].sort()
        this.selectedTarget = targetName
        this.selectedScreen = screenName
        this.showScreen(targetName, screenName)
      })
    },
    showScreen(target, screen) {
      const def = this.definitions.find(
        (def) => def.target == target && def.screen == screen,
      )
      if (!def) {
        this.loadScreen(target, screen).then((response) => {
          this.pushScreen({
            id: this.counter++,
            target: target,
            screen: screen,
            definition: response.data,
            floated: false,
            top: 0,
            left: 0,
            zIndex: 0,
          })
        })
      }
    },
    loadScreen(target, screen) {
      return Api.get('/openc3-api/screen/' + target + '/' + screen, {
        headers: {
          Accept: 'text/plain',
          // Plugins can be removed so 404 is possible which we want to ignore
          'Ignore-Errors': '404',
        },
      }).catch((error) => {
        // eslint-disable-next-line no-console
        console.error(
          `Error loading screen ${screen} for target ${target}:`,
          error,
        )
      })
    },
    pushScreen(definition) {
      this.definitions.push(definition)
      this.$nextTick(function () {
        if (!definition.floated) {
          let items = this.grid.add(
            this.$refs.gridItem[this.$refs.gridItem.length - 1],
            {
              active: false,
            },
          )
          this.grid.show(items)
          this.grid.refreshItems().layout()
        }
      })
    },
    closeScreenByName(target, screen) {
      const def = this.definitions.find(
        (def) => def.target == target && def.screen == screen,
      )
      if (def) {
        this.closeScreen(def.id)
      }
    },
    closeAll() {
      for (const def of this.definitions) {
        this.closeScreen(def.id)
      }
    },
    closeScreen(id) {
      let items = this.grid.getItems([
        document.getElementById(this.screenId(id)),
      ])
      this.grid.remove(items)
      this.grid.refreshItems().layout()
      this.definitions = this.definitions.filter((value, index, arr) => {
        return value.id != id
      })
    },
    deleteScreen(def) {
      this.closeScreen(def.id)
      let index = this.screens[def.target].indexOf(def.screen)
      if (index !== -1) {
        this.screens[def.target].splice(index, 1)
        if (this.screens[def.target].length === 0) {
          // Must call this.$delete to notify Vue of property deletion
          this.$delete(this.screens, def.target)
        }
      }
    },
    floatScreen(definition, floated, top, left, zIndex) {
      definition.floated = floated
      definition.top = top
      definition.left = left
      definition.zIndex = zIndex
      let items = this.grid.getItems([
        document.getElementById(this.screenId(definition.id)),
      ])
      this.grid.remove(items)
      this.grid.refreshItems().layout()
    },
    unfloatScreen(definition, floated, top, left, zIndex) {
      definition.floated = floated
      definition.top = top
      definition.left = left
      definition.zIndex = zIndex
      let items = [document.getElementById(this.screenId(definition.id))]
      this.grid.add(items)
      this.grid.refreshItems().layout()
    },
    dragScreen(definition, floated, top, left, zIndex) {
      definition.floated = floated
      definition.top = top
      definition.left = left
      definition.zIndex = zIndex
    },
    refreshLayout() {
      setTimeout(() => {
        this.grid.refreshItems().layout()
      }, 600) // TODO: Is 600ms ok for all screens?
    },
    screenId(id) {
      return 'tlmViewerScreen' + id
    },
    loadAll(config, promises) {
      // Wait until they're all loaded
      Promise.all(promises)
        .then((responses) => {
          // Then add all the screens in order
          config.forEach((definition, index) => {
            const response = responses[index]
            setTimeout(() => {
              let floated = definition.floated
              if (!floated) {
                floated = false
              }
              let top = definition.top || 0
              let left = definition.left || 0
              let zIndex = definition.zIndex || 0
              this.pushScreen({
                id: this.counter++,
                target: definition.target,
                screen: definition.screen,
                definition: response.data,
                floated: floated,
                top: top,
                left: left,
                zIndex: zIndex,
              })
            }, 0) // I don't even know... but Muuri complains if this isn't in a setTimeout
          })
        })
        .then(() => {
          setTimeout(this.refreshLayout, 0) // Muuri probably stacked some, so refresh that
        })
    },
    applyConfig: function (config) {
      this.counter = 0
      this.definitions = []
      // Load all the screen definitions from the API at once
      const screenPromises = config.map((definition) => {
        return this.loadScreen(definition.target, definition.screen)
      })
      this.loadAll(config, screenPromises)
    },
    openConfiguration: function (name, routed = false) {
      this.openConfigBase(name, routed, (config) => {
        this.applyConfig(config)
        // No need to this.saveDefaultConfig(config)
        // because applyConfig calls loadAll which calls pushScreen
        // which does a this.saveDefaultConfig(this.currentConfig)
      })
      this.panel = null // Minimize the expansion panel
    },
    saveConfiguration: function (name) {
      this.saveConfigBase(name, this.currentConfig)
    },
    playbackToggle() {
      if (this.playbackPlaying) {
        this.playbackPause()
      } else {
        this.playbackPlay()
      }
    },
    playbackStepBackward() {
      if (this.playbackDateTime) {
        this.playbackDateTime = new Date(
          this.playbackDateTime.getTime() - 1000 * this.playbackStep,
        )
      }
    },
    playbackStepForward() {
      if (this.playbackDateTime) {
        const newTime = new Date(
          this.playbackDateTime.getTime() + 1000 * this.playbackStep,
        )
        if (newTime <= new Date()) {
          this.playbackDateTime = newTime
        }
      }
    },
    playbackSkipBackward() {
      if (this.playbackDateTime) {
        this.playbackDateTime = new Date(
          this.playbackDateTime.getTime() - 1000 * this.playbackSkip,
        )
      }
    },
    playbackSkipForward() {
      if (this.playbackDateTime) {
        const newTime = new Date(
          this.playbackDateTime.getTime() + 1000 * this.playbackSkip,
        )
        if (newTime <= new Date()) {
          this.playbackDateTime = newTime
        }
      }
    },
    playbackPlay() {
      if (this.timeZone === 'UTC') {
        this.playbackDateTime = new Date(
          `${this.playbackDate}T${this.playbackTime}Z`,
        )
      } else {
        this.playbackDateTime = new Date(
          `${this.playbackDate}T${this.playbackTime}`,
        )
      }

      if (this.playbackTimer) {
        clearInterval(this.playbackTimer)
      }

      this.playbackTimer = setInterval(() => {
        if (this.playbackDateTime) {
          this.playbackDateTime = new Date(
            this.playbackDateTime.getTime() + 1000 * this.playbackStep,
          )
        }
      }, 1000)
      this.playbackPlaying = true
    },
    playbackPause() {
      if (this.playbackTimer) {
        clearInterval(this.playbackTimer)
        this.playbackTimer = null
      }
      this.playbackPlaying = false
    },
  },
}
</script>

<style scoped>
.playback {
  text-align: center;
  color: black;
  font-weight: bold;
  background-color: darkorange;
}
.v-application {
  /* fix for playwright scrolling I guess? */
  margin-bottom: 120px;
}
.v-expansion-panel-text {
  .container {
    margin: 0px;
  }
}
.v-expansion-panel-title {
  min-height: 10px;
  padding: 5px;
}
.grid {
  position: relative;
}
.item {
  position: absolute;
  display: block;
  margin: 5px;
  z-index: 1;
}
.item.muuri-item-dragging {
  z-index: 3;
}
.item.muuri-item-releasing {
  z-index: 2;
}
.item.muuri-item-hidden {
  z-index: 0;
}
.item-content {
  position: relative;
  cursor: pointer;
  border-radius: 6px;
}
</style>
