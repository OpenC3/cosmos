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
  <div class="d-flex flex-wrap align-center w-100">
    <v-text-field
      v-model="date"
      class="mr-4"
      density="compact"
      hide-details
      variant="outlined"
      label="Date"
      type="date"
      style="max-width: 200px"
      data-test="playback-date"
      :disabled="playing"
    />
    <OpenC3TimePicker
      v-model="time"
      text-field-class="mr-4"
      density="compact"
      hide-details
      variant="outlined"
      label="Time"
      style="max-width: 200px"
      data-test="playback-time"
      :disabled="playing"
    />
    <v-tooltip
      v-for="control in backward"
      :key="control.test"
      :text="control.label"
      :open-delay="2000"
      location="top"
    >
      <template #activator="{ props: activator }">
        <v-btn
          v-bind="activator"
          :icon="control.icon"
          variant="text"
          :aria-label="control.aria"
          :data-test="control.test"
          :disabled="loading"
          @click="control.action"
        />
      </template>
    </v-tooltip>
    <v-btn
      :icon="playing ? 'mdi-pause' : 'mdi-play'"
      variant="text"
      class="bg-primary"
      aria-label="Play / Pause"
      data-test="playback-play"
      @click="toggle"
    />
    <v-tooltip
      v-for="control in forward"
      :key="control.test"
      :text="control.label"
      :open-delay="2000"
      location="top"
    >
      <template #activator="{ props: activator }">
        <v-btn
          v-bind="activator"
          :icon="control.icon"
          variant="text"
          :aria-label="control.aria"
          :data-test="control.test"
          :disabled="loading"
          @click="control.action"
        />
      </template>
    </v-tooltip>
    <v-number-input
      v-model="step"
      control-variant="stacked"
      class="mr-4 ml-4"
      density="compact"
      hide-details
      variant="outlined"
      label="Step (Speed)"
      suffix="secs"
      :step="1"
      data-test="playback-speed"
      style="max-width: 180px"
    />
    <v-number-input
      v-model="skip"
      control-variant="stacked"
      class="mr-4"
      density="compact"
      hide-details
      variant="outlined"
      label="Skip"
      suffix="secs"
      :step="1"
      data-test="skip"
      style="max-width: 180px"
    />
  </div>
</template>

<script setup>
import { computed, onBeforeUnmount, ref } from 'vue'
import OpenC3TimePicker from './OpenC3TimePicker.vue'
import { useTimeFilters } from '@/composables'

// Telemetry playback controls: a start date and time, play / pause that
// advances `step` seconds every second, and step / skip buttons. The time
// being shown is the v-model (a Date, null until playback starts). The
// date, time, step and skip are remembered under `storageKey`.
const props = defineProps({
  modelValue: { type: Date, default: null },
  // 'UTC' or 'local'
  timeZone: { type: String, default: 'local' },
  // Requests for the current time are still loading: don't step or play on
  loading: { type: Boolean, default: false },
  storageKey: { type: String, required: true },
})
const emit = defineEmits(['update:modelValue', 'update:step', 'update:playing'])
const timeFilters = useTimeFilters()

function remember(name, value) {
  localStorage[`${props.storageKey}__${name}`] = value
}
function saved(name) {
  return localStorage[`${props.storageKey}__${name}`]
}

// Each field is remembered (and step and playing reported) as it's set
function stored(name, initial, onSet) {
  const value = ref(initial)
  return computed({
    get: () => value.value,
    set: (next) => {
      if (next === value.value) return
      value.value = next
      remember(name, next)
      onSet?.(next)
    },
  })
}
const date = stored('date', '')
const time = stored('time', '')
const step = stored('step', saved('step') ? Number(saved('step')) : 1, (next) =>
  emit('update:step', next),
)
const skip = stored('skip', saved('skip') ? Number(saved('skip')) : 10)
const playingValue = ref(false)
const playing = computed({
  get: () => playingValue.value,
  set: (next) => {
    if (next === playingValue.value) return
    playingValue.value = next
    emit('update:playing', next)
  },
})
let timer = null

// Start an hour back each time playback opens
showDateTime(new Date(Date.now() - 3600000))
emit('update:step', step.value)
remember('step', step.value)

const backward = computed(() => [
  {
    label: `Skip Backward ${skip.value} secs`,
    aria: 'Skip Backward',
    icon: 'mdi-skip-backward',
    test: 'playback-skip-backward',
    action: () => move(-skip.value),
  },
  {
    label: `Step Backward ${step.value} secs`,
    aria: 'Step Backward',
    icon: 'mdi-step-backward',
    test: 'playback-step-backward',
    action: () => move(-step.value),
  },
])
const forward = computed(() => [
  {
    label: `Step Forward ${step.value} secs`,
    aria: 'Step Forward',
    icon: 'mdi-step-forward',
    test: 'playback-step-forward',
    action: () => move(step.value),
  },
  {
    label: `Skip Forward ${skip.value} secs`,
    aria: 'Skip Forward',
    icon: 'mdi-skip-forward',
    test: 'playback-skip-forward',
    action: () => move(skip.value),
  },
])

function showDateTime(dateTime) {
  date.value = timeFilters.formatDate(dateTime, props.timeZone)
  time.value = timeFilters.formatTime(dateTime, props.timeZone)
}
// Moves playback to dateTime and shows it in the date and time fields.
// Playback can't run past now; returns whether it can go on.
function setDateTime(dateTime) {
  emit('update:modelValue', dateTime)
  if (dateTime > new Date()) {
    pause()
    return false
  }
  showDateTime(dateTime)
  return true
}
function toggle() {
  if (playing.value) {
    pause()
  } else {
    play()
  }
}
// Step or skip by seconds; forward stops at now
function move(seconds) {
  if (!props.modelValue) return
  const next = new Date(props.modelValue.getTime() + 1000 * seconds)
  if (seconds < 0 || next <= new Date()) {
    setDateTime(next)
  }
}
function play() {
  const text = `${date.value}T${time.value}`
  if (!setDateTime(new Date(props.timeZone === 'UTC' ? `${text}Z` : text))) {
    return
  }
  clearInterval(timer)
  timer = setInterval(() => {
    // Don't advance time while previous playback requests are still loading
    if (props.modelValue && !props.loading) {
      setDateTime(new Date(props.modelValue.getTime() + 1000 * step.value))
    }
  }, 1000)
  playing.value = true
}
function pause() {
  clearInterval(timer)
  timer = null
  playing.value = false
}

onBeforeUnmount(pause)
</script>
