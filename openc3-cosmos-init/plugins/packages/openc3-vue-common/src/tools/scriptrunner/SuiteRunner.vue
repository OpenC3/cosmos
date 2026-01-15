<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# Modified by OpenC3, Inc.
# All changes Copyright 2026, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
-->

<template>
  <div>
    <div id="tr-container">
      <v-row no-gutters align="center">
        <v-col cols="4">
          <v-row no-gutters>
            <v-col cols="6">
              <v-tooltip :open-delay="600" location="top">
                <template #activator="{ props: activatorProps }">
                  <div v-bind="activatorProps">
                    <v-checkbox
                      v-model="options"
                      label="Pause on Error"
                      value="pauseOnError"
                      hide-details
                      data-test="pause-on-error"
                    />
                  </div>
                </template>
                <span>
                  Checked pauses the script when an error is encountered<br />
                  Unchecked continues without user interaction
                </span>
              </v-tooltip>
            </v-col>
            <v-col cols="6">
              <v-tooltip :open-delay="600" location="top">
                <template #activator="{ props: activatorProps }">
                  <div v-bind="activatorProps">
                    <v-checkbox
                      v-model="options"
                      label="Manual"
                      value="manual"
                      hide-details
                      data-test="manual"
                    />
                  </div>
                </template>
                <span>
                  {{ checkedManualTooltip }}<br />
                  {{ uncheckedManualTooltip }}
                </span>
              </v-tooltip>
            </v-col>
          </v-row>
        </v-col>
        <v-col cols="8">
          <v-row no-gutters justify="end">
            <v-col cols="5">
              <v-select
                v-model="suite"
                label="Suite:"
                class="mb-2 mr-2"
                hide-details
                density="compact"
                variant="outlined"
                :items="suites"
                data-test="select-suite"
                @update:model-value="suiteChanged"
              />
            </v-col>
            <v-col cols="auto">
              <v-btn
                color="primary"
                class="mr-2"
                :disabled="disableButtons || !userInfo.execute"
                data-test="start-suite"
                @click="$emit('button', { method: 'start', suite, options })"
              >
                Start
              </v-btn>
              <v-btn
                color="primary"
                class="mr-2"
                data-test="setup-suite"
                :disabled="
                  disableButtons || !setupSuiteEnabled || !userInfo.execute
                "
                @click="$emit('button', { method: 'setup', suite, options })"
              >
                Setup
              </v-btn>
              <v-btn
                color="primary"
                data-test="teardown-suite"
                :disabled="
                  disableButtons || !teardownSuiteEnabled || !userInfo.execute
                "
                @click="$emit('button', { method: 'teardown', suite, options })"
              >
                Teardown
              </v-btn>
            </v-col>
          </v-row>
        </v-col>
      </v-row>
      <v-row no-gutters>
        <v-col cols="4">
          <v-row no-gutters>
            <v-col cols="6">
              <v-tooltip :open-delay="600" location="top">
                <template #activator="{ props: activatorProps }">
                  <div v-bind="activatorProps">
                    <v-checkbox
                      v-model="options"
                      label="Continue after Error"
                      value="continueAfterError"
                      hide-details
                      data-test="continue-after-error"
                    />
                  </div>
                </template>
                <span>
                  Checked allows the script to continue when an error is
                  encountered<br />
                  Unchecked forces the current script to end
                </span>
              </v-tooltip>
            </v-col>
            <v-col cols="6">
              <v-tooltip :open-delay="600" location="top">
                <template #activator="{ props: activatorProps }">
                  <div v-bind="activatorProps">
                    <v-checkbox
                      v-model="options"
                      label="Loop"
                      value="loop"
                      hide-details
                      data-test="loop"
                    />
                  </div>
                </template>
                <span>
                  Checked continuously executes until explicitly stopped<br />
                  Unchecked executes only the started script(s)
                </span>
              </v-tooltip>
            </v-col>
          </v-row>
        </v-col>
        <v-col cols="8">
          <v-row no-gutters justify="end">
            <v-col cols="5">
              <v-select
                v-model="group"
                label="Group:"
                class="mb-2 mr-2"
                hide-details
                density="compact"
                variant="outlined"
                :items="groups"
                data-test="select-group"
                @update:model-value="groupChanged"
              />
            </v-col>
            <v-col cols="auto">
              <v-btn
                color="primary"
                class="mr-2"
                :disabled="disableButtons || !userInfo.execute"
                data-test="start-group"
                @click="
                  $emit('button', { method: 'start', suite, group, options })
                "
              >
                Start
              </v-btn>
              <v-btn
                color="primary"
                class="mr-2"
                data-test="setup-group"
                :disabled="
                  disableButtons || !setupGroupEnabled || !userInfo.execute
                "
                @click="
                  $emit('button', { method: 'setup', suite, group, options })
                "
              >
                Setup
              </v-btn>
              <v-btn
                color="primary"
                data-test="teardown-group"
                :disabled="
                  disableButtons || !teardownGroupEnabled || !userInfo.execute
                "
                @click="
                  $emit('button', { method: 'teardown', suite, group, options })
                "
              >
                Teardown
              </v-btn>
            </v-col>
          </v-row>
        </v-col>
      </v-row>
      <v-row no-gutters>
        <v-col cols="4">
          <v-row no-gutters>
            <v-col cols="6">
              <v-tooltip :open-delay="600" location="top">
                <template #activator="{ props: activatorProps }">
                  <div v-bind="activatorProps">
                    <v-checkbox
                      v-model="options"
                      label="Abort after Error"
                      value="abortAfterError"
                      hide-details
                      data-test="abort-after-error"
                    />
                  </div>
                </template>
                <span>
                  Checked stops additional script execution when an error is
                  encountered<br />
                  Unchecked allows additional scripts to execute
                </span>
              </v-tooltip>
            </v-col>
            <v-col cols="6">
              <v-tooltip :open-delay="600" location="top">
                <template #activator="{ props: activatorProps }">
                  <div v-bind="activatorProps">
                    <v-checkbox
                      v-model="options"
                      :disabled="!options.includes('loop')"
                      label="Break Loop on Error"
                      value="breakLoopOnError"
                      hide-details
                      data-test="break-loop-on-error"
                    />
                  </div>
                </template>
                <span>
                  Checked breaks the loop option when an error is encountered<br />
                  Unchecked allows the loop to run continuously<br />
                  Note: Abort after Error still breaks the loop
                </span>
              </v-tooltip>
            </v-col>
          </v-row>
        </v-col>
        <v-col cols="8">
          <v-row no-gutters justify="end">
            <v-col cols="5">
              <v-select
                v-model="script"
                label="Script:"
                class="mb-2 mr-2"
                hide-details
                density="compact"
                variant="outlined"
                :items="scriptNames"
                item-title="title"
                item-value="value"
                data-test="select-script"
                @update:model-value="scriptChanged"
              />
            </v-col>
            <v-col cols="auto">
              <v-btn
                color="primary"
                class="mr-2"
                :disabled="disableButtons || !userInfo.execute"
                data-test="start-script"
                @click="
                  $emit('button', {
                    method: 'start',
                    suite,
                    group,
                    script,
                    options,
                  })
                "
              >
                Start
              </v-btn>
              <!-- Create some invisible buttons to line up Start properly -->
              <v-btn color="primary" class="mr-2 invisible"> Setup </v-btn>
              <v-btn color="primary" class="invisible"> Teardown </v-btn>
            </v-col>
          </v-row>
        </v-col>
      </v-row>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted } from 'vue'

