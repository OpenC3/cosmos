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
  <div class="d-flex flex-wrap align-center">
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
      <template #activator="{ props }">
        <v-btn
          v-bind="props"
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
      <template #activator="{ props }">
        <v-btn
          v-bind="props"
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

<script>
import OpenC3TimePicker from './OpenC3TimePicker.vue'
import { TimeFilters } from '@/util'

// Telemetry playback controls: a start date and time, play / pause that
// advances `step` seconds every second, and step / skip buttons. The time
// being shown is the v-model (a Date, null until playback starts). The
// date, time, step and skip are remembered under `storageKey`.
export default {
  components: { OpenC3TimePicker },
  mixins: [TimeFilters],
  props: {
    modelValue: { type: Date, default: null },
    // 'UTC' or 'local'
    timeZone: { type: String, default: 'local' },
    // Requests for the current time are still loading: don't step or play on
    loading: { type: Boolean, default: false },
    storageKey: { type: String, required: true },
  },
  emits: ['update:modelValue', 'update:step', 'update:playing'],
  data() {
    return {
      date: '',
      time: '',
      step: 1,
      skip: 10,
      playing: false,
      timer: null,
    }
  },
  computed: {
    backward() {
      return [
        {
          label: `Skip Backward ${this.skip} secs`,
          aria: 'Skip Backward',
          icon: 'mdi-skip-backward',
          test: 'playback-skip-backward',
          action: () => this.move(-this.skip),
        },
        {
          label: `Step Backward ${this.step} secs`,
          aria: 'Step Backward',
          icon: 'mdi-step-backward',
          test: 'playback-step-backward',
          action: () => this.move(-this.step),
        },
      ]
    },
    forward() {
      return [
        {
          label: `Step Forward ${this.step} secs`,
          aria: 'Step Forward',
          icon: 'mdi-step-forward',
          test: 'playback-step-forward',
          action: () => this.move(this.step),
        },
        {
          label: `Skip Forward ${this.skip} secs`,
          aria: 'Skip Forward',
          icon: 'mdi-skip-forward',
          test: 'playback-skip-forward',
          action: () => this.move(this.skip),
        },
      ]
    },
  },
  watch: {
    modelValue(dateTime) {
      if (!dateTime) return
      // Playback can't run past now
      if (dateTime > new Date()) {
        this.pause()
      } else {
        this.date = this.formatDate(dateTime, this.timeZone)
        this.time = this.formatTime(dateTime, this.timeZone)
      }
    },
    step: {
      immediate: true,
      handler(step) {
        this.$emit('update:step', step)
        this.remember('step', step)
      },
    },
    skip(skip) {
      this.remember('skip', skip)
    },
    date(date) {
      this.remember('date', date)
    },
    time(time) {
      this.remember('time', time)
    },
    playing(playing) {
      this.$emit('update:playing', playing)
    },
  },
  created() {
    const saved = (name) => localStorage[`${this.storageKey}__${name}`]
    if (saved('step')) this.step = Number(saved('step'))
    if (saved('skip')) this.skip = Number(saved('skip'))
    // Start an hour back each time playback opens
    const start = new Date(Date.now() - 3600000)
    this.date = this.formatDate(start, this.timeZone)
    this.time = this.formatTime(start, this.timeZone)
  },
  beforeUnmount() {
    this.pause()
  },
  methods: {
    remember(name, value) {
      localStorage[`${this.storageKey}__${name}`] = value
    },
    toggle() {
      if (this.playing) {
        this.pause()
      } else {
        this.play()
      }
    },
    // Step or skip by seconds; forward stops at now
    move(seconds) {
      if (!this.modelValue) return
      const next = new Date(this.modelValue.getTime() + 1000 * seconds)
      if (seconds < 0 || next <= new Date()) {
        this.$emit('update:modelValue', next)
      }
    },
    play() {
      const text = `${this.date}T${this.time}`
      this.$emit(
        'update:modelValue',
        new Date(this.timeZone === 'UTC' ? `${text}Z` : text),
      )
      clearInterval(this.timer)
      this.timer = setInterval(() => {
        // Don't advance time while previous playback requests are still loading
        if (this.modelValue && !this.loading) {
          this.$emit(
            'update:modelValue',
            new Date(this.modelValue.getTime() + 1000 * this.step),
          )
        }
      }, 1000)
      this.playing = true
    },
    pause() {
      clearInterval(this.timer)
      this.timer = null
      this.playing = false
    },
  },
}
</script>
