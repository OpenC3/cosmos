<!--
# Copyright 2024 OpenC3, Inc.
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

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <!-- Edit Item dialog -->
  <v-dialog v-model="show" @keydown.esc="$emit('cancel')" max-width="700">
    <v-toolbar height="24">
      <v-spacer />
      <span> Edit Graph </span>
      <v-spacer />
    </v-toolbar>
    <v-card class="pa-3">
      <v-tabs v-model="tab" class="ml-3">
        <v-tab value="0"> Settings </v-tab>
        <v-tab value="1"> Scale / Lines </v-tab>
        <v-tab value="2"> Items </v-tab>
      </v-tabs>
      <v-tabs-window v-model="tab">
        <v-tabs-window-item value="0" eager>
          <div class="edit-box">
            <v-row>
              <v-col>
                <v-card-text class="pa-0">
                  <v-text-field
                    class="pb-2"
                    label="Title"
                    v-model="graph.title"
                    hide-details
                  />
                </v-card-text>
              </v-col>
              <v-col>
                <v-select
                  label="Legend Position"
                  hide-details
                  :items="legendPositions"
                  v-model="graph.legendPosition"
                  style="max-width: 280px"
                />
              </v-col>
            </v-row>
          </div>
          <div class="edit-box">
            <v-card-text class="pa-0">
              Select a start date/time for the graph. Leave blank for start now.
            </v-card-text>
            <v-row>
              <v-col>
                <v-text-field
                  label="Start Date"
                  :name="`date${Date.now()}`"
                  :rules="[rules.date]"
                  v-model="startDate"
                  type="date"
                />
              </v-col>
              <v-col>
                <!-- We set the :name attribute to be unique to avoid auto-completion -->
                <v-text-field
                  label="Start Time"
                  :name="`time${Date.now()}`"
                  :rules="[rules.time]"
                  v-model="startTime"
                  type="time"
                  step="1"
                />
              </v-col>
            </v-row>
            <v-card-text class="pa-0">
              Select a end date/time for the graph. Leave blank for continuous
              real-time graphing.
            </v-card-text>
            <v-row>
              <v-col>
                <v-text-field
                  label="End Date"
                  :name="`date${Date.now()}`"
                  :rules="[rules.date]"
                  v-model="endDate"
                  type="date"
                />
              </v-col>
              <v-col>
                <!-- We set the :name attribute to be unique to avoid auto-completion -->
                <v-text-field
                  label="End Time"
                  :name="`time${Date.now()}`"
                  :rules="[rules.time]"
                  v-model="endTime"
                  type="time"
                  step="1"
                />
              </v-col>
            </v-row>
          </div>
        </v-tabs-window-item>
        <v-tabs-window-item value="1" eager>
          <div class="edit-box">
            <v-card-text class="pa-0">
              Set a min or max Y value to override automatic scaling
            </v-card-text>
            <v-row dense>
              <v-col class="px-2">
                <v-text-field
                  hide-details
                  label="Min Y Axis (Optional)"
                  v-model="graph.graphMinY"
                  type="number"
                />
              </v-col>
              <v-col class="px-2">
                <v-text-field
                  hide-details
                  label="Max Y Axis (Optional)"
                  v-model="graph.graphMaxY"
                  type="number"
                />
              </v-col>
            </v-row>
          </div>
          <div class="edit-box">
            <v-list density="compact">
              <v-list-item>
                <span style="padding-top: 5px">
                  Add horizontal lines to the graph
                </span>
                <v-spacer />
                <v-btn @click="addLine()"> New Line </v-btn>
              </v-list-item>
              <v-list-item
                v-for="(item, i) in graph.lines"
                :key="i"
                :value="item"
                color="primary"
              >
                <v-row>
                  <v-col>
                    <v-text-field label="Y Value" v-model="item.yValue" />
                  </v-col>
                  <v-col>
                    <v-select
                      label="Color"
                      hide-details
                      :items="colors"
                      v-model="item.color"
                    />
                  </v-col>
                  <v-col>
                    <v-tooltip text="Remove" location="bottom">
                      <template v-slot:activator="{ props }">
                        <v-icon
                          v-bind="props"
                          style="padding: 30px"
                          @click="removeLine(item)"
                          >mdi-delete</v-icon
                        >
                      </template>
                    </v-tooltip>
                  </v-col>
                </v-row>
              </v-list-item>
            </v-list>
          </div>
        </v-tabs-window-item>
        <v-tabs-window-item value="2" eager>
          <v-data-table
            item-key="itemId"
            class="elevation-1 my-2"
            data-test="edit-graph-items"
            :headers="itemHeaders"
            :items="editItems"
            :items-per-page="5"
            :footer-props="{
              'items-per-page-options': [5],
            }"
          >
            <template v-slot:item.actions="{ item }">
              <v-tooltip text="Remove" location="bottom">
                <template v-slot:activator="{ props }">
                  <v-icon v-bind="props" @click="$emit('remove', item)">
                    mdi-delete
                  </v-icon>
                </template>
              </v-tooltip>
            </template>
            <template v-slot:no-data>
              <span> Currently no items on this graph </span>
            </template>
          </v-data-table>
        </v-tabs-window-item>
      </v-tabs-window>
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn variant="outlined" @click="$emit('cancel')"> Cancel </v-btn>
        <v-btn variant="flat" @click="closeOk"> Ok </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { TimeFilters } from '@/util'
