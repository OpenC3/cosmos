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
  <v-dialog v-model="show" width="600">
    <v-toolbar height="24">
      <v-spacer />
      <span>TlmGrapher Settings</span>
      <v-spacer />
    </v-toolbar>
    <v-card class="pa-3">
      <v-card-text>
        <div v-for="item in settings" :key="item.title">
          <v-row class="my-5">
            <v-text-field
              v-model.number="item.value"
              hide-details="auto"
              type="number"
              :rules="item.rules"
              :label="item.title"
            />
          </v-row>
        </div>
        <v-row>
          <span class="text-red">
            Increasing these values may cause issues
          </span>
        </v-row>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
export default {
  props: {
    settings: {
      type: Object,
      required: true,
    },
  },
  data() {
    return { show: false }
  },
}
</script>
