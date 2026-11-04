<!--
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <v-dialog v-model="show" scrollable width="900">
    <v-card class="discover-dialog">
      <v-card-title class="d-flex align-center">
        Discover Hardware
        <v-spacer />
        <v-btn
          icon="mdi-close"
          variant="text"
          size="small"
          aria-label="Close"
          @click="show = false"
        />
      </v-card-title>
      <div class="px-6 flex-shrink-0">
        <p class="text-body-2 text-medium-emphasis mb-3">
          Scans the computers connected to COSMOS through openc3-app for USB,
          serial, network and Bluetooth devices, and proposes plugins to install
          for them.
        </p>
        <v-row dense align="center">
          <v-col cols="12" sm="6">
            <v-select
              v-model="bridge"
              :items="bridgeItems"
              item-title="text"
              item-value="value"
              label="Bridge"
              density="comfortable"
              variant="outlined"
              hide-details
              :disabled="scanning"
              data-test="discover-bridge"
            />
          </v-col>
          <v-col cols="12" sm="6">
            <v-btn
              prepend-icon="mdi-radar"
              variant="flat"
              :loading="scanning"
              :disabled="bridgeItems.length === 0"
              data-test="discover-scan"
              @click="scan"
            >
              {{ result ? 'Scan Again' : 'Scan' }}
            </v-btn>
          </v-col>
        </v-row>
      </div>
      <v-card-text class="discover-body pt-3">
        <v-alert
          v-if="bridgeItems.length === 0 && bridgesLoaded"
          type="info"
          variant="tonal"
          data-test="discover-no-bridge"
        >
          No bridge is paired with openc3-app. Pair a computer with COSMOS from
          the Bridges tab to discover its hardware.
        </v-alert>
        <div v-if="scanning" class="text-center py-8">
          <v-progress-circular indeterminate class="mb-3" />
          <div class="text-body-2">Scanning for hardware...</div>
          <div class="text-caption text-medium-emphasis">
            This takes about 10 seconds
          </div>
        </div>
        <v-alert
          v-if="error"
          type="error"
          variant="tonal"
          class="mb-3"
          data-test="discover-error"
        >
          {{ error }}
        </v-alert>
        <template v-if="result && !scanning">
          <v-alert
            v-for="(scanError, index) in result.errors"
            :key="index"
            type="warning"
            variant="tonal"
            density="compact"
            class="mb-2"
            data-test="discover-scan-error"
          >
            {{ errorText(scanError) }}
          </v-alert>
          <div
            v-if="recognized.length === 0"
            class="text-body-1 py-4"
            data-test="discover-none"
          >
            No plugins match the hardware found.
            <div
              v-if="!result.store_matchers"
              class="text-body-2 text-medium-emphasis mt-1"
            >
              The OpenC3 Store doesn't provide hardware discovery data yet, so
              only the plugins installed in COSMOS were checked.
            </div>
          </div>
          <v-card
            v-for="device in recognized"
            :key="deviceKey(device)"
            variant="outlined"
            class="mb-3"
            data-test="discover-device"
          >
            <v-card-item>
              <template #prepend>
                <v-icon :icon="kind(device).icon" />
              </template>
              <v-card-title class="text-subtitle-1">
                {{ device.text }}
              </v-card-title>
              <v-card-subtitle>
                {{ kind(device).text }}
                <span v-if="multipleBridges"> on {{ device.bridge }}</span>
              </v-card-subtitle>
              <template v-if="device.claimed_by" #append>
                <v-chip size="small" data-test="discover-claimed">
                  In use by {{ device.claimed_by }}
                </v-chip>
              </template>
            </v-card-item>
            <v-list density="compact" class="py-0">
              <v-list-item
                v-for="(candidate, index) in device.candidates"
                :key="index"
                data-test="discover-candidate"
              >
                <template #prepend>
                  <v-avatar rounded="sm" size="40" class="mr-2">
                    <v-img
                      v-if="candidate.image_url"
                      :src="candidate.image_url"
                      cover
                    />
                    <v-icon v-else icon="mdi-puzzle" />
                  </v-avatar>
                </template>
                <v-list-item-title>{{ candidate.title }}</v-list-item-title>
                <v-list-item-subtitle>
                  {{ candidateSubtitle(candidate) }}
                </v-list-item-subtitle>
                <template #append>
                  <v-chip
                    v-if="!candidate.entitled"
                    size="small"
                    prepend-icon="mdi-lock"
                    class="mr-2"
                  >
                    Requires license
                  </v-chip>
                  <v-btn
                    variant="tonal"
                    size="small"
                    :disabled="!candidate.entitled"
                    data-test="discover-install"
                    @click="install(candidate)"
                  >
                    {{ candidate.installed ? 'Install Another' : 'Install' }}
                  </v-btn>
                </template>
              </v-list-item>
            </v-list>
          </v-card>
          <!-- Devices no plugin recognizes, which shows gaps in what plugins support -->
          <template v-if="unrecognized.length > 0">
            <v-btn
              :prepend-icon="
                showOther ? 'mdi-chevron-down' : 'mdi-chevron-right'
              "
              variant="text"
              data-test="discover-other"
              @click="showOther = !showOther"
            >
              Other devices ({{ unrecognized.length }})
            </v-btn>
            <v-list v-if="showOther" density="compact">
              <v-list-item
                v-for="device in unrecognized"
                :key="deviceKey(device)"
                :prepend-icon="kind(device).icon"
                :title="device.text"
                :subtitle="
                  kind(device).text +
                  (multipleBridges ? ` on ${device.bridge}` : '')
                "
              />
            </v-list>
          </template>
        </template>
      </v-card-text>
    </v-card>
  </v-dialog>
