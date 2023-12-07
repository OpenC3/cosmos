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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <top-bar :menus="menus" :title="title" />
    <v-expansion-panels v-model="panel" style="margin-bottom: 5px">
      <v-expansion-panel>
        <v-expansion-panel-header style="z-index: 1"></v-expansion-panel-header>
        <v-expansion-panel-content>
          <v-card>
            <div v-show="this.selectedGraphId === null">
              <v-row class="my-5">
                <v-spacer />
                <span>
                  Add a graph from the menu bar or select an existing graph to
                  continue
                </span>
                <v-spacer />
              </v-row>
            </div>

            <v-row
              class="px-1"
              justify="space-between"
              v-show="this.selectedGraphId !== null"
            >
              <v-col cols="11" style="padding-bottom: 0px">
                <target-packet-item-chooser
                  :initial-target-name="this.$route.params.target"
                  :initial-packet-name="this.$route.params.packet"
                  :initial-item-name="this.$route.params.item"
                  @click="addItem"
                  button-text="Add Item"
                  choose-item
                  select-types
                />
              </v-col>
              <v-col cols="1">
                <v-btn
                  v-show="state === 'pause'"
                  class="pulse"
                  v-on:click="
                    () => {
                      state = 'start'
                    }
                  "
                  color="primary"
                  fab
                  data-test="start-graph"
                >
                  <v-icon large>mdi-play</v-icon>
                </v-btn>
                <v-btn
                  v-show="state === 'start'"
                  v-on:click="
                    () => {
                      state = 'pause'
                    }
                  "
                  color="primary"
                  fab
                  data-test="pause-graph"
                >
                  <v-icon large>mdi-pause</v-icon>
                </v-btn>
              </v-col>
            </v-row>
          </v-card>
        </v-expansion-panel-content>
      </v-expansion-panel>
    </v-expansion-panels>
    <div>
      <div class="grid">
        <div
          class="item"
          v-for="graph in graphs"
          :key="graph"
          :id="`gridItem${graph}`"
          :ref="`gridItem${graph}`"
        >
          <div class="item-content">
            <graph
              :ref="`graph${graph}`"
              :id="graph"
              :state="state"
              :start-time="startTime"
              :selected-graph-id="selectedGraphId"
              :seconds-graphed="settings.secondsGraphed.value"
              :points-saved="settings.pointsSaved.value"
              :points-graphed="settings.pointsGraphed.value"
              :refresh-interval-ms="settings.refreshIntervalMs.value"
              @close-graph="() => closeGraph(graph)"
              @min-max-graph="() => minMaxGraph(graph)"
              @resize="() => resize()"
              @pause="() => (state = 'pause')"
              @start="() => (state = 'start')"
              @click="() => graphSelected(graph)"
              @edit="saveDefaultConfig(currentConfig)"
              @started="graphStarted"
            />
          </div>
        </div>
      </div>
    </div>
    <!-- Note we're using v-if here so it gets re-created each time and refreshes the list -->
    <open-config-dialog
      v-if="showOpenConfig"
      v-model="showOpenConfig"
      :configKey="configKey"
      @success="openConfiguration"
    />
    <!-- Note we're using v-if here so it gets re-created each time and refreshes the list -->
    <save-config-dialog
      v-if="showSaveConfig"
      v-model="showSaveConfig"
      :configKey="configKey"
      @success="saveConfiguration"
    />
    <!-- Note we're using v-if here so it gets re-created each time and refreshes the list -->
    <settings-dialog
      v-show="showSettingsDialog"
      v-model="showSettingsDialog"
      :settings="settings"
    />
  </div>
</template>

<script>
import Config from '@openc3/tool-common/src/components/config/Config'
import Graph from '@openc3/tool-common/src/components/Graph.vue'
import OpenConfigDialog from '@openc3/tool-common/src/components/config/OpenConfigDialog'
import SaveConfigDialog from '@openc3/tool-common/src/components/config/SaveConfigDialog'
import TargetPacketItemChooser from '@openc3/tool-common/src/components/TargetPacketItemChooser'
import TopBar from '@openc3/tool-common/src/components/TopBar'
import Muuri from 'muuri'

import SettingsDialog from '@/tools/TlmGrapher/SettingsDialog'

