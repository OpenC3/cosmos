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
#
# A portion of this file was funded by Blue Origin Enterprises, L.P.
# See https://github.com/OpenC3/cosmos/pull/1957
-->

<template>
  <div @click.prevent="$emit('click')">
    <v-card>
      <v-toolbar
        height="24"
        class="pl-2 pr-2"
        :class="selectedGraphId === id ? 'active' : ''"
        v-show="!hideToolbarData"
      >
        <div v-show="errors.length !== 0" class="mx-2">
          <v-tooltip text="Errors" location="top">
            <template v-slot:activator="{ props }">
              <v-icon v-bind="props" @click="errorDialog = true">
                mdi-alert
              </v-icon>
            </template>
          </v-tooltip>
        </div>

        <v-tooltip text="Edit" location="top">
          <template v-slot:activator="{ props }">
            <v-icon
              v-bind="props"
              @click="editGraph = true"
              data-test="edit-graph-icon"
            >
              mdi-pencil
            </v-icon>
          </template>
        </v-tooltip>

        <v-spacer />
        <span> {{ title }} </span>
        <v-spacer />

        <div v-show="expand">
          <v-tooltip v-if="calcFullSize" text="Collapse" location="top">
            <template v-slot:activator="{ props }">
              <v-icon
                v-bind="props"
                @click="collapseAll"
                data-test="collapse-all"
              >
                mdi-arrow-collapse
              </v-icon>
            </template>
          </v-tooltip>
          <v-tooltip v-else text="Expand" location="top">
            <template v-slot:activator="{ props }">
              <v-icon v-bind="props" @click="expandAll" data-test="expand-all">
                mdi-arrow-expand
              </v-icon>
            </template>
          </v-tooltip>
        </div>

        <div v-show="expand">
          <v-tooltip v-if="fullWidth" text="Collapse Width" location="top">
            <template v-slot:activator="{ props }">
              <v-icon
                v-bind="props"
                @click="collapseWidth"
                data-test="collapse-width"
              >
                mdi-arrow-collapse-horizontal
              </v-icon>
            </template>
          </v-tooltip>
          <v-tooltip v-else text="Expand Width" location="top">
            <template v-slot:activator="{ props }">
              <v-icon
                v-bind="props"
                @click="expandWidth"
                data-test="expand-width"
              >
                mdi-arrow-expand-horizontal
              </v-icon>
            </template>
          </v-tooltip>
        </div>

        <div v-show="expand">
          <v-tooltip v-if="fullHeight" text="Collapse Height" location="top">
            <template v-slot:activator="{ props }">
              <v-icon
                v-bind="props"
                @click="collapseHeight"
                data-test="collapse-height"
              >
                mdi-arrow-collapse-vertical
              </v-icon>
            </template>
          </v-tooltip>
          <v-tooltip v-else text="Expand Height" location="top">
            <template v-slot:activator="{ props }">
              <v-icon
                v-bind="props"
                @click="expandHeight"
                data-test="expand-height"
              >
                mdi-arrow-expand-vertical
              </v-icon>
            </template>
          </v-tooltip>
        </div>

        <v-tooltip v-if="expand" text="Minimize" location="top">
          <template v-slot:activator="{ props }">
            <v-icon
              v-bind="props"
              @click="minMaxTransition"
              data-test="minimize-screen-icon"
            >
              mdi-window-minimize
            </v-icon>
          </template>
        </v-tooltip>
        <v-tooltip v-else text="Maximize" location="top">
          <template v-slot:activator="{ props }">
            <v-icon
              v-bind="props"
              @click="minMaxTransition"
              data-test="maximize-screen-icon"
            >
              mdi-window-maximize
            </v-icon>
          </template>
        </v-tooltip>

        <v-tooltip text="Close" location="top">
          <template v-slot:activator="{ props }">
            <v-icon
              v-bind="props"
              @click="$emit('close-graph')"
              data-test="close-graph-icon"
            >
              mdi-close-box
            </v-icon>
          </template>
        </v-tooltip>
      </v-toolbar>

      <v-expand-transition>
        <div class="pa-1" id="chart" ref="chart" v-show="expand">
          <div :id="`chart${id}`"></div>
          <div id="betweenCharts"></div>
          <div :id="`overview${id}`" v-show="showOverview"></div>
        </div>
      </v-expand-transition>
    </v-card>

    <!-- Edit graph dialog -->
    <graph-edit-dialog
      v-if="editGraph"
      v-model="editGraph"
      :title="title"
      :legend-position="legendPosition"
      :items="items"
      :graph-min-y="graphMinY"
      :graph-max-y="graphMaxY"
      :lines="lines"
      :colors="colors"
      :start-date-time="graphStartDateTime"
      :end-date-time="graphEndDateTime"
      :time-zone="timeZone"
      @remove="removeItems([$event])"
      @ok="editGraphClose"
      @cancel="editGraph = false"
    />

    <!-- Error dialog -->
    <v-dialog v-model="errorDialog" max-width="600">
      <v-toolbar height="24">
        <v-spacer />
        <span> Errors </span>
        <v-spacer />
      </v-toolbar>
      <v-card class="pa-3">
        <v-row dense>
          <v-text-field
            readonly
            hide-details
            v-model="title"
            class="pb-2"
            label="Graph Title"
          />
        </v-row>
        <v-row class="my-3">
          <v-textarea readonly rows="8" :value="error" />
        </v-row>
        <v-row>
          <v-btn block @click="clearErrors"> Clear </v-btn>
        </v-row>
      </v-card>
    </v-dialog>

    <!-- Edit right click context menu -->
    <v-menu
      v-if="editGraphMenu"
      v-model="editGraphMenu"
      :target="[editGraphMenuX, editGraphMenuY]"
      absolute
      offset-y
    >
      <v-list>
        <v-list-item @click="editGraph = true">
          <v-list-item-title style="cursor: pointer">
            Edit {{ title }}
          </v-list-item-title>
        </v-list-item>
      </v-list>
    </v-menu>

    <graph-edit-item-dialog
      v-if="editItem"
      v-model="editItem"
      :colors="colors"
      :item="selectedItem"
      @changeColor="changeColor"
      @changeLimits="changeLimits"
      @cancel="editItem = false"
      @close="closeEditItem"
    />

    <!-- Edit Item right click context menu -->
    <v-menu
      v-if="itemMenu"
      v-model="itemMenu"
      :target="[itemMenuX, itemMenuY]"
      absolute
      offset-y
    >
      <v-list nav density="compact">
        <v-list-subheader>
          {{ selectedItem.targetName }}
          {{ selectedItem.packetName }}
          {{ selectedItem.itemName }}
        </v-list-subheader>
        <v-list-item @click="editItem = true">
          <template v-slot:prepend>
            <v-icon icon="mdi-pencil" />
          </template>
          <v-list-item-title> Edit </v-list-item-title>
        </v-list-item>
        <v-list-item @click="clearData([selectedItem])">
          <template v-slot:prepend>
            <v-icon icon="mdi-eraser" />
          </template>
          <v-list-item-title> Clear </v-list-item-title>
        </v-list-item>
        <v-list-item @click="removeItems([selectedItem])">
          <template v-slot:prepend>
            <v-icon icon="mdi-delete" />
          </template>
          <v-list-item-title> Delete </v-list-item-title>
        </v-list-item>
      </v-list>
    </v-menu>

    <!-- Edit Legend right click context menu -->
    <v-menu
      v-if="legendMenu"
      v-model="legendMenu"
      :target="[legendMenuX, legendMenuY]"
      absolute
      offset-y
    >
      <v-list>
        <v-list-item @click="moveLegend('top')">
          <v-list-item-title style="cursor: pointer">
            Legend Top
          </v-list-item-title>
        </v-list-item>
        <v-list-item @click="moveLegend('bottom')">
          <v-list-item-title style="cursor: pointer">
            Legend Bottom
          </v-list-item-title>
        </v-list-item>
        <v-list-item @click="moveLegend('left')">
          <v-list-item-title style="cursor: pointer">
            Legend Left
          </v-list-item-title>
        </v-list-item>
        <v-list-item @click="moveLegend('right')">
          <v-list-item-title style="cursor: pointer">
            Legend RIght
          </v-list-item-title>
        </v-list-item>
      </v-list>
    </v-menu>

    <div v-if="!sparkline" class="u-series" ref="info">
      <v-tooltip
        text="Click item to toggle, Right click to edit"
        location="top"
      >
        <template v-slot:activator="{ props }">
          <v-icon v-bind="props"> mdi-information-variant-circle </v-icon>
        </template>
      </v-tooltip>
    </div>
  </div>