</template>

<script>
import { Api } from '@openc3/js-common/services'

// How each discovery class's devices are shown
const KINDS = {
  'openc3.discovery.serial_discovery': {
    text: 'Serial port',
    icon: 'mdi-serial-port',
  },
  'openc3.discovery.hid_discovery': {
    text: 'USB HID device',
    icon: 'mdi-gamepad-variant',
  },
  'openc3.discovery.usb_discovery': { text: 'USB device', icon: 'mdi-usb' },
  'openc3.discovery.zeroconf_discovery': {
    text: 'Network device',
    icon: 'mdi-lan',
  },
  'openc3.discovery.ssdp_discovery': {
    text: 'UPnP network device',
    icon: 'mdi-access-point-network',
  },
  'openc3.discovery.neighbor_discovery': {
    text: 'Network host',
    icon: 'mdi-lan-connect',
  },
  'openc3.discovery.bluetooth_discovery': {
    text: 'Bluetooth device',
    icon: 'mdi-bluetooth',
  },
}

export default {
  props: {
    modelValue: Boolean,
  },
  emits: ['update:modelValue', 'install'],
  data() {
    return {
      bridges: [],
      bridgesLoaded: false,
      bridge: 'ALL',
      scanning: false,
      result: null,
      error: null,
      showOther: false,
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
    // Only bridges paired with openc3-app can scan their host
    bridgeItems() {
      const items = this.bridges.map((name) => ({ value: name, text: name }))
      if (items.length > 1) {
        items.unshift({ value: 'ALL', text: 'All bridges' })
      }
      return items
    },
    multipleBridges() {
      return this.bridges.length > 1
    },
    recognized() {
      return (this.result?.devices || []).filter(
        (device) => device.candidates.length > 0,
      )
    },
    unrecognized() {
      return (this.result?.devices || []).filter(
        (device) => device.candidates.length === 0,
      )
    },
  },
  async created() {
    await this.loadBridges()
    if (this.bridgeItems.length > 0) {
      this.scan()
    }
  },
  methods: {
    async loadBridges() {
      try {
        const response = await Api.get('/openc3-api/bridges/ALL', {
          headers: { Accept: 'application/json' },
        })
        this.bridges = Object.values(response.data || {})
          .filter((bridge) => bridge.app_public_key)
          .map((bridge) => bridge.name)
          .sort()
      } catch (error) {
        this.bridges = []
      }
      this.bridge = this.bridgeItems[0]?.value || 'ALL'
      this.bridgesLoaded = true
    },
    async scan() {
      this.scanning = true
      this.error = null
      try {
        const response = await Api.post('/openc3-api/discovery/scan', {
          data: { bridge: this.bridge },
          headers: { 'Ignore-Errors': '500,503' },
        })
        this.result = response.data
      } catch (error) {
        this.result = null
        this.error =
          error.response?.data?.message || error.message || String(error)
      } finally {
        this.scanning = false
      }
    },
    install(candidate) {
      this.$emit('install', candidate)
      this.show = false
    },
    kind(device) {
      return KINDS[device.class] || { text: device.class, icon: 'mdi-chip' }
    },
    deviceKey(device) {
      return `${device.bridge}/${device.class}/${device.value}`
    },
    candidateSubtitle(candidate) {
      const parts = []
      if (candidate.match_title && candidate.match_title !== candidate.title) {
        parts.push(candidate.match_title)
      }
      parts.push(
        candidate.source === 'store' ? 'OpenC3 Store' : 'Installed in COSMOS',
      )
      return parts.join(' · ')
    },
    errorText(scanError) {
      const where = scanError.class
        ? `${this.kind({ class: scanError.class }).text}s on ${scanError.bridge}`
        : scanError.bridge
      return `${where}: ${scanError.message}`
    },
  },
}
</script>

<style scoped>
/* Fit the window and scroll the results, like PluginDialog */
.discover-dialog {
  display: flex;
  flex-direction: column;
  max-height: calc(100vh - 48px);
  max-height: calc(100dvh - 48px);
}
.discover-body {
  flex: 1 1 auto;
  min-height: 0;
  overflow-y: auto;
}
</style>
