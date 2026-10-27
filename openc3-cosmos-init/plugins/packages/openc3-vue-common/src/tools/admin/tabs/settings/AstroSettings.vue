<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-card>
    <v-card-title>Astro Settings</v-card-title>
    <v-alert v-model="errorLoading" type="error" closable density="compact">
      Error loading previous configuration due to {{ errorText }}
    </v-alert>
    <v-alert v-model="errorSaving" type="error" closable density="compact">
      Error saving due to {{ errorText }}
    </v-alert>
    <v-alert v-model="successSaving" type="success" closable density="compact">
      Saved! (Refresh the page to see changes)
    </v-alert>
    <v-card-text class="pb-0">
      <v-switch
        v-model="hideClock"
        label="Hide Astro Clock"
        color="primary"
        :disabled="settingsLoading"
      />
      <v-switch
        v-model="showItemClock"
        label="Show Telemetry Item Clock"
        color="primary"
        :disabled="settingsLoading"
        data-test="show-item-clock"
      />
      <div v-if="showItemClock">
        <div class="text-body-2">
          Displays a second clock driven by a telemetry item such as
          PACKET_TIMEFORMATTED or PACKET_TIMESECONDS. Formatted times are
          treated as UTC and numeric values as seconds since the Unix epoch.
        </div>
        <!-- Wait for the setting to load so the initial names are set
        before the chooser defaults to the first target -->
        <target-packet-item-chooser
          v-if="!settingsLoading"
          choose-item
          :initial-target-name="itemClock.targetName"
          :initial-packet-name="itemClock.packetName"
          :initial-item-name="itemClock.itemName"
          @on-set="itemSelected"
        />
        <v-switch
          v-model="showItemClockTitle"
          label="Show Item Clock Title"
          color="primary"
          data-test="show-item-clock-title"
        />
        <v-text-field
          v-if="showItemClockTitle"
          v-model="itemClockTitle"
          label="Item Clock Title"
          :placeholder="defaultItemClockTitle"
          hint="Defaults to the target and packet name. Titles up to 12 characters fit without widening the clock."
          persistent-hint
          persistent-placeholder
          clearable
          data-test="item-clock-title-input"
        />
      </div>
    </v-card-text>
    <v-card-actions>
      <v-btn
        color="success"
        variant="text"
        data-test="save-astro-settings"
        :disabled="showItemClock && !itemClockValid"
        @click="save"
      >
        Save
      </v-btn>
    </v-card-actions>
  </v-card>
</template>

<script>
import { TargetPacketItemChooser } from '@/components'
import Settings from './settings.js'

const settingName = 'astro'
export default {
  components: {
    TargetPacketItemChooser,
  },
  mixins: [Settings],
  data() {
    return {
      hideClock: false,
      showItemClock: false,
      showItemClockTitle: true,
      itemClockTitle: '',
      itemClock: {
        targetName: null,
        packetName: null,
        itemName: null,
      },
    }
  },
  computed: {
    // Update AppNav itemClockLabel when changing this
    defaultItemClockTitle: function () {
      if (!this.itemClock.targetName || !this.itemClock.packetName) {
        return ''
      }
      return `${this.itemClock.targetName} ${this.itemClock.packetName}`
    },
    itemClockValid: function () {
      return (
        !!this.itemClock.targetName &&
        !!this.itemClock.packetName &&
        !!this.itemClock.itemName
      )
    },
  },
  created() {
    this.loadSetting(settingName)
  },
  methods: {
    itemSelected(event) {
      this.itemClock = {
        targetName: event.targetName,
        packetName: event.packetName,
        itemName: event.itemName,
      }
    },
    save() {
      if (this.showItemClock && !this.itemClockValid) {
        return
      }
      this.saveSetting(
        settingName,
        // Hashify the setting to allow for future settings
        // Update AppNav when adding new settings
        JSON.stringify({
          hideClock: this.hideClock,
          showItemClock: this.showItemClock,
          showItemClockTitle: this.showItemClockTitle,
          // Blank means use the target and packet name
          itemClockTitle: this.itemClockTitle?.trim() || '',
          itemClock: this.itemClock,
        }),
      )
    },
    parseSetting: function (response) {
      if (response) {
        let parsed = JSON.parse(response)
        this.hideClock = parsed.hideClock
        this.showItemClock = !!parsed.showItemClock
        // Settings saved before the title existed default to showing it
        this.showItemClockTitle = parsed.showItemClockTitle ?? true
        this.itemClockTitle = parsed.itemClockTitle || ''
        if (parsed.itemClock) {
          this.itemClock = parsed.itemClock
        }
      }
    },
  },
}
</script>
