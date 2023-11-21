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
  <v-dialog v-model="show" width="700">
    <v-card>
      <v-system-bar>
        <v-spacer />
        <span>Overrides</span>
        <v-spacer />
      </v-system-bar>
      <div class="pa-2">
        <v-card-text>
          <v-btn
            @click="clearOverrides"
            color="primary"
            data-test="overrides-dialog-clear-all"
          >
            Clear All Overrides
          </v-btn>

          <v-card-title>
            Overrides
            <v-spacer />
            <v-text-field
              v-model="search"
              label="Search"
              prepend-inner-icon="mdi-magnify"
              outlined
              dense
              single-line
              hide-details
            />
          </v-card-title>
          <v-data-table
            :headers="headers"
            :items="overrides"
            :search="search"
            :footer-props="{
              itemsPerPageOptions: [100],
              showFirstLastPage: true,
              firstIcon: 'mdi-page-first',
              lastIcon: 'mdi-page-last',
              prevIcon: 'mdi-chevron-left',
              nextIcon: 'mdi-chevron-right',
            }"
            calculate-widths
            multi-sort
            dense
          >
            <template v-slot:item.delete="{ item }">
              <v-tooltip bottom>
                <template v-slot:activator="{ on, attrs }">
                  <v-icon
                    @click="deleteOverride(item)"
                    v-bind="attrs"
                    v-on="on"
                  >
                    mdi-delete
                  </v-icon>
                </template>
                <span>Delete Override</span>
              </v-tooltip>
            </template>
          </v-data-table>
        </v-card-text>
      </div>
      <v-card-actions>
        <v-spacer />
        <v-btn
          @click="show = !show"
          color="primary"
          data-test="overrides-dialog-ok"
        >
          Ok
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { OpenC3Api } from '@openc3/tool-common/src/services/openc3-api'

export default {
  components: {},
  props: {
    value: {
      type: Boolean,
      required: true,
    },
  },
  data() {
    return {
      api: null,
      overrides: [],
      search: '',
      headers: [
        { text: 'Target', value: 'target_name' },
        { text: 'Packet', value: 'packet_name' },
        { text: 'Item', value: 'item_name' },
        { text: 'Type', value: 'value_type' },
        { text: 'Value', value: 'value' },
        { text: 'Delete', value: 'delete' },
      ],
    }
  },
  created: function () {
    this.api = new OpenC3Api()
    this.getOverrides()
  },
  computed: {
    show: {
      get() {
        return this.value
      },
      set(value) {
        this.$emit('input', value) // input is the default event when using v-model
      },
    },
  },
  methods: {
    getOverrides: function () {
      this.api.get_overrides().then((result) => {
        this.overrides = result
      })
    },
    clearOverrides: function () {
      const items = [
        ...new Map(
          this.overrides.map((item) => [
            // Create a key based on target, packet, item so we remove duplicates
            `${item.target_name}__${item.packet_name}__${item.item_name}`,
            item,
          ]),
        ).values(),
      ]
      for (let item of items) {
        this.api
          .normalize_tlm(
            item.target_name,
            item.packet_name,
            item.item_name,
            'ALL',
          )
          .then((result) => {
            this.overrides = []
          })
      }
    },
    deleteOverride: function (item) {
      this.api
        .normalize_tlm(
          item.target_name,
          item.packet_name,
          item.item_name,
          item.value_type,
        )
        .then((result) => {
          var index = this.overrides.indexOf(item)
          this.overrides.splice(index, 1)
        })
    },
  },
}
</script>
