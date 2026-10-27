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
  <div
    v-if="isPlayback"
    class="d-flex flex-column align-center justify-center ga-2 flex-grow-1 pa-4 text-center text-caption text-medium-emphasis"
    data-test="limits-playback"
  >
    <v-icon icon="mdi-history" size="24" />
    Limits show the live state only. Go back to live to see them.
  </div>
  <div v-else class="d-flex flex-column flex-grow-1 min-h-0">
    <div class="d-flex flex-wrap ga-2 px-4 pt-2">
      <v-chip
        v-for="count in counts"
        :key="count.level"
        size="small"
        variant="tonal"
        label
        :data-test="`limits-count-${count.level}`"
      >
        <status-symbol :level="count.level" decorative class="mr-2" />
        <span class="num font-weight-bold mr-1">{{ count.n }}</span>
        {{ count.label }}
      </v-chip>
    </div>
    <!-- Virtual rows: only the ones in view are rendered -->
    <div class="flex-grow-1 min-h-0 mt-2" aria-live="polite">
      <v-virtual-scroll
        v-if="rows.length"
        :items="rows"
        :item-height="52"
        class="h-100"
      >
        <template #default="{ item: row }">
          <div
            :key="row.key"
            :class="[
              'db-row d-flex align-center ga-3 px-4 py-2',
              `t-${row.level}`,
            ]"
            data-test="limits-row"
          >
            <status-symbol :level="row.level" />
            <div class="flex-grow-1 min-w-0">
              <div class="mono text-caption font-weight-bold text-truncate">
                {{ row.path }}
              </div>
              <div class="text-caption text-medium-emphasis text-truncate">
                {{ row.reason }}
              </div>
            </div>
            <div class="num text-right text-caption flex-shrink-0">
              <div class="text-body-2 font-weight-bold">{{ row.value }}</div>
              <div class="text-medium-emphasis">{{ durationOf(row) }}</div>
            </div>
          </div>
        </template>
      </v-virtual-scroll>
      <div
        v-else
        class="d-flex align-center ga-2 pa-4 text-caption text-medium-emphasis"
      >
        <status-symbol level="normal" decorative />
        All items within limits
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue'
import { Cable, OpenC3Api } from '@openc3/js-common/services'
import StatusSymbol from '../components/StatusSymbol.vue'
import { panelProps, usePanel } from './panelBase'
import { baseKey, itemKey } from '../composables/tlmPoller'
import { formatTelemetry } from '../composables/format'
import { LEVEL_LABELS, limitsReason, stateToLevel } from '../status'

const HISTORY_COUNT = 1000

// Live list of items out of limits for the panel's targets (all targets when
// none are listed). Seeded from get_out_of_limits and kept current from the
// limits event stream, whose history also tells us how long items have been out.
const props = defineProps(panelProps)

const { poller, itemInfo, cable, isPlayback } = usePanel(props, {
  pollKeys: () => {
    if (!streaming.value) return []
    return visible.value.map((entry) => itemKey(entry, 'CONVERTED'))
  },
  // Rows are sorted critical first
  panelLevel: () => rows.value[0]?.level ?? null,
})

// TGT__PKT__ITEM => { targetName, packetName, itemName, state, since }
const entries = ref({})
// Only the duration text reads this, so the 1 s tick doesn't re-sort and
// nothing re-renders while no item is out of limits
const now = ref(Date.now())

const api = new OpenC3Api()
const socket = cable || new Cable()
let subscription = null
let clock = null
// Bumped by start and stop, so a seed or subscription still loading
// from an earlier start is dropped
let generation = 0

const visible = computed(() => {
  const targets = props.panel.targets
  return Object.values(entries.value).filter(
    (entry) => !targets.length || targets.includes(entry.targetName),
  )
})
const rows = computed(() =>
  visible.value
    .map((entry) => {
      const polled = poller.values[itemKey(entry, 'CONVERTED')]
      const info = itemInfo.get(entry)
      const text = formatTelemetry(polled?.value, info.formatString)
      return {
        key: baseKey(entry),
        level: stateToLevel(entry.state),
        path: `${entry.targetName} ${entry.packetName} ${entry.itemName}`,
        reason: limitsReason(entry.state, itemInfo.limits(entry)),
        value: polled ? `${text} ${info.units}`.trim() : '',
        since: entry.since || 0,
      }
    })
    .sort((a, b) =>
      a.level === b.level ? b.since - a.since : a.level === 'critical' ? -1 : 1,
    ),
)
const counts = computed(() =>
  ['critical', 'caution'].map((level) => ({
    level,
    label: LEVEL_LABELS[level],
    n: rows.value.filter((row) => row.level === level).length,
  })),
)
const streaming = computed(() => !isPlayback.value)

// Live only: not in playback (past limits states aren't available). Watched
// because playback is toggled outside the panel and owns the socket.
watch(streaming, (live) => {
  if (live) {
    entries.value = {}
    start()
  } else {
    stop()
  }
})

if (streaming.value) start()

onMounted(() => {
  // Re-renders only while a duration text reads it
  clock = setInterval(() => {
    now.value = Date.now()
  }, 1000)
})
onUnmounted(() => {
  clearInterval(clock)
  stop()
  if (!cable) socket.disconnect()
})

// Load what's out of limits now and follow the event stream. The seed
// and the stream are independent; setEntry keeps the earliest known time.
function start() {
  const current = ++generation
  api
    .get_out_of_limits()
    .then((items) => {
      if (current !== generation) return
      for (const [targetName, packetName, itemName, state] of items) {
        setEntry(targetName, packetName, itemName, state, null)
      }
    })
    .catch((error) => {
      console.error('Dashboards limits panel failed to load:', error)
    })
  socket
    .createSubscription(
      'LimitsEventsChannel',
      window.openc3Scope,
      {
        received: (messages) => {
          if (current !== generation) return
          socket.recordPing()
          handleMessages(messages)
        },
      },
      { history_count: HISTORY_COUNT },
    )
    .then((created) => {
      if (current !== generation) {
        created.unsubscribe()
        return
      }
      subscription = created
    })
}

function stop() {
  generation++
  subscription?.unsubscribe()
  subscription = null
}

function durationOf(row) {
  return row.since ? formatDuration(now.value - row.since) : ''
}

function setEntry(targetName, packetName, itemName, state, since) {
  const key = baseKey({ targetName, packetName, itemName })
  const out = state && (state.startsWith('RED') || state.startsWith('YELLOW'))
  if (!out) {
    delete entries.value[key]
    return
  }
  const existing = entries.value[key]
  entries.value[key] = {
    targetName,
    packetName,
    itemName,
    state,
    // Keep the original time while the item stays out of limits
    since:
      existing && existing.state === state && existing.since
        ? existing.since
        : since,
  }
}

function handleMessages(messages) {
  for (const json of messages) {
    const message = JSON.parse(json.event)
    // The channel also sends LIMITS_SETTINGS and LIMITS_SET messages
    if (message.type !== 'LIMITS_CHANGE' || message.suppress_stored) continue
    setEntry(
      message.target_name,
      message.packet_name,
      message.item_name,
      message.new_limits_state,
      Math.floor(message.time_nsec / 1_000_000),
    )
  }
}

function formatDuration(ms) {
  const seconds = Math.max(0, Math.floor(ms / 1000))
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ${minutes % 60}m`
  return `${Math.floor(hours / 24)}d ${hours % 24}h`
}
</script>