const MURRI_REFRESH_TIME = 250
export default {
  components: {
    Graph,
    OpenConfigDialog,
    SaveConfigDialog,
    SettingsDialog,
    TargetPacketItemChooser,
    TopBar,
  },
  mixins: [Config],
  data() {
    return {
      title: 'COSMOS Telemetry Grapher',
      configKey: 'telemetry_grapher',
      showOpenConfig: false,
      showSaveConfig: false,
      showSettingsDialog: false,
      grid: null,
      panel: 0,
      state: 'stop', // Valid: stop, start, pause
      startTime: null, // Start time in nanoseconds
      // Setup defaults to show an initial graph
      graphs: [0],
      selectedGraphId: 0,
      counter: 1,
      applyingConfig: false,
      menus: [
        {
          label: 'File',
          items: [
            {
              label: 'Open Configuration',
              icon: 'mdi-folder-open',
              command: () => {
                this.showOpenConfig = true
              },
            },
            {
              label: 'Save Configuration',
              icon: 'mdi-content-save',
              command: () => {
                this.showSaveConfig = true
              },
            },
            {
              label: 'Reset Configuration',
              icon: 'mdi-monitor-shimmer',
              command: () => {
                this.panel = 0 // Expand the expansion panel
                this.closeAllGraphs()
                this.resetConfigBase()
              },
            },
          ],
        },
        {
          label: 'Graph',
          items: [
            {
              label: 'Add Graph',
              icon: 'mdi-plus',
              command: () => {
                this.addGraph()
              },
            },
            {
              divider: true,
            },
            {
              label: 'Start / Resume',
              icon: 'mdi-play',
              command: () => {
                this.state = 'start'
              },
            },
            {
              label: 'Pause',
              icon: 'mdi-pause',
              command: () => {
                this.state = 'pause'
              },
            },
            {
              label: 'Stop',
              icon: 'mdi-stop',
              command: () => {
                this.state = 'stop'
              },
            },
            {
              divider: true,
            },
            {
              label: 'Settings',
              icon: 'mdi-cog',
              command: () => {
                this.showSettingsDialog = true
              },
            },
          ],
        },
      ],
      settings: {
        secondsGraphed: {
          title: 'Seconds Graphed',
          value: 1000,
          rules: [(value) => !!value || 'Required'],
        },
        pointsSaved: {
          title: 'Points Saved',
          value: 1000000,
          rules: [(value) => !!value || 'Required'],
        },
        pointsGraphed: {
          title: 'Points Graphed',
          value: 1000,
          rules: [(value) => !!value || 'Required'],
        },
        refreshIntervalMs: {
          title: 'Refresh Interval Ms',
          value: 100,
          rules: [(value) => !!value || 'Required'],
        },
      },
    }
  },
  watch: {
    settings: {
      handler: function () {
        this.saveDefaultConfig(this.currentConfig)
      },
      deep: true,
    },
  },
  computed: {
    currentConfig: function () {
      return {
        settings: {
          secondsGraphed: this.settings.secondsGraphed.value,
          pointsSaved: this.settings.pointsSaved.value,
          pointsGraphed: this.settings.pointsGraphed.value,
          refreshIntervalMs: this.settings.refreshIntervalMs.value,
        },
        graphs: this.grid.getItems().map((item) => {
          // Map the gridItem id to the graph id
          const graphId = `graph${item.getElement().id.substring(8)}`
          const vueGraph = this.$refs[graphId][0]
          let config = {
            items: vueGraph.items,
            title: vueGraph.title,
            fullWidth: vueGraph.fullWidth,
            fullHeight: vueGraph.fullHeight,
            graphMinX: vueGraph.graphMinX,
            graphMaxX: vueGraph.graphMaxX,
            legendPosition: vueGraph.legendPosition,
          }
          // Only add the start and end time if we have both
          // This prevents adding just the start time and having the graph
          // try to pull a LOT of data from some previously set date / time
          if (vueGraph.graphStartDateTime && vueGraph.graphEndDateTime) {
            config.graphStartDateTime = vueGraph.graphStartDateTime
            config.graphEndDateTime = vueGraph.graphEndDateTime
          }
          return config
        }),
      }
    },
  },
  mounted: function () {
    this.grid = new Muuri('.grid', {
      dragEnabled: true,
      layoutOnResize: true,
      // Only allow drags starting from the v-system-bar title
      dragHandle: '.v-system-bar',
    })
    // Sometimes when we move graphs, other graphs become non-interactive
    // This seems to fix that issue
    this.grid.on('move', function (data) {
      data.item.getGrid().synchronize()
    })

    // Called like /tools/tlmgrapher?config=temps
    if (this.$route.query && this.$route.query.config) {
      this.openConfiguration(this.$route.query.config, true) // routed
    }
    // If we're passed in the route then manually addItem
    else if (
      this.$route.params.target &&
      this.$route.params.packet &&
      this.$route.params.item
    ) {
      this.addItem({
        targetName: this.$route.params.target.toUpperCase(),
        packetName: this.$route.params.packet.toUpperCase(),
        itemName: this.$route.params.item.toUpperCase(),
        valueType: 'CONVERTED',
        reduced: 'DECOM',
      })
    } else {
      let config = this.loadDefaultConfig()
      // Only apply the config if it's not an empty object (config does not exist)
      if (JSON.stringify(config) !== '{}') {
        this.applyConfig(config)
      }
    }
  },
  methods: {
    graphSelected: function (id) {
      this.selectedGraphId = id
    },
    addItem: function (newItem, startGraphing = true) {
      for (const item of this.$refs[`graph${this.selectedGraphId}`][0].items) {
        if (
          newItem.targetName === item.targetName &&
          newItem.packetName === item.packetName &&
          newItem.itemName === item.itemName &&
          newItem.valueType === item.valueType &&
          newItem.reduced === item.reduced &&
          newItem.reducedType === item.reducedType
        ) {
          this.$notify.caution({
            title: 'Item Already Exists',
            body:
              `Item ${newItem.targetName} ${newItem.packetName} ${newItem.itemName} ` +
              `with ${newItem.valueType} ${newItem.reduced} ${newItem.reducedType} already exists!`,
          })
          return
        }
      }
      this.$refs[`graph${this.selectedGraphId}`][0].addItems([newItem])
      if (startGraphing === true) {
        this.state = 'start'
      }
      this.saveDefaultConfig(this.currentConfig)
    },
    addGraph: function () {
      const id = this.counter
      this.graphs.push(id)
      this.counter += 1
      this.$nextTick(function () {
        var items = this.grid.add(this.$refs[`gridItem${id}`], {
          active: false,
        })
        this.grid.show(items)
        this.selectedGraphId = id
        setTimeout(() => {
          this.grid.refreshItems().layout()
        }, MURRI_REFRESH_TIME)
      })
      this.saveDefaultConfig(this.currentConfig)
    },
    closeGraph: function (id) {
      var items = this.grid.getItems([document.getElementById(`gridItem${id}`)])
      this.grid.remove(items)
      this.graphs.splice(this.graphs.indexOf(id), 1)
      this.selectedGraphId = null
      // Clear out the startTime if we close all the graphs ... we're starting over
      if (this.graphs.length === 0) {
        this.startTime = null
      }
      this.saveDefaultConfig(this.currentConfig)
    },
    closeAllGraphs: function () {
      // Make a copy of this.graphs to iterate on since closeGraph modifies in place
      for (let graph of [...this.graphs]) {
        this.closeGraph(graph)
      }
      this.counter = 0
    },
    minMaxGraph: function (id) {
      this.selectedGraphId = id
      setTimeout(
        () => {
          this.grid.refreshItems().layout()
        },
        MURRI_REFRESH_TIME * 2, // Double the time since there is more animation
      )
      this.saveDefaultConfig(this.currentConfig)
    },
    resize: function () {
      setTimeout(
        () => {
          this.grid.refreshItems().layout()
        },
        MURRI_REFRESH_TIME * 2, // Double the time since there is more animation
      )
    },
    graphStarted: function (time) {
      // Only set startTime once when notified by the first graph to start
      // This allows us to have a uniform start time on all graphs
      if (this.startTime === null) {
        this.startTime = time
      }
    },
    applyConfig: async function (config) {
      // Don't save the default config while we're applying new config
      this.dontSaveDefaultConfig = true
      this.closeAllGraphs()
      await this.$nextTick()

      this.settings.secondsGraphed.value = config.settings.secondsGraphed
      this.settings.pointsSaved.value = config.settings.pointsSaved
      this.settings.pointsGraphed.value = config.settings.pointsGraphed
      this.settings.refreshIntervalMs.value = config.settings.refreshIntervalMs

      let graphs = config.graphs
      for (let graph of graphs) {
        this.addGraph()
      }
      await this.$nextTick()
      const that = this
      graphs.forEach(function (graph, i) {
        let vueGraph = that.$refs[`graph${i}`][0]
        vueGraph.title = graph.title
        vueGraph.fullWidth = graph.fullWidth
        vueGraph.fullHeight = graph.fullHeight
        vueGraph.graphMinX = graph.graphMinX
        vueGraph.graphMaxX = graph.graphMaxX
        vueGraph.graphStartDateTime = graph.graphStartDateTime
        vueGraph.graphEndDateTime = graph.graphEndDateTime
        vueGraph.moveLegend(graph.legendPosition)
        vueGraph.addItems([...graph.items])
      })
      this.state = 'start'
      this.dontSaveDefaultConfig = false
    },
    openConfiguration: function (name, routed = false) {
      this.openConfigBase(name, routed, async (config) => {
        await this.applyConfig(config)
        this.saveDefaultConfig(config)
      })
      this.panel = null // Minimize the expansion panel
    },
    saveConfiguration: function (name) {
      this.saveConfigBase(name, this.currentConfig)
    },
  },
}
</script>

<style>
/* Flash the chevron icon 3 times to let the user know they can minimize the controls */
i.v-icon.mdi-chevron-down {
  animation: pulse 2s 3;
}
@keyframes pulse {
  0% {
    -webkit-box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.4);
  }
  70% {
    -webkit-box-shadow: 0 0 0 10px rgba(255, 255, 255, 0);
  }
  100% {
    -webkit-box-shadow: 0 0 0 0 rgba(255, 255, 255, 0);
  }
}
</style>
<style lang="scss" scoped>
.v-expansion-panel-content {
  background-color: var(--v-tertiary-darken2);
  .container {
    margin: 0px;
  }
}
.v-expansion-panel-header {
  min-height: 10px;
  padding: 5px;
  background-color: var(--v-tertiary-darken2);
}
.v-navigation-drawer {
  z-index: 2;
}
.theme--dark.v-navigation-drawer {
  background-color: var(--v-primary-darken2);
}
.grid {
  position: relative;
}
.item {
  position: absolute;
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
  margin: 5px;
}

.pulse {
  animation: pulse 1s infinite;
}

@keyframes pulse {
  0% {
    opacity: 1;
  }

  50% {
    opacity: 0.5;
  }
}
</style>
