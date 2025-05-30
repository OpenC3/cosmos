<!--
# Copyright 2023 OpenC3, Inc.
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
  <!-- Dialog for creating new screen -->
  <v-dialog v-model="show" width="600">
    <v-card>
      <v-toolbar height="24">
        <v-spacer />
        <span>Create New Screen</span>
        <v-spacer />
        <v-btn
          icon="mdi-close-box"
          variant="text"
          density="compact"
          data-test="new-screen-close-icon"
          @click="show = false"
        />
      </v-toolbar>
      <v-card-text>
        <v-alert
          v-model="duplicateScreenAlert"
          type="error"
          closable
          density="compact"
        >
          Screen {{ newScreenName.toUpperCase() }} already exists!
        </v-alert>
        <v-row class="pt-3">
          <v-col> Screens must belong to a target. Select a target: </v-col>
        </v-row>
        <v-row dense>
          <v-col>
            <v-select
              v-model="selectedTarget"
              label="Select Target"
              :items="targets"
              item-title="label"
              item-value="value"
              @update:model-value="targetSelect"
            />
          </v-col>
        </v-row>

        <v-row dense>
          <v-col>
            Screens can be auto-generated based on an existing Packet. This
            creates a LABELVALUE line for every item in the packet. The screen
            can then be edited and customized.
          </v-col>
        </v-row>
        <v-row dense>
          <v-col> Leave this blank to start with a blank screen. </v-col>
        </v-row>
        <v-row dense>
          <v-col>
            <v-autocomplete
              v-model="selectedPacketName"
              label="New screen packet"
              hide-details
              density="compact"
              :items="packetNames"
              item-title="label"
              item-value="value"
              data-test="new-screen-packet"
            />
          </v-col>
        </v-row>
        <v-row dense>
          <v-col>
            <v-text-field
              v-model="newScreenName"
              flat
              autofocus
              clearable
              label="Screen Name (without .txt)"
              :rules="[rules.required]"
              data-test="new-screen-name"
              @keyup="newScreenKeyup($event)"
            />
            <div v-if="newScreenSaving" class="pl-2">
              <v-progress-circular indeterminate color="primary" />
            </div>
          </v-col>
        </v-row>
      </v-card-text>
      <v-divider />
      <v-card-actions class="px-2">
        <v-spacer />
        <v-btn variant="outlined" @click="show = false"> Cancel </v-btn>
        <v-btn variant="flat" @click="saveNewScreen"> Save </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>

<script>
import { OpenC3Api } from '@openc3/js-common/services'

export default {
  props: {
    modelValue: Boolean,
    target: {
      type: String,
    },
    screens: {
      type: Object,
    },
  },
  data() {
    return {
      api: null,
      targets: [],
      newScreenSaving: false,
      newScreenName: '',
      duplicateScreenAlert: false,
      packetNames: [],
      selectedTarget: '',
      selectedPacketName: '',
      rules: {
        required: (value) => !!value || 'Required.',
      },
    }
  },
  computed: {
    show: {
      get() {
        return this.modelValue
      },
      set(value) {
        this.$emit('update:modelValue', value)
      },
    },
    existingScreens() {
      if (this.screens[this.selectedTarget]) {
        return this.screens[this.selectedTarget].join(', ')
      } else {
        return 'None'
      }
    },
  },
  watch: {
    selectedPacketName: function (value) {
      if (value === 'BLANK') {
        this.newScreenName = ''
        this.duplicateScreenAlert = false
      } else {
        this.newScreenName = value.toLowerCase()
        if (
          this.screens[this.selectedTarget] &&
          this.screens[this.selectedTarget].indexOf(
            this.newScreenName.toUpperCase(),
          ) !== -1
        ) {
          this.duplicateScreenAlert = true
        } else {
          this.duplicateScreenAlert = false
        }
      }
    },
    newScreenName: function (value) {
      if (
        this.screens[this.selectedTarget] &&
        this.screens[this.selectedTarget].indexOf(value.toUpperCase()) !== -1
      ) {
        this.duplicateScreenAlert = true
      } else {
        this.duplicateScreenAlert = false
      }
    },
  },
  created() {
    this.api = new OpenC3Api()
    this.duplicateScreenAlert = false
    this.newScreenSaving = false
    this.selectedTarget = this.target
    this.api
      .get_target_names({ params: { scope: window.openc3Scope } })
      .then((targets) => {
        this.targets = targets.filter((item) => item !== 'UNKNOWN')
      })
    this.targetSelect(this.selectedTarget)
  },
  methods: {
    targetSelect(target) {
      this.selectedTarget = target
      this.api.get_all_tlm_names(this.selectedTarget).then((names) => {
        this.packetNames = names.map((name) => {
          return {
            label: name,
            value: name,
          }
        })
        this.packetNames.unshift({
          label: '[ BLANK ]',
          value: 'BLANK',
        })
      })
    },
    newScreenKeyup(event) {
      if (event.key === 'Enter') {
        this.saveNewScreen()
      }
    },
    saveNewScreen() {
      if (this.duplicateScreenAlert || this.newScreenName === '') {
        return
      }
      this.newScreenSaving = true
      this.$emit(
        'success',
        this.newScreenName.toUpperCase(),
        this.selectedPacketName,
        this.selectedTarget,
      )
    },
  },
}
</script>

<style scoped>
.v-alert {
  margin-bottom: 0px;
}
</style>