</template>

<script>
import GraphEditDialog from './GraphEditDialog.vue'
import GraphEditItemDialog from './GraphEditItemDialog.vue'
import uPlot from 'uplot'
import bs from 'binary-search'
import { Cable } from '@openc3/js-common/services'
import { TimeFilters } from '@/util'

import 'uplot/dist/uPlot.min.css'

export default {
  components: {
    GraphEditDialog,
    GraphEditItemDialog,
  },
  props: {
    id: {
      type: Number,
      required: true,
    },
    selectedGraphId: {
      type: Number,
      // Not required because we pass null
    },
    state: {
      type: String,
      required: true,
    },
    // start time in nanoseconds to start the graph
    // this allows multiple graphs to be synchronized
    startTime: {
      type: Number,
    },
    secondsGraphed: {
      type: Number,
      required: true,
    },
    pointsSaved: {
      type: Number,
      required: true,
    },
    pointsGraphed: {
      type: Number,
      required: true,
    },
    refreshIntervalMs: {
      type: Number,
      default: 200,
    },
    hideToolbar: {
      type: Boolean,
      default: false,
    },
    hideOverview: {
      type: Boolean,
      default: false,
    },
    sparkline: {
      type: Boolean,
      default: false,
    },
    initialItems: {
      type: Array,
    },
    // These allow the parent to force a specific height and/or width
    height: {
      type: Number,
    },
    width: {
      type: Number,
    },
    timeZone: {
      type: String,
      default: 'local',
    },
  },
  mixins: [TimeFilters],
  data() {
    return {
      lines: [],
      active: true,
      expand: true,
      fullWidth: true,
      fullHeight: true,
      graph: null,
      editGraph: false,
      editGraphMenu: false,
      editGraphMenuX: 0,
      editGraphMenuY: 0,
      editItem: false,
      itemMenu: false,
      itemMenuX: 0,
      itemMenuY: 0,
      legendMenu: false,
      legendMenuX: 0,
      legendMenuY: 0,
      legendPosition: 'bottom',
      selectedItem: null,
      hideToolbarData: this.hideToolbar,
      showOverview: !this.hideOverview,
      hideOverviewData: this.hideOverview,
      title: '',
      overview: null,
      data: [[]],
      dataChanged: false,
      timeout: null,
      graphMinY: null,
      graphMaxY: null,
      graphStartDateTime: null,
      graphEndDateTime: null,
      indexes: {},
      items: this.initialItems || [],
      limitsValues: [],
      drawInterval: null,
      zoomChart: false,
      zoomOverview: false,
      cable: new Cable(),
      subscription: null,
      needToUpdate: false,
      errorDialog: false,
      errors: [],
      colorIndex: 0,
      colors: [
        // The first 3 are taken from the Astro css definitions for
        // --color-data-visualization-1 through 3
        '#00c7cb',
        '#938bdb',
        '#4dacff',
        'lime',
        'darkorange',
        'red',
        'gold',
        'hotpink',
        'tan',
        'cyan',
        'maroon',
        'blue',
        'teal',
        'purple',
        'green',
        'brown',
        'lightblue',
        'white',
        'black',
      ],
    }
  },
  computed: {
    calcFullSize: function () {
      return this.fullWidth || this.fullHeight
    },
    error: function () {
      if (this.errorDialog && this.errors.length > 0) {
        return JSON.stringify(this.errors, null, 4)
      }
      return null
    },
  },
  created() {
    this.title = `Graph ${this.id}`
    for (const [index, item] of this.items.entries()) {
      this.data.push([]) // initialize the empty data arrays
      this.indexes[this.subscriptionKey(item)] = index + 1
      if (item.color === undefined) {
        item.color = this.colors[this.colorIndex]
      }
      this.colorIndex++
      if (this.colorIndex === this.colors.length) {
        this.colorIndex = 0
      }
    }
  },
  mounted() {
    // This code allows for temporary pulling in a patched uPlot
    // Also note you need to add 'async' before the mounted method for await
    // const plugin = document.createElement('script')
    // plugin.setAttribute(
    //   'src',
    //   'https://leeoniya.github.io/uPlot/dist/uPlot.iife.min.js'
    // )
    // plugin.async = true
    // document.head.appendChild(plugin)
    // await new Promise(r => setTimeout(r, 500)) // Allow the js to load

    // TODO: This is demo / performance code of multiple items with many data points
    // 10 items at 500,000 each renders immediately and uses 180MB in Chrome
    // Refresh still works, chrome is sluggish but once you pause it is very performant
    // 500,000 pts at 1Hz is 138.9hrs .. almost 6 days
    //
    // 10 items at 100,000 each is very performant ... 1,000,000 pts is Qt TlmGrapher default
    // 100,000 pts at 1Hz is 27.8hrs
    //
    // 100,000 takes 40ms, Chrome uses 160MB
    // this.data = []
    // const dataPoints = 100000
    // const items = 10
    // let pts = new Array(dataPoints)
    // let times = new Array(dataPoints)
    // let time = 1589398007
    // let series = [{}]
    // for (let i = 0; i < dataPoints; i++) {
    //   times[i] = time
    //   pts[i] = i
    //   time += 1
    // }
    // this.data.push(times)
    // for (let i = 0; i < items; i++) {
    //   this.data.push(pts.map(x => x + i))
    //   series.push({
    //     label: 'Item' + i,
    //     stroke: this.colors[i]
    //   })
    // }

    // NOTE: These are just initial settings ... actual series are added by this.graph.addSeries
    const { chartSeries, overviewSeries } = this.items.reduce(
      (seriesObj, item) => {
        const commonProps = {
          spanGaps: true,
        }
        seriesObj.chartSeries.push({
          ...commonProps,
          item: item,
          label: this.formatLabel(item),
          stroke: (u, seriesIdx) => {
            return this.items[seriesIdx - 1].color
          },
          width: 2,
          value: (self, rawValue) => {
            if (typeof rawValue === 'string' || isNaN(rawValue)) {
              return 'NaN'
            } else {
              return rawValue == null ? '--' : rawValue.toFixed(3)
            }
          },
        })
        seriesObj.overviewSeries.push({
          ...commonProps,
        })
        return seriesObj
      },
      { chartSeries: [], overviewSeries: [] },
    )

    let chartOpts = {}
    if (this.sparkline) {
      this.hideToolbarData = true
      this.hideOverviewData = true
      this.showOverview = false
      chartOpts = {
        width: this.width,
        height: this.height,
        pxAlign: false,
        cursor: {
          show: false,
        },
        select: {
          show: false,
        },
        legend: {
          show: false,
        },
        scales: {
          x: {
            time: false,
          },
        },
        axes: [
          {
            show: false,
          },
          {
            show: false,
          },
        ],
        series: [
          {},
          {
            stroke: 'white', // TODO: Light / dark theme
          },
        ],
      }
      this.graph = new uPlot(
        chartOpts,
        this.data,
        document.getElementById(`chart${this.id}`),
      )
    } else {
      // Uplot wants the real timezone name ('local' doesn't work)
      let timeZoneName = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (this.timeZone && this.timeZone !== 'local') {
        timeZoneName = this.timeZone
      }
      chartOpts = {
        ...this.getSize('chart'),
        ...this.getScales(),
        ...this.getAxes('chart'),
        // series: series, // TODO: Uncomment with the performance code
        plugins: [this.linesPlugin()],
        tzDate: (ts) => uPlot.tzDate(new Date(ts * 1e3), timeZoneName),
        series: [
          {
            label: 'Time',
            value: (u, v) =>
              // Convert the unix timestamp into a formatted date / time
              v == null ? '--' : this.formatSeconds(v, this.timeZone),
          },
          ...chartSeries,
        ],
        cursor: {
          drag: {
            x: true,
            y: false,
          },
          // Sync the cursor across graphs so mouseovers are synced
          sync: {
            key: 'openc3',
            // setSeries links graphs so clicking an item to hide it also hides the other graph item
            // setSeries: true,
          },
          bind: {
            mouseup: (self, targ, handler) => {
              return (e) => {
                // Single click while paused will resume the graph
                // This makes it possible to resume in TlmViewer widgets
                if (this.state === 'pause' && self.select.width === 0) {
                  this.$emit('start')
                }
                handler(e)
              }
            },
          },
        },
        hooks: {
          setScale: [
            (chart, key) => {
              if (key === 'x' && !this.zoomOverview && this.overview) {
                this.zoomChart = true
                let left = Math.round(
                  this.overview.valToPos(chart.scales.x.min, 'x'),
                )
                let right = Math.round(
                  this.overview.valToPos(chart.scales.x.max, 'x'),
                )
                this.overview.setSelect({ left, width: right - left })
                this.zoomChart = false
              }
            },
          ],
          setSelect: [
            (chart) => {
              // Pause the graph while selecting a range to zoom
              if (this.state === 'start' && chart.select.width > 0) {
                this.$emit('pause')
              }
            },
          ],
          ready: [
            (u) => {
              let canvas = u.root.querySelector('.u-over')
              canvas.addEventListener('contextmenu', (e) => {
                e.preventDefault()
                this.itemMenu = false
                this.legendMenu = false
                this.editGraphMenuX = e.clientX
                this.editGraphMenuY = e.clientY
                this.editGraphMenu = true
              })
              let legend = u.root.querySelector('.u-legend')
              legend.addEventListener('contextmenu', (e) => {
                e.preventDefault()
                this.editGraphMenu = false
                this.legendMenu = false
                this.itemMenuX = e.clientX
                this.itemMenuY = e.clientY
                // Grab the closest series and then figure out which index it is
                let seriesEl = e.target.closest('.u-series')
                let seriesIdx = Array.prototype.slice
                  .call(legend.childNodes[0].childNodes)
                  .indexOf(seriesEl)
                let series = u.series[seriesIdx]
                if (series.item) {
                  this.selectedItem = series.item
                  this.itemMenu = true
                } else {
                  this.itemMenu = false
                  this.legendMenuX = e.clientX
                  this.legendMenuY = e.clientY
                  this.legendMenu = true
                }
              })
              // Append the info to the legend
              legend.querySelector('tbody').appendChild(this.$refs.info)
            },
          ],
        },
      }
      this.graph = new uPlot(
        chartOpts,
        this.data,
        document.getElementById(`chart${this.id}`),
      )

      const overviewOpts = {
        ...this.getSize('overview'),
        ...this.getScales(),
        ...this.getAxes('overview'),
        // series: series, // TODO: Uncomment with the performance code
        tzDate: (ts) => uPlot.tzDate(new Date(ts * 1e3), timeZoneName),
        series: [...overviewSeries],
        cursor: {
          y: false,
          drag: {
            setScale: false,
            x: true,
            y: false,
          },
        },
        legend: {
          show: false,
        },
        hooks: {
          setSelect: [
            (chart) => {
              if (!this.zoomChart) {
                // Pause the graph while selecting an overview range to zoom
                if (this.state === 'start' && chart.select.width > 0) {
                  this.$emit('pause')
                }
                this.zoomOverview = true
                let min = chart.posToVal(chart.select.left, 'x')
                let max = chart.posToVal(
                  chart.select.left + chart.select.width,
                  'x',
                )
                this.graph.setScale('x', { min, max })
                this.zoomOverview = false
              }
            },
          ],
        },
      }
      if (!this.hideOverview) {
        this.overview = new uPlot(
          overviewOpts,
          this.data,
          document.getElementById(`overview${this.id}`),
        )
      }
      this.moveLegend(this.legendPosition)

      // Allow the charts to dynamically resize when the window resizes
      window.addEventListener('resize', this.resize)
    }

    if (this.state !== 'stop') {
      this.startGraph()
    }
  },
  beforeUnmount: function () {
    this.stopGraph()
    this.cable.disconnect()
    window.removeEventListener('resize', this.resize)
  },
  watch: {
    state: function (newState, oldState) {
      switch (newState) {
        case 'start':
          // Only subscribe if we were previously stopped
          // If we were paused we do nothing ... see the data function
          if (oldState === 'stop') {
            this.startGraph()
          }
          break
        // case 'pause': Nothing to do ... see the data function
        case 'stop':
          this.stopGraph()
          break
      }
    },
    data: function (newData, oldData) {
      this.dataChanged = true
    },
    graphMinY: function (newVal, oldVal) {
      let val = parseFloat(newVal)
      if (!isNaN(val)) {
        this.graphMinY = val
      }
      this.setGraphRange()
    },
    graphMaxY: function (newVal, oldVal) {
      let val = parseFloat(newVal)
      if (!isNaN(val)) {
        this.graphMaxY = val
      }
      this.setGraphRange()
    },
    graphStartDateTime: function (newVal, oldVal) {
      if (newVal && typeof newVal === 'string') {
        this.graphStartDateTime =
          this.parseDateTime(this.graphStartDateTime, this.timeZone) * 1000000
        if (this.graphStartDateTime !== oldVal) {
          this.needToUpdate = true
        }
      } else if (newVal === null && oldVal) {
        // If they clear the start date time we need to update
        this.graphStartDateTime = null
        this.needToUpdate = true
      }
    },
    graphEndDateTime: function (newVal, oldVal) {
      if (newVal && typeof newVal === 'string') {
        this.graphEndDateTime =
          this.parseDateTime(this.graphEndDateTime, this.timeZone) * 1000000
        if (this.graphEndDateTime !== oldVal) {
          this.needToUpdate = true
        }
      } else if (newVal === null && oldVal) {
        // If they clear the end date time we need to update
        this.graphEndDateTime = null
        this.needToUpdate = true
      }
    },
  },
  methods: {
    startGraph: function () {
      this.subscribe()
      this.timeout = setTimeout(() => {
        this.updateTimeout()
      }, this.refreshIntervalMs)
    },
    stopGraph: function () {
      if (this.subscription) {
        this.subscription.unsubscribe()
        this.subscription = null
      }
      if (this.timeout) {
        clearTimeout(this.timeout)
        this.timeout = null
      }
    },
    updateTimeout: function () {
      this.updateGraphData()
      this.timeout = setTimeout(() => {
        this.updateTimeout()
      }, this.refreshIntervalMs)
    },
    updateGraphData: function () {
      // Ignore changes to the data while we're paused
      if (this.state === 'pause' || !this.dataChanged) {
        return
      }
      this.graph.setData(this.data)
      if (this.overview) {
        this.overview.setData(this.data)
      }
      let max = this.data[0][this.data[0].length - 1]
      let ptsMin = this.data[0][this.data[0].length - this.pointsGraphed]
      let min = this.data[0][0]
      if (min < max - this.secondsGraphed) {
        min = max - this.secondsGraphed
      }
      if (ptsMin > min) {
        min = ptsMin
      }
      this.graph.setScale('x', { min, max })
      this.dataChanged = false
    },
    formatLabel(item) {
      if (item.valueType === 'CONVERTED' && item.reduced === 'DECOM') {
        return item.itemName
      } else {
        let description = ''
        // Only display valueType if we're not CONVERTED
        if (item.valueType !== 'CONVERTED') {
          description += item.valueType
        }
        // Only display reduced if we're not DECOM
        if (item.reduced !== 'DECOM') {
          // If we already have the valueType add a space
          if (description !== '') {
            description += ' '
          }
          description += `${item.reduced.split('_')[1]} ${item.reducedType}`
        }
        return `${item.itemName} (${description})`
      }
    },
    moveLegend: function (desired) {
      switch (desired) {
        case 'bottom':
          this.graph.root.classList.remove('side-legend')
          this.graph.root.classList.remove('left-legend')
          this.graph.root.classList.remove('top-legend')
          break
        case 'top':
          this.graph.root.classList.remove('side-legend')
          this.graph.root.classList.remove('left-legend')
          this.graph.root.classList.add('top-legend')
          break
        case 'left':
          this.graph.root.classList.remove('top-legend')
          this.graph.root.classList.add('side-legend')
          this.graph.root.classList.add('left-legend')
          break
        case 'right':
          this.graph.root.classList.remove('top-legend')
          this.graph.root.classList.remove('left-legend')
          this.graph.root.classList.add('side-legend')
          break
      }
      this.legendPosition = desired
      this.resize()
    },
    clearErrors: function () {
      this.errors = []
    },
    editGraphClose: function (graph) {
      this.editGraph = false
      this.title = graph.title
      // Don't need to copy items because we don't modify them
      this.legendPosition = graph.legendPosition
      this.graphMinY = graph.graphMinY
      this.graphMaxY = graph.graphMaxY
      this.lines = [...graph.lines]
      this.graphStartDateTime = graph.startDateTime
      this.graphEndDateTime = graph.endDateTime
      // Allow the watch to update needToUpdate
      this.$nextTick(() => {
        if (this.needToUpdate) {
          if (this.subscription == null) {
            this.startGraph()
          } else {
            // NOTE: removing and adding back to back broke the streaming_api
            // because the messages got out of order (add before remove)
            // Code in openc3-cosmos-cmd-tlm-api/app/channels/application_cable/channel.rb
            // fixed the issue to enforce ordering.
            // Clone the items first because removeItems modifies this.items
            let clonedItems = JSON.parse(JSON.stringify(this.items))
            this.removeItems(clonedItems)
            setTimeout(() => {
              this.addItems(clonedItems)
            }, 0)
          }
          this.needToUpdate = false
        }
      })
      this.moveLegend(this.legendPosition)
      this.$emit('edit')
    },
    resize: function () {
      this.graph.setSize(this.getSize('chart'))
      if (this.overview) {
        this.overview.setSize(this.getSize('overview'))
      }
      this.$emit('resize', this.id)
    },
    expandAll: function () {
      this.fullWidth = true
      this.fullHeight = true
      this.resize()
    },
    collapseAll: function () {
      this.fullWidth = false
      this.fullHeight = false
      this.resize()
    },
    expandWidth: function () {
      this.fullWidth = true
      this.resize()
    },
    collapseWidth: function () {
      this.fullWidth = false
      this.resize()
    },
    expandHeight: function () {
      this.fullHeight = true
      this.resize()
    },
    collapseHeight: function () {
      this.fullHeight = false
      this.resize()
    },
    minMaxTransition: function () {
      this.expand = !this.expand
      this.$emit('min-max-graph', this.id)
    },
    setGraphRange: function () {
      let pad = 0.1
      if (
        this.graphMinY ||
        this.graphMinY === 0 ||
        this.graphMaxY ||
        this.graphMaxY === 0
      ) {
        pad = 0
      }
      this.graph.scales.y.range = (u, dataMin, dataMax) => {
        let min = dataMin
        if (this.graphMinY || this.graphMinY === 0) {
          min = this.graphMinY
        }
        let max = dataMax
        if (this.graphMaxY || this.graphMaxY === 0) {
          max = this.graphMaxY
        }
        return uPlot.rangeNum(min, max, pad, true)
      }
    },
    subscribe: function () {
      this.cable
        .createSubscription('StreamingChannel', window.openc3Scope, {
          received: (data) => this.received(data),
          connected: () => {
            this.addItemsToSubscription(this.items)
          },
          disconnected: (data) => {
            // If allowReconnect is true it means we got a disconnect due to connection lost or server disconnect
            // If allowReconnect is false this is a normal server close or client close
            if (data.allowReconnect) {
              this.errors.push({
                type: 'disconnected',
                message: 'OpenC3 backend connection disconnected',
                time: new Date().getTime(),
              })
            }
          },
          rejected: () => {
            this.errors.push({
              type: 'rejected',
              message: 'OpenC3 backend connection rejected',
              time: new Date().getTime(),
            })
          },
        })
        .then((subscription) => {
          this.subscription = subscription
        })
    },
    // throttle(cb, limit) {
    //   let wait = false
    //   return () => {
    //     if (!wait) {
    //       requestAnimationFrame(cb)
    //       wait = true
    //       setTimeout(() => {
    //         wait = false
    //       }, limit)
    //     }
    //   }
    // },
    getSize: function (type) {
      let navDrawerWidth = 0
      const navDrawer = document.getElementById('openc3-nav-drawer')
      if (navDrawer) {
        navDrawerWidth = navDrawer.classList.contains(
          'v-navigation-drawer--active',
        )
          ? navDrawer.clientWidth
          : 0
      }
      let legendWidth = 0
      if (this.legendPosition === 'right' || this.legendPosition === 'left') {
        const legend = document.getElementsByClassName('u-legend')[0]
        legendWidth = legend.clientWidth
      }
      const viewWidth =
        Math.max(document.documentElement.clientWidth, window.innerWidth || 0) -
        navDrawerWidth -
        legendWidth
      const viewHeight = Math.max(
        document.documentElement.clientHeight,
        window.innerHeight || 0,
      )

      const panel = document.getElementsByClassName('v-expansion-panel')[0]
      let height = 100
      if (type === 'overview') {
        // Show overview if we're full height and we're not explicitly hiding it
        if (this.fullHeight && !this.hideOverviewData) {
          this.showOverview = true
        } else {
          this.showOverview = false
        }
      } else {
        // Height of chart is viewportSize - expansion-panel - overview - fudge factor (primarily padding)
        height = viewHeight - panel.clientHeight - height - 250
        if (!this.fullHeight) {
          height = height / 2.0 + 10 // 5px padding top and bottom
        }
      }
      // subtract off some arbitrary padding left and right to make the layout work
      let width = viewWidth - 70
      if (!this.fullWidth) {
        // 6px padding left and right defined in TlmGrapher.vue .item-content
        width = width / 2.0 - 12
      }
      return {
        width: this.width || width,
        height: this.height || height,
      }
    },
    getScales: function () {
      return {
        scales: {
          x: {
            range(u, dataMin, dataMax) {
              if (dataMin == null) return [1566453600, 1566497660]
              return [dataMin, dataMax]
            },
          },
          y: {
            range(u, dataMin, dataMax) {
              if (dataMin == null) return [-100, 100]
              return uPlot.rangeNum(dataMin, dataMax, 0.1, true)
            },
          },
        },
      }
    },
    getAxes: function (type) {
      let strokeColor = 'rgba(255, 255, 255, .1)'
      let axisColor = 'white'
      return {
        axes: [
          {
            stroke: axisColor,
            grid: {
              show: true,
              stroke: strokeColor,
              width: 2,
            },
          },
          {
            size: 80, // This size supports values up to 8 digits plus sign
            stroke: axisColor,
            grid: {
              show: type === 'overview' ? false : true,
              stroke: strokeColor,
              width: 2,
            },
            // Forces the axis values to be formatted correctly
            // especially with really small or large values
            values(u, splits) {
              if (
                splits.some((el) => el >= 10000000) ||
                splits.every((el) => el < 0.01)
              ) {
                splits = splits.map((split) => split.toExponential(3))
              }
              return splits
            },
          },
        ],
      }
    },
    closeEditItem: function (event) {
      this.editItem = false
      if (
        // If we have an end time and anything was changed we basically regraph
        (this.graphEndDateTime !== null && this.selectedItem !== event) ||
        // If we're live graphing we just regraph if the types change
        this.selectedItem.valueType !== event.valueType ||
        this.selectedItem.reduced !== event.reduced ||
        this.selectedItem.reducedType !== event.reducedType
      ) {
        this.changeItem(event)
      }
    },
    changeColor: function (event) {
      let key = this.subscriptionKey(this.selectedItem)
      let index = this.indexes[key]
      this.items[index - 1].color = event
      this.selectedItem.color = event
      this.graph.root.querySelectorAll('.u-marker')[index].style.borderColor =
        event
    },
    changeLimits: function (limits) {
      let key = this.subscriptionKey(this.selectedItem)
      let index = this.indexes[key]
      this.items[index - 1].limits = limits
      this.selectedItem.limits = limits
      this.limitsValues = limits
    },
    linesPlugin: function () {
      return {
        hooks: {
          draw: (u) => {
            const { ctx, bbox } = u
            // These are all in canvas units
            const yMin = u.valToPos(u.scales.y.min, 'y', true)
            const yMax = u.valToPos(u.scales.y.max, 'y', true)
            const redLow = u.valToPos(this.limitsValues[0], 'y', true)
            const yellowLow = u.valToPos(this.limitsValues[1], 'y', true)
            const yellowHigh = u.valToPos(this.limitsValues[2], 'y', true)
            const redHigh = u.valToPos(this.limitsValues[3], 'y', true)
            let height = 0

            // NOTE: These comparisons are tricky because the canvas
            // starts in the upper left with 0,0. Thus it grows downward
            // and to the right with increasing values. The comparisons
            // of scale and limitsValues use graph coordinates but the
            // fillRect calculations use the canvas coordinates.

            // Draw Y axis lines
            this.lines.forEach((line) => {
              if (
                u.scales.y.min <= line.yValue &&
                line.yValue <= u.scales.y.max
              ) {
                ctx.save()
                ctx.beginPath()
                ctx.strokeStyle = line.color
                ctx.lineWidth = 2
                ctx.moveTo(bbox.left, u.valToPos(line.yValue, 'y', true))
                ctx.lineTo(
                  bbox.left + bbox.width,
                  u.valToPos(line.yValue, 'y', true),
                )
                ctx.stroke()
                ctx.restore()
              }
            })

            ctx.save()
            ctx.beginPath()

            // Draw red limits
            ctx.fillStyle = 'rgba(255,0,0,0.15)'
            if (u.scales.y.min < this.limitsValues[0]) {
              let start = redLow < yMax ? yMax : redLow
              ctx.fillRect(bbox.left, redLow, bbox.width, yMin - start)
            }
            if (u.scales.y.max > this.limitsValues[3]) {
              let end = yMin < redHigh ? yMin : redHigh
              ctx.fillRect(bbox.left, yMax, bbox.width, end - yMax)
            }

            // Draw yellow limits
            ctx.fillStyle = 'rgba(255,255,0,0.15)'
            if (
              u.scales.y.min < this.limitsValues[1] && // yellowLow
              u.scales.y.max > this.limitsValues[0] // redLow
            ) {
              let start = yellowLow < yMax ? yMax : yellowLow
              ctx.fillRect(bbox.left, start, bbox.width, redLow - start)
            }
            if (
              u.scales.y.max > this.limitsValues[2] && // yellowHigh
              u.scales.y.min < this.limitsValues[3] // redHigh
            ) {
              let start = yMin < redHigh ? yMin : redHigh
              let end = yMin < yellowHigh ? yMin : yellowHigh
              ctx.fillRect(bbox.left, start, bbox.width, end - start)
            }

            // Draw green limits & operational limits
            ctx.fillStyle = 'rgba(0,255,0,0.15)'
            // If there are no operational limits the interior is all green
            if (this.limitsValues.length === 4) {
              // Determine if we show any green
              if (
                u.scales.y.min < this.limitsValues[2] && // yellowHigh
                u.scales.y.max > this.limitsValues[1] // yellowLow
              ) {
                let start = yellowHigh < yMax ? yMax : yellowHigh
                let end = yMin < yellowLow ? yMin : yellowLow
                ctx.fillRect(bbox.left, start, bbox.width, end - start)
              }
            } else {
              // Operational limits
              const greenLow = u.valToPos(this.limitsValues[4], 'y', true)
              const greenHigh = u.valToPos(this.limitsValues[5], 'y', true)
              if (
                u.scales.y.min < this.limitsValues[4] && // greenLow
                u.scales.y.max > this.limitsValues[1] // yellowLow
              ) {
                let start = greenLow < yMax ? yMax : greenLow
                ctx.fillRect(bbox.left, start, bbox.width, yellowLow - start)
              }
              if (
                u.scales.y.max > this.limitsValues[5] && // greenHigh
                u.scales.y.min < this.limitsValues[2] // yellowHigh
              ) {
                let start = yMin < yellowHigh ? yMin : yellowHigh
                let end = yMin < greenHigh ? yMin : greenHigh
                ctx.fillRect(bbox.left, start, bbox.width, end - start)
              }
              ctx.fillStyle = 'rgba(0,0,255,0.15)'
              let start = greenHigh < yMax ? yMax : greenHigh
              let end = yMin < greenLow ? yMin : greenLow
              ctx.fillRect(bbox.left, start, bbox.width, end - start)
            }
            ctx.stroke()
            ctx.restore()
          },
        },
      }
    },
    changeItem: function (event) {
      // NOTE: removing and adding items back to back broke the streaming_api
      // because the messages got out of order (add before remove)
      // Code in openc3-cosmos-cmd-tlm-api/app/channels/application_cable/channel.rb
      // fixed the issue to enforce ordering.
      this.removeItems([this.selectedItem])
      this.selectedItem.valueType = event.valueType
      this.selectedItem.reduced = event.reduced
      this.selectedItem.reducedType = event.reducedType
      setTimeout(() => {
        this.addItems([this.selectedItem])
      }, 0)
    },
    addItems: function (itemArray, type = 'CONVERTED') {
      itemArray.forEach((item) => {
        item.valueType ||= type // set the default type
        item.color ||= this.colors[this.colorIndex]
        item.limits ||= []

        if (item.limits.length > 0) {
          this.limitsValues = item.limits
        }

        this.colorIndex = (this.colorIndex + 1) % this.colors.length
        this.items.push(item)

        const index = this.data.length
        this.graph.addSeries(this.createSeriesConfig(item), index)

        if (this.overview) {
          this.overview.addSeries(this.createOverviewSeriesConfig(), index)
        }

        this.data.splice(index, 0, Array(this.data[0].length))
        this.indexes[this.subscriptionKey(item)] = index
      })

      this.updateColorIndex(itemArray)
      this.addItemsToSubscription(itemArray)
      this.$emit('resize')
      this.$emit('edit')
    },
    createSeriesConfig: function (item) {
      return {
        spanGaps: true,
        item: item,
        label: this.formatLabel(item),
        stroke: (u, seriesIdx) => this.items[seriesIdx - 1].color,
        width: 2,
        value: (self, rawValue) => {
          if (typeof rawValue === 'string' || isNaN(rawValue)) {
            return 'NaN'
          } else if (rawValue == null) {
            return '--'
          } else if (
            (Math.abs(rawValue) < 0.01 && rawValue !== 0) ||
            Math.abs(rawValue) >= 10000000
          ) {
            return rawValue.toExponential(6)
          } else {
            return rawValue.toFixed(6)
          }
        },
      }
    },
    createOverviewSeriesConfig: function () {
      return {
        spanGaps: true,
        stroke: (u, seriesIdx) => this.items[seriesIdx - 1].color,
      }
    },
    updateColorIndex: function (itemArray) {
      const lastItem = itemArray[itemArray.length - 1]
      if (lastItem) {
        const index = this.colors.indexOf(lastItem.color)
        if (index !== -1) {
          this.colorIndex = (index + 1) % this.colors.length
        }
      }
    },
    addItemsToSubscription: function (itemArray = this.items) {
      let theStartTime = this.startTime
      if (this.graphStartDateTime) {
        theStartTime = this.graphStartDateTime
      }
      if (this.subscription) {
        OpenC3Auth.updateToken(OpenC3Auth.defaultMinValidity).then(
          (refreshed) => {
            if (refreshed) {
              OpenC3Auth.setTokens()
            }
            this.subscription.perform('add', {
              scope: window.openc3Scope,
              token: localStorage.openc3Token,
              items: itemArray.map(this.subscriptionKey),
              start_time: theStartTime,
              end_time: this.graphEndDateTime,
            })
          },
        )
      }
    },
    clearAllData: function () {
      // Clear all data so delete the time data as well
      this.data[0] = []
      this.clearData(this.items)
    },
    clearData: function (itemArray) {
      for (const key of itemArray.map(this.subscriptionKey)) {
        let index = this.indexes[key]
        this.data[index] = Array(this.data[0].length).fill(null)
        this.graph.setData(this.data)
        if (this.overview) {
          this.overview.setData(this.data)
        }
      }
      // data.length of 2 means we only have 1 item
      // so delete all the time (data[0]) to start fresh
      if (this.data.length === 2) {
        this.data[0] = []
        this.graph.setData(this.data)
        if (this.overview) {
          this.overview.setData(this.data)
        }
      }
    },
    removeItems: function (itemArray) {
      this.removeItemsFromSubscription(itemArray)

      for (const key of itemArray.map(this.subscriptionKey)) {
        const index = this.reorderIndexes(key)
        this.items.splice(index - 1, 1)
        this.data.splice(index, 1)
        this.graph.delSeries(index)
        this.graph.setData(this.data)
        if (this.overview) {
          this.overview.delSeries(index)
          this.overview.setData(this.data)
        }
      }
      // data.length of 1 means we've deleted all our items
      // so delete all the time (data[0]) to start fresh
      if (this.data.length === 1) {
        this.data[0] = []
        this.graph.setData(this.data)
        if (this.overview) {
          this.overview.setData(this.data)
        }
      }
      this.$emit('resize')
      this.$emit('edit')
    },
    removeItemsFromSubscription: function (itemArray = this.items) {
      if (this.subscription) {
        this.subscription.perform('remove', {
          scope: window.openc3Scope,
          token: localStorage.openc3Token,
          items: itemArray.map(this.subscriptionKey),
        })
      }
    },
    reorderIndexes: function (key) {
      let index = this.indexes[key]
      delete this.indexes[key]
      for (let i in this.indexes) {
        if (this.indexes[i] > index) {
          this.indexes[i] -= 1
        }
      }
      return index
    },
    received: function (data) {
      this.cable.recordPing()
      // TODO: Shouldn't get errors but should we handle this every time?
      // if (json_data.error) {
      //   console.log(json_data.error)
      //   return
      // }
      for (let i = 0; i < data.length; i++) {
        let time = data[i].__time / 1000000000.0 // Time in seconds
        let length = this.data[0].length
        if (length === 0 || time > this.data[0][length - 1]) {
          // Nominal case - append new data to end
          for (let j = 0; j < this.data.length; j++) {
            this.data[j].push(null)
          }
          this.set_data_at_index(this.data[0].length - 1, time, data[i])
        } else {
          let index = bs(this.data[0], time, this.bs_comparator)
          if (index >= 0) {
            // Found a slot with the exact same time value
            // Handle duplicate time by subtracting a small amount until we find an open slot
            while (index >= 0) {
              time -= 1e-5 // Subtract 10 microseconds
              index = bs(this.data[0], time, this.bs_comparator)
            }
            // Now that we have a unique time, insert at the ideal index
            let ideal_index = -index - 1
            for (let j = 0; j < this.data.length; j++) {
              this.data[j].splice(ideal_index, 0, null)
            }
            // Use the adjusted time but keep the original data
            this.set_data_at_index(ideal_index, time, data[i])
          } else {
            // Insert a new null slot at the ideal index
            let ideal_index = -index - 1
            for (let j = 0; j < this.data.length; j++) {
              this.data[j].splice(ideal_index, 0, null)
            }
            this.set_data_at_index(ideal_index, time, data[i])
          }
        }
      }
      // If we weren't passed a startTime notify grapher of our start
      if (this.startTime == null && this.data[0][0]) {
        let newStartTime = this.data[0][0] * 1000000000
        this.$emit('started', newStartTime)
      }
      this.dataChanged = true
    },
    bs_comparator: function (element, needle) {
      return element - needle
    },
    set_data_at_index: function (index, time, new_data) {
      this.data[0][index] = time
      for (const [key, value] of Object.entries(new_data)) {
        if (key === 'time') {
          continue
        }
        let key_index = this.indexes[key]
        if (key_index) {
          let array = this.data[key_index]
          // NaN and Infinite values are sent as objects with raw attribute set
          // to 'NaN', '-Infinity', or 'Infinity', just set data to null
          if (value?.raw) {
            array[index] = null
          } else if (typeof value === 'string') {
            // Can't graph strings so just set to null
            array[index] = null
            // If it's not already RAW, change the type to RAW
            // NOTE: Some items are RAW strings so they won't ever work
            if (!key.includes('__RAW')) {
              for (let item of this.items) {
                if (this.subscriptionKey(item) === key) {
                  this.selectedItem = item
                  break
                }
              }
              this.changeItem({
                valueType: 'RAW',
                reduced: this.selectedItem.reduced,
                reducedType: this.selectedItem.reducedType,
              })
            }
          } else {
            array[index] = value
          }
        }
      }
    },
    subscriptionKey: function (item) {
      let key = `${item.reduced}__TLM__${item.targetName}__${item.packetName}__${item.itemName}__${item.valueType}`
      if (
        item.reduced === 'REDUCED_MINUTE' ||
        item.reduced === 'REDUCED_HOUR' ||
        item.reduced === 'REDUCED_DAY'
      ) {
        key += `__${item.reducedType}`
      }
      return key
    },
  },
}
</script>

