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
-->

<template>
  <v-card>
    <v-card-title>
      {{ data.length }} Command Packets
      <v-spacer />
      <v-text-field
        v-model="search"
        append-icon="mdi-magnify"
        label="Search"
        single-line
        hide-details
      />
    </v-card-title>
    <v-data-table
      :headers="headers"
      :items="data"
      :search="search"
      :items-per-page="10"
      :footer-props="{ itemsPerPageOptions: [10, 20, 50, 100] }"
      sort-by="target_name"
      @current-items="currentItems"
      calculate-widths
      multi-sort
      data-test="cmd-packets-table"
    >
      <template v-slot:item.view_raw="{ item }">
        <v-btn
          block
          color="primary"
          :disabled="item.count < 1"
          @click="openViewRaw(item.target_name, item.packet_name)"
        >
          View Raw
        </v-btn>
      </template>
      <template v-slot:item.view_in_cmd_sender="{ item }">
        <span v-if="item.target_name === 'UNKNOWN'">N/A</span>
        <v-btn
          v-else
          block
          color="primary"
          @click="openCmdSender(item.target_name, item.packet_name)"
        >
          View In Command Sender
          <v-icon right> mdi-open-in-new </v-icon>
        </v-btn>
      </template>
    </v-data-table>
    <raw-dialog
      type="Command"
      :target-name="target_name"
      :packet-name="packet_name"
      :visible="viewRaw"
      @display="rawDisplayCallback"
    />
  </v-card>
</template>

<script>
import Updater from './Updater'
import RawDialog from './RawDialog'

export default {
  components: {
    RawDialog,
  },
  mixins: [Updater],
  props: {
    tabId: Number,
    curTab: Number,
  },
  data() {
    return {
      search: '',
      data: [],
      headers: [
        { text: 'Target Name', value: 'target_name' },
        { text: 'Packet Name', value: 'packet_name' },
        { text: 'Packet Count', value: 'count' },
        { text: 'View Raw', value: 'view_raw' },
        { text: 'View In Command Sender', value: 'view_in_cmd_sender' },
      ],
      viewRaw: false,
      target_name: null,
      packet_name: null,
      visible: null,
    }
  },
  created() {
    this.api.get_target_list().then((targets) => {
      targets.map((target) => {
        this.api.get_all_command_names(target).then((names) => {
          this.data = this.data.concat(
            names.map((packet) => {
              return { target_name: target, packet_name: packet, count: 0 }
            })
          )
        })
      })
    })
  },
  methods: {
    // This method is hooked to the RawDialog as a callback to
    // keep track of whether the dialog is displayed
    rawDisplayCallback(bool) {
      this.viewRaw = bool
    },
    openViewRaw(target_name, packet_name) {
      this.target_name = target_name
      this.packet_name = packet_name
      this.viewRaw = true
    },
    openCmdSender(target_name, packet_name) {
      let routeData = this.$router.resolve({
        name: 'CommandSender',
        params: {
          target: target_name,
          packet: packet_name,
        },
      })
      window.open(`/tools/cmdsender/${target_name}/${packet_name}`, '_blank')
    },
    currentItems(event) {
      this.visible = event.map((i) => {
        return [i.target_name, i.packet_name]
      })
    },
    update() {
      if (this.tabId != this.curTab) return
      if (this.currentItems === null) return
      this.api.get_cmd_cnts(this.visible).then((counts) => {
        for (let i = 0; i < counts.length; i++) {
          let index = this.data.findIndex(
            (item) =>
              item.target_name === this.visible[i][0] &&
              item.packet_name === this.visible[i][1]
          )
          this.data[index].count = counts[i]
        }
      })
    },
  },
}
</script>
