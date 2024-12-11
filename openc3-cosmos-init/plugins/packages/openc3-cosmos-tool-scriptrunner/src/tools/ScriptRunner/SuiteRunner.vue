<!--
# Copyright 2022 Ball Aerospace & Technologies Corp.
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

# Modified by OpenC3, Inc.
# All changes Copyright 2023, OpenC3, Inc.
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
              <v-tooltip location="top">
                <template v-slot:activator="{ props }">
                  <div v-bind="props">
                    <v-checkbox
                      v-model="options"
                      label="Pause on Error"
                      value="pauseOnError"
                      hide-details
                      data-test="pause-on-error"
                    />
                  </div>
                </template>
                <span
                  >Checked pauses the script when an error is encountered<br />Unchecked
                  continues without user interaction</span
                >
              </v-tooltip>
            </v-col>
            <v-col cols="6">
              <v-tooltip location="top">
                <template v-slot:activator="{ props }">
                  <div v-bind="props">
                    <v-checkbox
                      v-model="options"
                      label="Manual"
                      value="manual"
                      hide-details
                      data-test="manual"
                    />
                  </div>
                </template>
                <span
                  >{{ checkedManualTooltip }}<br />{{
                    uncheckedManualTooltip
                  }}</span
                >
              </v-tooltip>
            </v-col>
          </v-row>
        </v-col>
        <v-col cols="8">
          <v-row no-gutters justify="end">
            <v-col cols="5">
              <v-select
                label="Suite:"
                class="mb-2 mr-2"
                hide-details
                density="compact"
                variant="outlined"
                @update:model-value="suiteChanged"
                :items="suites"
                v-model="suite"
                data-test="select-suite"
              />
            </v-col>
            <v-col cols="auto">
              <v-btn
                color="primary"
                class="mr-2"
                :disabled="disableButtons || !userInfo.execute"
                @click="$emit('button', { method: 'start', suite, options })"
                data-test="start-suite"
              >
                Start
              </v-btn>
              <v-btn
                color="primary"
                class="mr-2"
                @click="$emit('button', { method: 'setup', suite, options })"
                data-test="setup-suite"
                :disabled="
                  disableButtons || !setupSuiteEnabled || !userInfo.execute
                "
              >
                Setup
              </v-btn>
              <v-btn
                color="primary"
                @click="$emit('button', { method: 'teardown', suite, options })"
                data-test="teardown-suite"
                :disabled="
                  disableButtons || !teardownSuiteEnabled || !userInfo.execute
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
              <v-tooltip location="top">
                <template v-slot:activator="{ props }">
                  <div v-bind="props">
                    <v-checkbox
                      v-model="options"
                      label="Continue after Error"
                      value="continueAfterError"
                      hide-details
                      data-test="continue-after-error"
                    />
                  </div>
                </template>
                <span
                  >Checked allows the script to continue when an error is
                  encountered<br />Unchecked forces the current script to
                  end</span
                >
              </v-tooltip>
            </v-col>
            <v-col cols="6">
              <v-tooltip location="top">
                <template v-slot:activator="{ props }">
                  <div v-bind="props">
                    <v-checkbox
                      v-model="options"
                      label="Loop"
                      value="loop"
                      hide-details
                      data-test="loop"
                    />
                  </div>
                </template>
                <span
                  >Checked continuously executes until explicitly stopped<br />
                  Unchecked executes only the started script(s)</span
                >
              </v-tooltip>
            </v-col>
          </v-row>
        </v-col>
        <v-col cols="8">
          <v-row no-gutters justify="end">
            <v-col cols="5">
              <v-select
                label="Group:"
                class="mb-2 mr-2"
                hide-details
                density="compact"
                variant="outlined"
                @update:model-value="groupChanged"
                :items="groups"
                v-model="group"
                data-test="select-group"
              />
            </v-col>
            <v-col cols="auto">
              <v-btn
                color="primary"
                class="mr-2"
                :disabled="disableButtons || !userInfo.execute"
                @click="
                  $emit('button', { method: 'start', suite, group, options })
                "
                data-test="start-group"
              >
                Start
              </v-btn>
              <v-btn
                color="primary"
                class="mr-2"
                @click="
                  $emit('button', { method: 'setup', suite, group, options })
                "
                data-test="setup-group"
                :disabled="
                  disableButtons || !setupGroupEnabled || !userInfo.execute
                "
              >
                Setup
              </v-btn>
              <v-btn
                color="primary"
                @click="
                  $emit('button', { method: 'teardown', suite, group, options })
                "
                data-test="teardown-group"
                :disabled="
                  disableButtons || !teardownGroupEnabled || !userInfo.execute
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
              <v-tooltip location="top">
                <template v-slot:activator="{ props }">
                  <div v-bind="props">
                    <v-checkbox
                      v-model="options"
                      label="Abort after Error"
                      value="abortAfterError"
                      hide-details
                      data-test="abort-after-error"
                    />
                  </div>
                </template>
                <span
                  >Checked stops additional script execution when an error is
                  encountered<br />
                  Unchecked allows additional scripts to execute</span
                >
              </v-tooltip>
            </v-col>
            <v-col cols="6">
              <v-tooltip location="top">
                <template v-slot:activator="{ props }">
                  <div v-bind="props">
                    <v-checkbox
                      :disabled="!options.includes('loop')"
                      v-model="options"
                      label="Break Loop on Error"
                      value="breakLoopOnError"
                      hide-details
                      data-test="break-loop-on-error"
                    />
                  </div>
                </template>
                <span
                  >Checked breaks the loop option when an error is
                  encountered<br />
                  Unchecked allows the loop to run continuously<br />
                  Note: Abort after Error still breaks the loop</span
                >
              </v-tooltip>
            </v-col>
          </v-row>
        </v-col>
        <v-col cols="8">
          <v-row no-gutters justify="end">
            <v-col cols="5">
              <v-select
                label="Script:"
                class="mb-2 mr-2"
                hide-details
                density="compact"
                variant="outlined"
                @update:model-value="scriptChanged"
                :items="scriptNames"
                item-title="title"
                item-value="value"
                v-model="script"
                data-test="select-script"
              />
            </v-col>
            <v-col cols="auto">
              <v-btn
                color="primary"
                class="mr-2"
                :disabled="disableButtons || !userInfo.execute"
                @click="
                  $emit('button', {
                    method: 'start',
                    suite,
                    group,
                    script,
                    options,
                  })
                "
                data-test="start-script"
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

