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
  <section
    class="cs-panel d-flex flex-column rounded-lg min-w-0"
    aria-labelledby="cs-history-title"
  >
    <header class="cs-panel-header d-flex align-center ga-2 pl-4 pr-2">
      <h2 id="cs-history-title" class="cs-panel-title">History</h2>
      <span
        v-if="entries.length"
        class="text-caption text-medium-emphasis num"
        data-test="history-count"
      >
        {{ entries.length }}
      </span>
      <span class="cs-hint text-caption text-medium-emphasis text-truncate">
        Click a command to load it
      </span>
      <v-spacer />
      <v-btn
        icon="mdi-delete-sweep"
        size="small"
        variant="text"
        density="comfortable"
        title="Clear history"
        aria-label="Clear history"
        data-test="clear-history"
        @click="emit('clear')"
      />
    </header>
    <div
      v-if="!entries.length"
      class="px-4 pb-4 text-caption text-medium-emphasis"
    >
      Commands you send are listed here, newest first.
    </div>
    <!-- The list is the history's text, so tests and copy / paste of the
         whole list see only the commands -->
    <v-virtual-scroll
      ref="list"
      :items="entries"
      item-key="id"
      max-height="50vh"
      class="cs-history-list"
      data-test="sender-history"
    >
      <template #default="{ item }">
        <div
          :class="[
            'cs-history-row d-flex align-start ga-3 pl-4 pr-2',
            { current: item.id === selectedId },
          ]"
        >
          <span
            class="cs-time num text-medium-emphasis flex-shrink-0"
            :title="fullTime(item.sentAt)"
          >
            {{ shortTime(item.sentAt) }}
          </span>
          <button
            type="button"
            class="cs-cmd mono flex-grow-1 min-w-0 text-left"
            :aria-current="item.id === selectedId ? 'true' : undefined"
            :title="`Load ${item.cmd}`"
            data-test="history-entry"
            @click="emit('select', item)"
          >
            {{ item.cmd }}
          </button>
          <v-btn
            :icon="copiedId === item.id ? 'mdi-check' : 'mdi-content-copy'"
            size="x-small"
            variant="text"
            class="cs-copy flex-shrink-0"
            :title="copiedId === item.id ? 'Copied' : 'Copy'"
            aria-label="Copy command"
            data-test="history-copy"
            @click="copy(item)"
          />
        </div>
      </template>
    </v-virtual-scroll>
  </section>
</template>

<script setup>
import { ref } from 'vue'
import {
  formatDate,
  formatDateTimeHMS,
  formatTimeHMS,
} from '@openc3/vue-common/util'
import { writeClipboard } from './clipboard'

// The read-only history of sent commands, newest first. Clicking a command
// loads it into the form (select); it is never sent from here.
const props = defineProps({
  // { id, cmd, sentAt } from useCommandHistory
  entries: {
    type: Array,
    required: true,
  },
  selectedId: {
    type: Number,
    default: null,
  },
  timeZone: {
    type: String,
    default: 'local',
  },
})
const emit = defineEmits(['select', 'clear'])

const list = ref(null)
const copiedId = ref(null)

// Bring an entry into view, e.g. when stepping through with the keyboard
function scrollToEntry(id) {
  const index = props.entries.findIndex((entry) => entry.id === id)
  if (index !== -1) list.value?.scrollToIndex(index)
}
defineExpose({ scrollToEntry })
let copiedTimer = null

// Today's sends show only the time, older ones the date as well
function shortTime(sentAt) {
  if (sentAt === null) return '—'
  const date = new Date(sentAt)
  if (
    formatDate(date, props.timeZone) === formatDate(new Date(), props.timeZone)
  ) {
    return formatTimeHMS(date, props.timeZone)
  }
  return formatDateTimeHMS(date, props.timeZone)
}

function fullTime(sentAt) {
  if (sentAt === null) return 'Sent before the history kept times'
  return formatDateTimeHMS(new Date(sentAt), props.timeZone)
}

async function copy(item) {
  try {
    await writeClipboard(item.cmd)
    copiedId.value = item.id
    clearTimeout(copiedTimer)
    copiedTimer = setTimeout(() => {
      copiedId.value = null
    }, 1500)
  } catch (error) {
    console.error('Failed to copy command:', error)
  }
}
</script>

<style scoped>
.cs-history-row {
  border-left: 3px solid transparent;
  padding-top: 3px;
  padding-bottom: 3px;
}
.cs-history-row:hover {
  background: rgba(var(--v-theme-on-surface), 0.04);
}
/* The command last loaded into the form: a secondary bar on the left that
   doesn't shift the text, as Dashboards marks the current choice */
.cs-history-row.current {
  border-left-color: rgb(var(--v-theme-secondary));
  background: rgba(var(--v-theme-on-surface), 0.06);
}
.cs-time {
  min-width: 8ch;
  padding-top: 4px;
  font-size: 12px;
}
.cs-cmd {
  padding: 3px 0;
  font-size: 13px;
  line-height: 1.45;
  color: inherit;
  cursor: pointer;
  overflow-wrap: anywhere;
  border-radius: 4px;
}
.cs-cmd:focus-visible {
  outline: 2px solid rgb(var(--v-theme-secondary));
  outline-offset: 2px;
}
/* Only on hover or focus, so the list stays quiet; always on touch screens */
.cs-copy {
  opacity: 0;
  transition: opacity 0.15s;
}
.cs-history-row:hover .cs-copy,
.cs-history-row:focus-within .cs-copy {
  opacity: 1;
}
@media (hover: none) {
  .cs-copy {
    opacity: 1;
  }
}
</style>