import { isValid, parse, toDate } from 'date-fns'
export default {
  props: {
    modelValue: Boolean, // modelValue is the default prop when using v-model
    title: {
      type: String,
      required: true,
    },
    legendPosition: {
      type: String,
      required: true,
    },
    items: {
      type: Array,
      required: true,
    },
    graphMinY: {
      type: Number,
    },
    graphMaxY: {
      type: Number,
    },
    lines: {
      type: Array,
      required: true,
    },
    colors: {
      type: Array,
      required: true,
    },
    startDateTime: {
      type: Number,
    },
    endDateTime: {
      type: Number,
    },
    timeZone: {
      type: String,
      required: true,
    },
  },
  mixins: [TimeFilters],
  data: function () {
    return {
      tab: 0,
      graph: {},
      legendPositions: ['top', 'bottom', 'left', 'right'],
      startDate: null,
      startTime: null,
      endDate: null,
      endTime: null,
      lineHeaders: [
        { title: 'Y Value', value: 'yValue' },
        { title: 'Color', value: 'color' },
        { title: 'Actions', value: 'actions', sortable: false },
      ],
      itemHeaders: [
        { title: 'Target Name', value: 'targetName' },
        { title: 'Packet Name', value: 'packetName' },
        { title: 'Item Name', value: 'itemName' },
        { title: 'Actions', value: 'actions', sortable: false },
      ],
      rules: {
        date: (value) => {
          if (!value) return true
          try {
            return (
              isValid(parse(value, 'yyyy-MM-dd', new Date())) ||
              'Invalid date (YYYY-MM-DD)'
            )
          } catch (e) {
            return 'Invalid date (YYYY-MM-DD)'
          }
        },
        time: (value) => {
          if (!value) return true
          try {
            return (
              isValid(parse(value, 'HH:mm:ss', new Date())) ||
              'Invalid time (HH:MM:SS)'
            )
          } catch (e) {
            return 'Invalid time (HH:MM:SS)'
          }
        },
      },
    }
  },
  computed: {
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value) // update is the default event when using v-model
      },
    },
    editItems: function () {
      if (!this.items) return []
      let itemId = 0
      return this.items.map((item) => {
        itemId += 1
        return { ...item, itemId }
      })
    },
  },
  created() {
    this.graph = {
      title: this.title,
      legendPosition: this.legendPosition,
      items: this.items,
      graphMinY: this.graphMinY,
      graphMaxY: this.graphMaxY,
      lines: [...this.lines],
    }
    // Set the date and time if they pass a dateTime or set a default
    // Start needs a default because if the timeZone is UTC the time will still be local time
    if (this.startDateTime) {
      // Use the passed dateTime as is
      let date = toDate(this.startDateTime / 1_000_000)
      this.startDate = this.formatDate(date, this.timeZone)
      this.startTime = this.formatTimeHMS(date, this.timeZone)
    } else {
      // Create a new date 1 hr in the past as a default
      let date = new Date() - 3600000
      this.startDate = this.formatDate(date, this.timeZone)
      this.startTime = this.formatTimeHMS(date, this.timeZone)
    }
    // Only set end date / time if it is explicitly passed
    if (this.endDateTime) {
      let date = toDate(this.endDateTime / 1_000_000)
      this.endDate = this.formatDate(date, this.timeZone)
      this.endTime = this.formatTimeHMS(date, this.timeZone)
    }
  },
  methods: {
    closeOk() {
      if (!!this.startDate && !!this.startTime) {
        this.graph.startDateTime = this.startDate + ' ' + this.startTime
      } else {
        this.graph.startDateTime = null
      }
      if (!!this.endDate && !!this.endTime) {
        this.graph.endDateTime = this.endDate + ' ' + this.endTime
      } else {
        this.graph.endDateTime = null
      }
      this.$emit('ok', this.graph)
    },
    addLine() {
      this.graph.lines.push({ yValue: 0, color: 'white' })
    },
    removeLine(dline) {
      let i = this.graph.lines.indexOf(dline)
      this.graph.lines.splice(i, 1)
    },
  },
}
</script>

<style>
.edit-box {
  color: hsla(0, 0%, 100%, 0.7);
  background-color: var(--color-background-surface-default);
  padding: 10px;
  margin-top: 10px;
}
/* For the Y Axis item editor within the Edit Dialog */
.v-small-dialog__content {
  background-color: var(--color-background-surface-selected);
  padding: 5px 5px;
}
</style>
