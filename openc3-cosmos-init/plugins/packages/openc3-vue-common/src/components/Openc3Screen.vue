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
# All changes Copyright 2025, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# This screen expects to be inside of two parent elements.
# An overall item, and then a container for all screens
-->

<template>
  <div ref="bar" :style="computedStyle">
    <v-card
      v-if="!inline"
      :min-height="height"
      :min-width="width"
      style="cursor: default"
    >
      <v-toolbar height="24">
        <v-btn
          v-show="errors.length !== 0"
          icon="mdi-alert"
          variant="text"
          density="compact"
          data-test="error-graph-icon"
          aria-label="Show Errors"
          @click="
            () => {
              errorDialog = true
            }
          "
        />
        <v-btn
          icon="mdi-pencil"
          variant="text"
          density="compact"
          data-test="edit-screen-icon"
          aria-label="Edit Screen"
          @click="openEdit"
        />
        <v-tooltip v-if="!fixFloated" :open-delay="600" location="top">
          <template #activator="{ props }">
            <div v-bind="props">
              <v-btn
                :icon="floated ? 'mdi-balloon' : 'mdi-view-grid-outline'"
                variant="text"
                density="compact"
                data-test="float-screen-icon"
                :aria-label="floated ? 'Unfloat Screen' : 'Float Screen'"
                @click="floatScreen"
              />
            </div>
          </template>
          <span> {{ floated ? 'Unfloat Screen' : 'Float Screen' }} </span>
        </v-tooltip>
        <v-tooltip v-if="floated" :open-delay="600" location="top">
          <template #activator="{ props }">
            <div v-bind="props">
              <v-btn
                icon="mdi-arrow-up"
                variant="text"
                density="compact"
                data-test="up-screen-icon"
                aria-label="Move Screen Up"
                @click="upScreen"
              />
            </div>
          </template>
          <span> Move Screen Up </span>
        </v-tooltip>
        <v-tooltip
          v-if="floated && zIndex > minZ"
          :open-delay="600"
          location="top"
        >
          <template #activator="{ props }">
            <div v-bind="props">
              <v-btn
                icon="mdi-arrow-down"
                variant="text"
                density="compact"
                data-test="down-screen-icon"
                aria-label="Move Screen Down"
                @click="downScreen"
              />
            </div>
          </template>
          <span> Move Screen Down </span>
        </v-tooltip>
        <v-spacer />
        <span> {{ target }} {{ screen }} </span>
        <v-spacer />
        <v-btn
          v-if="expand"
          icon="mdi-window-minimize"
          variant="text"
          density="compact"
          data-test="minimize-screen-icon"
          aria-label="Minimize Screen"
          @click="minMaxTransition"
        />
        <v-btn
          v-else
          icon="mdi-window-maximize"
          variant="text"
          density="compact"
          data-test="maximize-screen-icon"
          aria-label="Maximize Screen"
          @click="minMaxTransition"
        />
        <v-btn
          v-if="showClose"
          icon="mdi-close-box"
          variant="text"
          density="compact"
          data-test="close-screen-icon"
          aria-label="Close Screen"
          @click="$emit('close-screen')"
        />
      </v-toolbar>
      <v-expand-transition v-if="!editDialog">
        <div
          v-show="expand"
          ref="screen"
          class="pa-1"
          style="position: relative"
        >
          <v-overlay
            style="pointer-events: none"
            :model-value="errors.length !== 0"
            opacity="0.8"
            absolute
            attach
            scroll-strategy="none"
          />
          <vertical-widget
            :key="screenKey"
            :widgets="layoutStack[0].widgets"
            :screen-values="screenValues"
            :screen-time-zone="timeZone"
            @add-item="addItem"
            @delete-item="deleteItem"
            @open="open"
            @close="close"
            @close-all="closeAll"
          />
        </div>
      </v-expand-transition>
    </v-card>

    <div v-if="inline" class="pa-1" style="position: relative">
      <v-overlay
        style="pointer-events: none"
        :model-value="errors.length !== 0"
        opacity="0.8"
        absolute
        attach
        scroll-strategy="none"
      />
      <v-btn
        v-show="errors.length !== 0"
        icon="mdi-alert"
        variant="text"
        density="compact"
        data-test="error-graph-icon"
        aria-label="Show Errors"
        @click="
          () => {
            errorDialog = true
          }
        "
      />
      <vertical-widget
        :key="screenKey"
        :widgets="layoutStack[0].widgets"
        :screen-values="screenValues"
        :screen-time-zone="timeZone"
        @add-item="addItem"
        @delete-item="deleteItem"
        @open="open"
        @close="close"
        @close-all="closeAll"
      />
    </div>

    <edit-screen-dialog
      v-if="editDialog"
      v-model="editDialog"
      :target="target"
      :screen="screen"
      :definition="currentDefinition"
      :keywords="keywords"
      :errors="errors"
      @save="saveEdit"
      @cancel="cancelEdit"
      @delete="deleteScreen"
    />

    <!-- Error dialog -->
    <v-dialog v-model="errorDialog" width="60vw">
      <v-toolbar height="24">
        <v-spacer />
        <span> Screen: {{ target }} {{ screen }} Errors </span>
        <v-spacer />
      </v-toolbar>
      <v-card>
        <v-textarea class="errors" readonly rows="13" :model-value="error" />
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import { uniqueId } from 'lodash'
import { Api, ConfigParserService, OpenC3Api } from '@openc3/js-common/services'
import WidgetComponents from '@/widgets/WidgetComponents'
import EditScreenDialog from './EditScreenDialog.vue'