<script>
export default {
  props: {
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
  },
  data() {
    return {
      suites: [],
      groups: [],
      scripts: [],
      suite: '',
      group: '',
      script: '',
      options: ['pauseOnError', 'manual', 'continueAfterError'],
      userInfo: {},
    }
  },
  computed: {
    checkedManualTooltip() {
      if (this.filename.endsWith('.py')) {
        return 'Checked sets the RunningScript.manual variable to True'
      } else {
        return 'Checked sets the $manual variable to true'
      }
    },
    uncheckedManualTooltip() {
      if (this.filename.endsWith('.py')) {
        return 'Unchecked sets the RunningScript.manual variable to False'
      } else {
        return 'Unchecked sets the $manual variable to false'
      }
    },
    setupSuiteEnabled() {
      if (this.suite && this.suiteMap[this.suite].setup) {
        return true
      } else {
        return false
      }
    },
    teardownSuiteEnabled() {
      if (this.suite && this.suiteMap[this.suite].teardown) {
        return true
      } else {
        return false
      }
    },
    setupGroupEnabled() {
      if (
        this.suite &&
        this.group &&
        this.suiteMap[this.suite].groups[this.group].setup
      ) {
        return true
      } else {
        return false
      }
    },
    teardownGroupEnabled() {
      if (
        this.suite &&
        this.group &&
        this.suiteMap[this.suite].groups[this.group].teardown
      ) {
        return true
      } else {
        return false
      }
    },
    scriptNames() {
      return this.scripts.map((name) => {
        return {
          // strip script_ or test_ from the name
          title: name.replace(/^(script_|test_)/, ''),
          value: name,
        }
      })
    },
  },
  created() {
    this.userInfo = JSON.parse(localStorage['script_runner__userinfo'])
    this.initSuites()
    this.$emit('loaded')
  },
  // Watch the suiteMap so we can recreate the suites and set the initial value
  watch: {
    suiteMap: {
      handler: function (newVal, oldVal) {
        this.updateSuiteMap()
      },
      deep: true, // Deep watcher because suiteMap is a nested Object
    },
  },
  methods: {
    updateSuiteMap() {
      this.suites = Object.keys(this.suiteMap)
      if (
        this.suiteMap[this.suite] == undefined ||
        this.suiteMap[this.suite].groups[this.group] == undefined
      ) {
        this.initSuites()
      } else {
        this.groups = Object.keys(this.suiteMap[this.suite].groups)
        this.scripts = this.suiteMap[this.suite].groups[this.group].scripts
      }
    },
    initSuites() {
      this.suites = Object.keys(this.suiteMap)
      this.suiteChanged(this.suites[0])
    },
    suiteChanged(event) {
      this.suite = event
      this.group = ''
      this.script = ''
      this.groups = Object.keys(this.suiteMap[event].groups)
      // Make the group default be the first group
      this.groupChanged(this.groups[0])
    },
    groupChanged(event) {
      this.group = event
      this.script = ''
      this.scripts = this.suiteMap[this.suite].groups[event].scripts
      // Make the script default be the first
      this.scriptChanged(this.scripts[0])
    },
    scriptChanged(event) {
      this.script = event
    },
  },
}
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
