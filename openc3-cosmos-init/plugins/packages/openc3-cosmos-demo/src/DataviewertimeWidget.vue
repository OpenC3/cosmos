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
  <v-container>
    <v-row dense>
      <v-col>Current Time:</v-col>
      <v-col>
        <v-text-field
          solo
          dense
          readonly
          single-line
          hide-no-data
          hide-details
          placeholder="Time"
          :value="date" /></v-col
    ></v-row>
    <v-row dense>
      <v-col>UTC Time:</v-col>
      <v-col>
        <v-text-field
          solo
          dense
          readonly
          single-line
          hide-no-data
          hide-details
          placeholder="Time"
          :value="utc" /></v-col
    ></v-row>
    <v-row dense>
      <v-col>Stream Time (UTC):</v-col>
      <v-col>
        <v-text-field
          solo
          dense
          readonly
          single-line
          hide-no-data
          hide-details
          placeholder="Time"
          :value="streamTime" /></v-col
    ></v-row>
    <v-row dense v-if="hasDecom">
      <v-col>Packet Time:</v-col>
      <v-col>
        <v-text-field
          solo
          dense
          readonly
          single-line
          hide-no-data
          hide-details
          placeholder="Time"
          :value="packetTime" /></v-col
    ></v-row>
    <v-row dense v-if="hasDecom">
      <v-col>Received Time:</v-col>
      <v-col>
        <v-text-field
          solo
          dense
          readonly
          single-line
          hide-no-data
          hide-details
          placeholder="Time"
          :value="receivedTime" /></v-col
    ></v-row>
  </v-container>
</template>

<script>
import Component from '@openc3/tool-common/src/components/dataviewer/Component'

export default {
  mixins: [Component],
  data: function () {
    return {
      packetTime: null,
      receivedTime: null,
      currentTime: null,
      date: new Date(),
    }
  },
  computed: {
    utc: function () {
      return this.date.toUTCString()
    },
  },
  watch: {
    lastReceived: function (data) {
      data.forEach((packet) => {
        // This only works with DECOM packets
        if ('buffer' in packet === false) {
          this.packetTime = packet['PACKET_TIMEFORMATTED']
          this.receivedTime = packet['RECEIVED_TIMEFORMATTED']
        }
        this.streamTime = new Date(packet.__time / 1000000).toISOString()
        this.date = new Date()
      })
    },
  },
}
</script>