const MAX_ERRORS = 20

export default {
  components: {
    EditScreenDialog,
  },
  mixins: [WidgetComponents],
  props: {
    target: {
      type: String,
      default: '',
    },
    screen: {
      type: String,
      default: '',
    },
    definition: {
      type: String,
      default: '',
    },
    keywords: {
      type: Array,
      default: () => [],
    },
    initialFloated: {
      type: Boolean,
      default: false,
    },
    initialTop: {
      type: Number,
      default: 0,
    },
    initialLeft: {
      type: Number,
      default: 0,
    },
    initialZ: {
      type: Number,
      default: 0,
    },
    minZ: {
      type: Number,
      default: 0,
    },
    fixFloated: {
      type: Boolean,
      default: false,
    },
    count: {
      type: Number,
      default: 0,
    },
    showClose: {
      type: Boolean,
      default: true,
    },
    timeZone: {
      type: String,
      default: 'local',
    },
    inline: {
      type: Boolean,
      default: false,
    },
  },
  emits: [
    'close-screen',
    'delete-screen',
    'drag-screen',
    'edit-screen',
    'float-screen',
    'min-max-screen',
    'unfloat-screen',
  ],
  data() {
    return {
      api: null,
      backup: '',
      currentDefinition: this.definition,
      editDialog: false,
      expand: true,
      configParser: null,
      configError: false,
      currentLayout: null,
      layoutStack: [],
      namedWidgets: {},
      dynamicWidgets: [],
      width: null,
      height: null,
      staleTime: 30,
      cacheTimeout: 0.1,
      globalSettings: [],
      substitute: false,
      original_target_name: null,
      force_substitute: false,
      pollingPeriod: 1,
      errors: [],
      errorDialog: false,
      screenKey: null,
      dragX: 0,
      dragY: 0,
      floated: this.initialFloated,
      top: this.initialTop,
      left: this.initialLeft,
      zIndex: this.initialZ,
      changeCounter: 0,
      screenItems: [],
      screenValues: {},
      updateCounter: 0,
      screenId: uniqueId('openc3-screen_'),
    }
  },
  computed: {
    error: function () {
      if (this.errorDialog && this.errors.length > 0) {
        let messages = new Set()
        let result = ''
        for (const error of this.errors) {
          if (messages.has(error.message)) {
            continue
          }
          let msg = `${error.time}: (${error.type}) ${error.message}\n`
          result += msg
          messages.add(error.message)
        }
        return result
      }
      return null
    },
    computedStyle() {
      let style = {}
      // note down what the width was in case it was set to AUTO, because absolute positioning will lose that
      const origWidth = this.width || this.$refs.bar?.clientWidth
      if (this.floated) {
        style['position'] = 'absolute'
        style['top'] = this.top + 'px'
        style['left'] = this.left + 'px'
        style['width'] = origWidth + 'px'
      }
      return style
    },
  },
  watch: {
    count: {
      handler(newValue, oldValue) {
        this.currentDefinition = this.definition
        this.rerender()
      },
    },
  },
  // Called when an error from any descendent component is captured
  // We need this because an error can occur from any of the children
  // in the widget stack and are typically thrown on create()
  errorCaptured(err, vm, info) {
    if (this.errors.length < MAX_ERRORS) {
      if (err.usage) {
        this.errors.push({
          type: 'usage',
          message: err.message,
          usage: err.usage,
          line: err.line,
          lineNumber: err.lineNumber,
          time: new Date().getTime(),
        })
      } else {
        this.errors.push({
          type: 'error',
          message: err,
          time: new Date().getTime(),
        })
      }
      // eslint-disable-next-line no-console
      console.log(this.errors)
      this.configError = true
    }
    return false
  },
  created() {
    this.api = new OpenC3Api()
    this.configParser = new ConfigParserService()
    this.parseDefinition()
    this.screenKey = Math.floor(Math.random() * 1000000)
  },
  mounted() {
    this.updateRefreshInterval()
    if (this.floated) {
      this.$refs.bar.onmousedown = this.dragMouseDown
      this.$refs.bar.parentElement.parentElement.style =
        'z-index: ' + this.zIndex
    }
  },
  unmounted() {
    if (this.updater != null) {
      clearInterval(this.updater)
      this.updater = null
    }
  },
  methods: {
    // These are API methods that ButtonWidget uses to open and close screens
    open(target, screen) {
      this.$parent.showScreen(target, screen)
    },
    close(target, screen) {
      this.$parent.closeScreenByName(target, screen)
    },
    closeAll() {
      this.$parent.closeAll()
    },
    clearErrors: function () {
      this.errors = []
      this.configError = false
    },
    updateRefreshInterval: function () {
      let refreshInterval = this.pollingPeriod * 1000
      if (this.updater) {
        clearInterval(this.updater)
      }
      this.updater = setInterval(() => {
        this.update()
      }, refreshInterval)
    },
    parseDefinition: function () {
      // Each time we start over and parse the screen definition
      this.clearErrors()
      this.screenItems = []
      this.namedWidgets = {}
      this.layoutStack = []
      this.dynamicWidgets = []
      // Every screen starts with a VerticalWidget
      this.layoutStack.push({
        type: 'VerticalWidget',
        parameters: [],
        widgets: [],
      })
      this.currentLayout = this.layoutStack[this.layoutStack.length - 1]

      this.configParser.parse_string(
        this.currentDefinition,
        '',
        false,
        true,
        (keyword, parameters, line, lineNumber) => {
          if (keyword) {
            switch (keyword) {
              case 'SCREEN':
                this.configParser.verify_num_parameters(
                  3,
                  4,
                  `${keyword} <Width or AUTO> <Height or AUTO> <Polling Period>`,
                )
                this.width = parseInt(parameters[0])
                this.height = parseInt(parameters[1])
                this.pollingPeriod = parseFloat(parameters[2])
                break
              case 'END':
                this.configParser.verify_num_parameters(0, 0, `${keyword}`)
                this.layoutStack.pop()
                this.currentLayout =
                  this.layoutStack[this.layoutStack.length - 1]
                break
              case 'STALE_TIME':
                this.configParser.verify_num_parameters(
                  1,
                  1,
                  `${keyword} <Time (s)>`,
                )
                this.staleTime = parseInt(parameters[0])
                break
              case 'SETTING':
              case 'SUBSETTING':
                const widget =
                  this.currentLayout.widgets[
                    this.currentLayout.widgets.length - 1
                  ] ?? this.currentLayout
                widget.settings.push(parameters)
                break
              case 'GLOBAL_SETTING':
              case 'GLOBAL_SUBSETTING':
                this.globalSettings.push(parameters)
                break
              default:
                this.processWidget(keyword, parameters, line, lineNumber)
                break
            } // switch keyword
          } // if keyword
        },
      )
      // This can happen if there is a typo in a layout widget with a corresponding END
      if (typeof this.layoutStack[0] === 'undefined') {
        let names = []
        let lines = []
        for (const widget of this.dynamicWidgets) {
          names.push(widget.name)
          lines.push(widget.lineNumber)
        }
        // Warn about any of the Dynamic widgets we found .. they could be typos
        if (this.errors.length < MAX_ERRORS) {
          this.errors.push({
            type: 'usage',
            message: `Unknown widget! Are these widgets: ${names.join(',')}?`,
            lineNumber: lines.join(','),
            time: new Date().getTime(),
          })
          this.configError = true
        }
        // Create a simple VerticalWidget to replace the bad widget so
        // the layout stack can successfully unwind
        this.layoutStack[0] = {
          type: 'VerticalWidget',
          parameters: [],
          widgets: [],
        }
      } else {
        this.applyGlobalSettings(this.layoutStack[0].widgets)
      }
    },
    openEdit: function () {
      // Make a copy in case they edit and cancel
      this.backup = this.currentDefinition.repeat(1)
      this.editDialog = true
    },
    upScreen: function () {
      this.zIndex += 1
      this.$refs.bar.parentElement.parentElement.style =
        'z-index: ' + this.zIndex
      this.$emit('drag-screen', [
        this.floated,
        this.top,
        this.left,
        this.zIndex,
      ])
    },
    downScreen: function () {
      if (this.zIndex > this.minZ) {
        this.zIndex -= 1
        this.$refs.bar.parentElement.parentElement.style =
          'z-index: ' + this.zIndex
        this.$emit('drag-screen', [
          this.floated,
          this.top,
          this.left,
          this.zIndex,
        ])
      }
    },
    floatScreen: function () {
      if (this.floated) {
        this.$refs.bar.onmousedown = null
        this.$refs.bar.parentElement.parentElement.style = 'z-index: 0'
        this.floated = false
        this.$emit('unfloat-screen', [
          this.floated,
          this.top,
          this.left,
          this.zIndex,
        ])
      } else {
        let bodyRect =
          this.$refs.bar.parentElement.parentElement.parentElement.getBoundingClientRect()
        let elemRect = this.$refs.bar.getBoundingClientRect()
        this.top = elemRect.top - bodyRect.top - 5
        this.left = elemRect.left - bodyRect.left - 5
        this.$refs.bar.onmousedown = this.dragMouseDown
        this.$refs.bar.parentElement.parentElement.style =
          'z-index: ' + this.zIndex
        this.floated = true
        this.$emit('float-screen', [
          this.floated,
          this.top,
          this.left,
          this.zIndex,
        ])
      }
    },
    dragMouseDown: function (e) {
      e = e || window.event
      e.preventDefault()
      // get the mouse cursor position at startup:
      this.dragX = e.clientX
      this.dragY = e.clientY
      document.onmouseup = this.closeDragElement
      // call a function whenever the cursor moves:
      document.onmousemove = this.elementDrag
    },
    elementDrag: function (e) {
      e = e || window.event
      e.preventDefault()
      // calculate the new cursor position:
      let xOffset = this.dragX - e.clientX
      let yOffset = this.dragY - e.clientY
      this.dragX = e.clientX
      this.dragY = e.clientY
      // set the element's new position:
      this.top = this.$refs.bar.offsetTop - yOffset
      this.left = this.$refs.bar.offsetLeft - xOffset
      this.$emit('drag-screen', [
        this.floated,
        this.top,
        this.left,
        this.zIndex,
      ])
    },
    closeDragElement: function () {
      // stop moving when mouse button is released:
      document.onmouseup = null
      document.onmousemove = null
    },
    rerender: function () {
      this.parseDefinition()
      this.updateRefreshInterval()
      // Force re-render
      this.screenKey = Math.floor(Math.random() * 1000000)
      // After re-render clear any errors
      this.$nextTick(function () {
        this.clearErrors()
        this.$emit('edit-screen')
      })
    },
    cancelEdit: function () {
      this.file = null
      this.editDialog = false
      // Restore the backup since we cancelled
      this.currentDefinition = this.backup
      this.rerender()
    },
    saveEdit: function (definition) {
      this.editDialog = false
      this.currentDefinition = definition
      this.rerender()
      this.$nextTick(function () {
        Api.post(
          '/openc3-api/screen/',
          {
            data: {
              scope: window.openc3Scope,
              target: this.target,
              screen: this.screen,
              text: this.currentDefinition,
            },
          },
          0,
        )
      })
    },
    deleteScreen: function () {
      this.editDialog = false
      Api.delete(`/openc3-api/screen/${this.target}/${this.screen}`).then(
        (response) => {
          this.$emit('delete-screen')
        },
      )
    },
    minMaxTransition: function () {
      this.expand = !this.expand
      this.$emit('min-max-screen')
    },
    processWidget: function (keyword, parameters, line, lineNumber) {
      let widgetName = null
      if (keyword === 'NAMED_WIDGET') {
        this.configParser.verify_num_parameters(
          2,
          null,
          `${keyword} <Widget Name> <Widget Type> <Widget Settings... (optional)>`,
        )
        widgetName = parameters[0].toUpperCase()
        keyword = parameters[1].toUpperCase()
        parameters = parameters.slice(2, parameters.length)
      }
      const componentName =
        keyword.charAt(0).toUpperCase() +
        keyword.slice(1).toLowerCase() +
        'Widget'
      let settings = []
      // Give all the widgets a reference to this screen
      // Use settings so we don't break existing custom widgets
      settings.push(['__SCREEN_ID__', this.screenId])
      if (widgetName !== null) {
        // Push a reference to the screen so the layout can register when it is created
        // We do this because the widget isn't actually created until
        // the layout happens with <component :is='type'>
        settings.push(['NAMED_WIDGET', widgetName])
      }
      // If this is a layout widget we add it to the layoutStack and reset the currentLayout
      if (
        keyword === 'VERTICAL' ||
        keyword === 'VERTICALBOX' ||
        keyword === 'HORIZONTAL' ||
        keyword === 'HORIZONTALBOX' ||
        keyword === 'MATRIXBYCOLUMNS' ||
        keyword === 'TABBOOK' ||
        keyword === 'TABITEM' ||
        keyword === 'CANVAS' ||
        keyword === 'RADIOGROUP' ||
        keyword === 'SCROLLWINDOW'
      ) {
        const layout = {
          type: componentName,
          parameters: parameters,
          settings: settings,
          screenValues: this.screenValues,
          screenTimeZone: this.timeZone,
          widgets: [],
        }
        this.layoutStack.push(layout)
        this.currentLayout.widgets.push(layout)
        this.currentLayout = layout
      } else if (this.$options.components[componentName]) {
        this.currentLayout.widgets.push({
          type: componentName,
          target: this.target,
          parameters: parameters,
          settings: settings,
          screenValues: this.screenValues,
          screenTimeZone: this.timeZone,
          line: line,
          lineNumber: lineNumber,
        })
      } else {
        let widget = {
          type: 'DynamicWidget',
          target: this.target,
          parameters: parameters,
          settings: settings,
          screenValues: this.screenValues,
          screenTimeZone: this.timeZone,
          name: componentName,
          line: line,
          lineNumber: lineNumber,
        }
        this.currentLayout.widgets.push(widget)
        this.dynamicWidgets.push(widget)
      }
    },
    applyGlobalSettings: function (widgets) {
      widgets.forEach((widget) => {
        this.globalSettings.forEach((setting) => {
          // widget.type is already the full camelcase widget name like LabelWidget
          // so we have to lower case both and tack on 'widget' to compare
          if (
            widget.type.toLowerCase() ===
            setting[0].toLowerCase() + 'widget'
          ) {
            const existingSetting = widget.settings.find(
              (s) => s[0] === setting[1],
            )
            if (!existingSetting) {
              widget.settings.push(setting.slice(1))
            }
          }
        })
        // Recursively apply to all widgets contained in layouts
        if (widget.widgets) {
          this.applyGlobalSettings(widget.widgets)
        }
      })
    },
    update: function () {
      if (this.screenItems.length !== 0 && this.configError === false) {
        this.api
          .get_tlm_values(this.screenItems, this.staleTime, this.cacheTimeout)
          .then((data) => {
            this.clearErrors()
            this.updateValues(data)
          })
          .catch((error) => {
            let message = JSON.stringify(error, null, 2)
            // Anything other than 'no response received' which means the API server is down
            // is an error the user needs to fix so don't request values until they do
            if (!message.includes('no response received')) {
              this.configError = true
            }
            if (
              !this.errors.find((existing) => {
                return existing.message === message
              })
            ) {
              if (this.errors.length < MAX_ERRORS) {
                this.errors.push({
                  type: 'error',
                  message: message,
                  time: new Date().getTime(),
                })
              }
            }
          })
      }
    },
    updateValues: function (values) {
      this.updateCounter += 1
      for (let i = 0; i < values.length; i++) {
        values[i].push(this.updateCounter)
        this.screenValues[this.screenItems[i]] = values[i]
      }
    },
    addItem: function (valueId) {
      this.screenItems.push(valueId)
      this.screenValues[valueId] = [null, null, 0]
    },
    deleteItem: function (valueId) {
      let index = this.screenItems.indexOf(valueId)
      this.screenItems.splice(index, 1)
    },
  },
}
</script>

<style scoped>
.errors {
  padding-top: 0px;
  margin-top: 0px;
}

.v-textarea :deep(textarea) {
  padding: 5px;
  -webkit-mask-image: unset;
  mask-image: unset;
}
</style>