<style>
.v-window-item {
  background-color: var(--color-background-surface-default);
}
/* left right stacked legend */
.uplot.side-legend {
  display: flex;
  width: auto;
}
.uplot.side-legend .u-wrap {
  flex: none;
}
.uplot.side-legend .u-legend {
  text-align: left;
  margin-left: 0;
  width: 220px;
}
.uplot.side-legend .u-legend,
.uplot.side-legend .u-legend tr,
.uplot.side-legend .u-legend th,
.uplot.side-legend .u-legend td {
  display: revert;
}
/* left side we need to order the legend before the plot */
.uplot.left-legend .u-legend {
  order: -1;
}
/* top legend */
.uplot.top-legend {
  display: flex;
  flex-direction: column;
}
.uplot.top-legend .u-legend {
  order: -1;
}
/* This value is large enough to support negative scientific notation
   that we use on the value with rawValue.toExponential(6) */
.u-legend.u-inline .u-series .u-value {
  width: 105px;
}
/* This value is large enough to support our date format: YYYY-MM-DD HH:MM:SS.sss */
.u-legend.u-inline .u-series:first-child .u-value {
  width: 185px;
}
.u-select {
  color: rgba(255, 255, 255, 0.07);
}
</style>
<style scoped>
.active {
  background-color: var(--color-background-surface-selected) !important;
}
</style>
