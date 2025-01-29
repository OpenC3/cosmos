<!--
# Copyright 2025 OpenC3, Inc.
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
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div class="pa-1" :id="`chart${id}`"></div>
</template>

<script>
import uPlot from 'uplot'
import 'uplot/dist/uPlot.min.css'
import { Cable } from '@openc3/js-common/services'
import GraphWidget from './GraphWidget'

export default {
  data: function () {
    return {
      items: [],
      indexes: {},
      data: [[]],
      cable: new Cable(),
      subscription: null,
      graph: null,
      xAxis: null,
      title: 'Array Plot',
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
  mixins: [GraphWidget],
  created() {
    for (const [index, item] of this.items.entries()) {
      this.data.push([]) // initialize the empty data arrays
      this.indexes[this.subscriptionKey(item)] = index + 1
      item.color = this.colors[this.colorIndex]
      this.colorIndex++
    }

    this.appliedSettings.forEach((setting) => {
      switch (setting[0]) {
        case 'TITLE':
          this.title = setting[1]
          break
        case 'X_AXIS':
          this.xAxis = {
            start: parseFloat(setting[1]),
            step: parseFloat(setting[2]),
          }
          break
      }
    })
  },
  mounted() {
    let chartSeries = []
    this.items.forEach((item) => {
      chartSeries.push({
        label: this.itemName(item),
        stroke: item.color,
        width: 2,
        value: (self, rawValue) => {
          if (typeof rawValue === 'string' || isNaN(rawValue)) {
            return 'NaN'
          } else {
            return rawValue == null ? '--' : rawValue.toFixed(3)
          }
        },
      })
    })

    let chartOpts = {
      title: this.title,
      width: this.size.width,
      height: this.size.height,
      scales: {
        x: {
          time: false,
        },
        y: {
          time: false,
          range: (u, min, max) => [min, max],
        },
      },
      axes: [
        {
          stroke: 'white',
          grid: {
            show: true,
            stroke: 'rgba(255, 255, 255, .1)',
            width: 2,
          },
        },
        {
          stroke: 'white',
          grid: {
            show: true,
            stroke: 'rgba(255, 255, 255, .1)',
            width: 2,
          },
        },
      ],
      series: [{}, ...chartSeries],
    }
    this.graph = new uPlot(
      chartOpts,
      this.data,
      document.getElementById(`chart${this.id}`),
    )
    this.subscribe()
  },
  beforeUnmount: function () {
    this.cable.disconnect()
  },
  computed: {
    dataOnly() {
      return this.data[1] // Ignore the x axis data
    },
  },
  watch: {
    // This is always firing even when the data is the same
    // Is it because we're setting the whole array data[1]?
    dataOnly: function () {
      if (this.graph) {
        this.graph.setData(this.data)
      }
    },
  },
  methods: {
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
    received: function (data) {
      for (let i = 0; i < data.length; i++) {
        for (const [key, value] of Object.entries(data[i])) {
          if (key === '__time') {
            let xaxis = []
            if (this.xAxis) {
              let x = this.xAxis.start
              for (let i = 0; i < this.data[1].length; i++) {
                xaxis.push(x)
                x += this.xAxis.step
              }
            } else {
              xaxis = Array.from({ length: this.data[1].length }, (_, i) => i)
            }
            this.data[0] = xaxis
          }
          let key_index = this.indexes[key]
          if (key_index) {
            this.data[key_index] = value
          }
        }
      }
    },
    addItemsToSubscription: function (itemArray = this.items) {
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
              start_time: null,
              end_time: null,
            })
          },
        )
      }
    },
    itemName: function (item) {
      return `${item.targetName} ${item.packetName} ${item.itemName}`
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
