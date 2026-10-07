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
  <div v-else class="d-flex flex-column flex-grow-1" style="min-height: 0">
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
    <div class="flex-grow-1 overflow-y-auto mt-2" aria-live="polite">
      <div
        v-for="row in rows"
        :key="row.key"
        :class="['db-row d-flex align-center ga-3 px-4 py-2', `t-${row.level}`]"
        data-test="limits-row"
      >
        <status-symbol :level="row.level" />
        <div class="flex-grow-1" style="min-width: 0">
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
      <div
        v-if="!rows.length"
        class="d-flex align-center ga-2 pa-4 text-caption text-medium-emphasis"
      >
        <status-symbol level="normal" decorative />
        All items within limits
      </div>
    </div>
  </div>
</template>

<script>
import { Cable, OpenC3Api } from '@openc3/js-common/services'
import StatusSymbol from '../components/StatusSymbol.vue'
import panelBase from './panelBase'
import { baseKey, itemKey } from '../composables/tlmPoller'
import { formatTelemetry } from '../composables/format'
import { LEVEL_LABELS, limitsReason, stateToLevel } from '../status'

const HISTORY_COUNT = 1000

// Live list of items out of limits for the panel's targets (all targets when
// none are listed). Seeded from get_out_of_limits and kept current from the
// limits event stream, whose history also tells us how long items have been out.
export default {
  components: { StatusSymbol },
  mixins: [panelBase],
  data() {
    return {
      // TGT__PKT__ITEM => { targetName, packetName, itemName, state, since }
      entries: {},
      // Only the duration text reads this, so the 1 s tick doesn't re-sort
      now: Date.now(),
    }
  },
  computed: {
    visible() {
      const targets = this.panel.targets
      return Object.values(this.entries).filter(
        (entry) => !targets.length || targets.includes(entry.targetName),
      )
    },
    rows() {
      return this.visible
        .map((entry) => {
          const polled = this.poller.values[itemKey(entry, 'CONVERTED')]
          const info = this.itemInfo.get(entry)
          const text = formatTelemetry(polled?.value, info.formatString)
          return {
            key: baseKey(entry),
            level: stateToLevel(entry.state),
            path: `${entry.targetName} ${entry.packetName} ${entry.itemName}`,
            reason: limitsReason(entry.state, this.itemInfo.limits(entry)),
            value: polled ? `${text} ${info.units}`.trim() : '',
            since: entry.since || 0,
          }
        })
        .sort((a, b) =>
          a.level === b.level
            ? b.since - a.since
            : a.level === 'critical'
              ? -1
              : 1,
        )
    },
    counts() {
      return ['critical', 'caution'].map((level) => ({
        level,
        label: LEVEL_LABELS[level],
        n: this.rows.filter((row) => row.level === level).length,
      }))
    },
    streaming() {
      return this.isLive && !this.isPlayback
    },
    pollKeys() {
      if (!this.streaming) return []
      return this.visible.map((entry) => itemKey(entry, 'CONVERTED'))
    },
    // Rows are sorted critical first
    panelLevel() {
      return this.rows[0]?.level ?? null
    },
  },
  watch: {
    // Nothing is fetched while the dashboard is being edited
    // Live only: not while editing (nothing is fetched) or in playback (past
    // limits states aren't available)
    streaming(live) {
      if (live) {
        this.entries = {}
        this.start()
      } else {
        this.stop()
      }
    },
    visible(entries) {
      for (const entry of entries) this.itemInfo.get(entry)
    },
  },
  created() {
    this.api = new OpenC3Api()
    this.socket = this.cable || new Cable()
    this.clock = setInterval(() => {
      this.now = Date.now()
    }, 1000)
    if (this.streaming) this.start()
  },
  unmounted() {
    clearInterval(this.clock)
    this.stop()
    if (!this.cable) this.socket.disconnect()
  },
  methods: {
    // Load what's out of limits now and follow the event stream. The seed
    // and the stream are independent; setEntry keeps the earliest known time.
    start() {
      this.api
        .get_out_of_limits()
        .then((items) => {
          for (const [targetName, packetName, itemName, state] of items) {
            this.setEntry(targetName, packetName, itemName, state, null)
          }
        })
        .catch((error) => {
          console.error('Dashboards limits panel failed to load:', error)
        })
      this.socket
        .createSubscription(
          'LimitsEventsChannel',
          window.openc3Scope,
          {
            received: (messages) => {
              this.socket.recordPing()
              this.handleMessages(messages)
            },
          },
          { history_count: HISTORY_COUNT },
        )
        .then((subscription) => {
          this.subscription = subscription
        })
    },
    stop() {
      this.subscription?.unsubscribe()
      this.subscription = null
    },
    durationOf(row) {
      return row.since ? this.formatDuration(this.now - row.since) : ''
    },
    setEntry(targetName, packetName, itemName, state, since) {
      const key = baseKey({ targetName, packetName, itemName })
      const out =
        state && (state.startsWith('RED') || state.startsWith('YELLOW'))
      if (!out) {
        delete this.entries[key]
        return
      }
      const existing = this.entries[key]
      this.entries[key] = {
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
    },
    handleMessages(messages) {
      for (const json of messages) {
        const message = JSON.parse(json.event)
        // The channel also sends LIMITS_SETTINGS and LIMITS_SET messages
        if (message.type !== 'LIMITS_CHANGE' || message.suppress_stored)
          continue
        this.setEntry(
          message.target_name,
          message.packet_name,
          message.item_name,
          message.new_limits_state,
          Math.floor(message.time_nsec / 1_000_000),
        )
      }
    },
    formatDuration(ms) {
      const seconds = Math.max(0, Math.floor(ms / 1000))
      if (seconds < 60) return `${seconds}s`
      const minutes = Math.floor(seconds / 60)
      if (minutes < 60) return `${minutes}m`
      const hours = Math.floor(minutes / 60)
      if (hours < 24) return `${hours}h ${minutes % 60}m`
      return `${Math.floor(hours / 24)}d ${hours % 24}h`
    },
  },
}
</script>
