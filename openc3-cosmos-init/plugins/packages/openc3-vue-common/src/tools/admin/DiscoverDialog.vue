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
          Scans the computers connected to COSMOS through openc3-cosmos-app for
          USB, serial, network and Bluetooth devices, and proposes plugins to
          install for them.
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
          No bridge is paired with openc3-cosmos-app. Pair a computer with
          COSMOS from the Bridges tab to discover its hardware.
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
                    v-if="candidate.possible"
                    size="small"
                    variant="outlined"
                    class="mr-2"
                    data-test="discover-possible"
                  >
                    Possible match
                    <v-tooltip
                      activator="parent"
                      location="top"
                      max-width="320"
                    >
                      Recognized only by a name pattern that other devices from
                      the same maker can share, so this plugin may not support
                      the device
                    </v-tooltip>
                  </v-chip>
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

<script setup>
import { computed, ref } from 'vue'
import { Api } from '@openc3/js-common/services'

const show = defineModel({ type: Boolean })
const emit = defineEmits(['install'])

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

const bridges = ref([])
const bridgesLoaded = ref(false)
const bridge = ref('ALL')
const scanning = ref(false)
const result = ref(null)
const error = ref(null)
const showOther = ref(false)

// Only bridges paired with openc3-cosmos-app can scan their host
const bridgeItems = computed(() => {
  const items = bridges.value.map((name) => ({ value: name, text: name }))
  if (items.length > 1) {
    items.unshift({ value: 'ALL', text: 'All bridges' })
  }
  return items
})
const multipleBridges = computed(() => bridges.value.length > 1)
const recognized = computed(() =>
  (result.value?.devices || []).filter(
    (device) => device.candidates.length > 0,
  ),
)
const unrecognized = computed(() =>
  (result.value?.devices || []).filter(
    (device) => device.candidates.length === 0,
  ),
)

async function loadBridges() {
  try {
    const response = await Api.get('/openc3-api/bridges/ALL', {
      headers: { Accept: 'application/json' },
    })
    bridges.value = Object.values(response.data || {})
      .filter((item) => item.app_public_key)
      .map((item) => item.name)
      .sort((a, b) => a.localeCompare(b))
  } catch {
    // No paired bridges, so only ALL is offered
    bridges.value = []
  }
  bridge.value = bridgeItems.value[0]?.value || 'ALL'
  bridgesLoaded.value = true
}

async function scan() {
  scanning.value = true
  error.value = null
  try {
    const response = await Api.post('/openc3-api/discovery/scan', {
      data: { bridge: bridge.value },
      headers: { 'Ignore-Errors': '500,503' },
    })
    result.value = response.data
  } catch (scanError) {
    result.value = null
    error.value =
      scanError.response?.data?.message ||
      scanError.message ||
      String(scanError)
  } finally {
    scanning.value = false
  }
}

function install(candidate) {
  emit('install', candidate)
  show.value = false
}

function kind(device) {
  return KINDS[device.class] || { text: device.class, icon: 'mdi-chip' }
}

function deviceKey(device) {
  return `${device.bridge}/${device.class}/${device.value}`
}

function candidateSubtitle(candidate) {
  const parts = []
  if (candidate.match_title && candidate.match_title !== candidate.title) {
    parts.push(candidate.match_title)
  }
  parts.push(
    candidate.source === 'store' ? 'OpenC3 Store' : 'Installed in COSMOS',
  )
  return parts.join(' · ')
}

function errorText(scanError) {
  const where = scanError.class
    ? `${kind({ class: scanError.class }).text}s on ${scanError.bridge}`
    : scanError.bridge
  return `${where}: ${scanError.message}`
}

async function loadAndScan() {
  await loadBridges()
  if (bridgeItems.value.length > 0) {
    await scan()
  }
}

// loadBridges and scan report their own errors
void loadAndScan()
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