const props = defineProps({
  suiteMap: {
    type: Object,
    required: true,
  },
  disableButtons: {
    type: Boolean,
    required: true,
  },
  filename: {
    type: String,
    required: true,
  },
})

const emit = defineEmits(['button', 'loaded'])

const suites = ref([])
const groups = ref([])
const scripts = ref([])
const suite = ref('')
const group = ref('')
const script = ref('')
const options = ref(['pauseOnError', 'manual', 'continueAfterError'])
const userInfo = ref({})

const checkedManualTooltip = computed(() => {
  if (props.filename.endsWith('.py')) {
    return 'Checked sets the RunningScript.manual variable to True'
  } else {
    return 'Checked sets the $manual variable to true'
  }
})

const uncheckedManualTooltip = computed(() => {
  if (props.filename.endsWith('.py')) {
    return 'Unchecked sets the RunningScript.manual variable to False'
  } else {
    return 'Unchecked sets the $manual variable to false'
  }
})

const setupSuiteEnabled = computed(() => {
  return !!(suite.value && props.suiteMap[suite.value]?.setup)
})

const teardownSuiteEnabled = computed(() => {
  return !!(suite.value && props.suiteMap[suite.value]?.teardown)
})

const setupGroupEnabled = computed(() => {
  return !!(
    suite.value &&
    group.value &&
    props.suiteMap[suite.value]?.groups[group.value]?.setup
  )
})

const teardownGroupEnabled = computed(() => {
  return !!(
    suite.value &&
    group.value &&
    props.suiteMap[suite.value]?.groups[group.value]?.teardown
  )
})

const scriptNames = computed(() => {
  return scripts.value.map((name) => {
    return {
      // strip script_ or test_ from the name
      title: name.replace(/^(script_|test_)/, ''),
      value: name,
    }
  })
})

// Watch the suiteMap so we can recreate the suites and set the initial value
watch(
  () => props.suiteMap,
  () => {
    updateSuiteMap()
  },
  { deep: true }, // Deep watcher because suiteMap is a nested Object
)

function updateSuiteMap() {
  suites.value = Object.keys(props.suiteMap)
  if (
    props.suiteMap[suite.value] == undefined ||
    props.suiteMap[suite.value].groups[group.value] == undefined
  ) {
    initSuites()
  } else {
    groups.value = Object.keys(props.suiteMap[suite.value].groups)
    scripts.value = props.suiteMap[suite.value].groups[group.value].scripts
  }
}

function initSuites() {
  suites.value = Object.keys(props.suiteMap)
  suiteChanged(suites.value[0])
}

function suiteChanged(event) {
  if (!event || props.suiteMap[event] == undefined) {
    return
  }
  suite.value = event
  group.value = ''
  script.value = ''
  groups.value = Object.keys(props.suiteMap[event].groups)
  // Make the group default be the first group
  groupChanged(groups.value[0])
}

function groupChanged(event) {
  if (
    !event ||
    props.suiteMap[suite.value] == undefined ||
    props.suiteMap[suite.value].groups[event] == undefined
  ) {
    return
  }
  group.value = event
  script.value = ''
  scripts.value = props.suiteMap[suite.value].groups[event].scripts
  // Make the script default be the first
  scriptChanged(scripts.value[0])
}

function scriptChanged(event) {
  script.value = event
}

onMounted(() => {
  userInfo.value = JSON.parse(localStorage['script_runner__userinfo'])
  initSuites()
  emit('loaded')
})
</script>

<style lang="scss" scoped>
.invisible {
  visibility: hidden;
}
#tr-container {
  padding-top: 0px;
  padding-bottom: 15px;
  padding-left: 0px;
  padding-right: 0px;
}
</style>
