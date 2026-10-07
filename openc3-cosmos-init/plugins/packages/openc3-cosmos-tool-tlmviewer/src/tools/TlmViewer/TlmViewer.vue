<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <top-bar :title="title" :menus="menus" />
  <v-alert
    v-if="playbackMode === 'playback'"
    class="playback text-overline mb-1 py-0 align-center justify-center flex-0-0"
    type="warning"
    variant="tonal"
    density="compact"
    border="start"
    :icon="false"
  >
    <span class="d-inline-flex align-center">
      <v-icon icon="mdi-play-circle-outline" size="16" class="mr-2" />
      Playback Mode
    </span>
  </v-alert>
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
            <playback-controls
              v-model="playbackDateTime"
              v-model:step="playbackStep"
              :time-zone="timeZone"
              :loading="playbackLoading"
              :storage-key="configKey"
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
          :initial-width="def.width"
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
  PlaybackControls,
  SaveConfigDialog,
  TopBar,
} from '@openc3/vue-common/components'
import { useStore } from '@openc3/vue-common/plugins'
import NewScreenDialog from './NewScreenDialog'

export default {
  components: {
    TopBar,
    Openc3Screen,
    PlaybackControls,
    NewScreenDialog,
    OpenConfigDialog,
    SaveConfigDialog,
  },
  mixins: [Config],
  setup() {
    const store = useStore()
    return { store }
  },
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
      playbackStep: 1,
      playbackDateTime: null,
      playbackMode: 'realtime',
    }
  },
  computed: {
    playbackLoading: function () {
      return this.store.playback.playbackLoading > 0
    },
    menus: function () {
      return [
        {
          label: 'File',
          items: [
            {
              label: 'Playback Mode',
              checkbox: true,
              checked: this.playbackMode === 'playback',
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
          width: def.width,
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
    playbackMode: function () {
      this.store.updatePlayback({
        playbackMode: this.playbackMode,
        playbackDateTime: this.playbackDateTime,
        playbackStep: this.playbackStep,
      })
    },
    playbackDateTime: function () {
      this.store.updatePlayback({
        playbackMode: this.playbackMode,
        playbackDateTime: this.playbackDateTime,
        playbackStep: this.playbackStep,
      })
    },
    playbackStep: function () {
      this.store.updatePlayback({
        playbackMode: this.playbackMode,
        playbackDateTime: this.playbackDateTime,
        playbackStep: this.playbackStep,
      })
    },
  },
  async created() {
    // Ensure Offline Access Is Setup For the Current User
    this.api = new OpenC3Api()
    this.api.ensure_offline_access()
    await this.api
      .get_setting('time_zone')
      .then((response) => {
        if (response) {
          this.timeZone = response
        }
      })
      .catch((error) => {
        // Do nothing
      })
    Api.get('/openc3-api/screens')
      .then((response) => {
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
      .catch((error) => {
        console.error('Error loading screens:', error)
      })
    Api.get('/openc3-api/autocomplete/keywords/screen')
      .then((response) => {
        this.keywords = response.data
      })
      .catch((error) => {
        console.error('Error loading screen keywords:', error)
      })
  },
  mounted() {
    this.grid = new Muuri('.grid', {
      dragEnabled: true,
      // Only allow drags starting from the v-toolbar title
      dragHandle: '.v-toolbar',
    })
    this.grid.on('dragEnd', this.refreshLayout)
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
            if (!item.hidden) {
              // Bracket characters need to be escaped with double brackets
              // This is to distinguish them from individual array items
              // See LabelvalueWidget.vue, VWidget.js, and GraphWidget.js
              const name = item.name.replace(/\[/g, '[[').replace(/\]/g, ']]')
              text += `  LABELVALUE ${targetName} ${packetName} ${name}\n`
            }
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
          if (!response || !response.data) return
          this.pushScreen({
            id: this.counter++,
            target: target,
            screen: screen,
            definition: response.data,
            floated: false,
            top: 0,
            left: 0,
            zIndex: 0,
            width: null,
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
          delete this.screens[def.target]
        }
      }
    },
    floatScreen(definition, floated, top, left, zIndex, width) {
      definition.floated = floated
      definition.top = top
      definition.left = left
      definition.zIndex = zIndex
      definition.width = width
      let items = this.grid.getItems([
        document.getElementById(this.screenId(definition.id)),
      ])
      this.grid.remove(items)
      this.grid.refreshItems().layout()
    },
    unfloatScreen(definition, floated, top, left, zIndex, width) {
      definition.floated = floated
      definition.top = top
      definition.left = left
      definition.zIndex = zIndex
      definition.width = width
      let items = [document.getElementById(this.screenId(definition.id))]
      this.grid.add(items)
      this.grid.refreshItems().layout()
    },
    dragScreen(definition, floated, top, left, zIndex, width) {
      definition.floated = floated
      definition.top = top
      definition.left = left
      definition.zIndex = zIndex
      definition.width = width
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
            // loadScreen catches its own errors and resolves undefined (a
            // removed plugin makes 404 expected), so skip screens that
            // failed rather than dereferencing undefined in the timeout
            // below, where the TypeError would be unrecoverable.
            if (!response || !response.data) return
            setTimeout(() => {
              let floated = definition.floated
              if (!floated) {
                floated = false
              }
              let top = definition.top || 0
              let left = definition.left || 0
              let zIndex = definition.zIndex || 0
              let width = definition.width || null
              this.pushScreen({
                id: this.counter++,
                target: definition.target,
                screen: definition.screen,
                definition: response.data,
                floated: floated,
                top: top,
                left: left,
                zIndex: zIndex,
                width: width,
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
  },
}
</script>

<style scoped>
.playback :deep(.v-alert__content) {
  /* v-alert pads content to fit its default 28px icon; ours is 18px */
  padding-block: 0;
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
