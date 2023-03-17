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
# All changes Copyright 2022, OpenC3, Inc.
# All Rights Reserved
#
# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
#
# This screen expects to be inside of two parent elements.
# An overall item, and then a container for all screens
-->

<template>
  <div :style="computedStyle" ref="bar">
    <v-card :min-height="height" :min-width="width">
      <v-system-bar>
        <div v-show="errors.length !== 0">
          <v-tooltip top>
            <template v-slot:activator="{ on, attrs }">
              <div v-on="on" v-bind="attrs">
                <v-icon
                  data-test="error-graph-icon"
                  @click="errorDialog = true"
                >
                  mdi-alert
                </v-icon>
              </div>
            </template>
            <span> Errors </span>
          </v-tooltip>
        </div>
        <v-tooltip top>
          <template v-slot:activator="{ on, attrs }">
            <div v-on="on" v-bind="attrs">
              <v-icon data-test="edit-screen-icon" @click="openEdit">
                mdi-pencil
              </v-icon>
            </div>
          </template>
          <span> Edit Screen </span>
        </v-tooltip>
        <v-tooltip top>
          <template v-slot:activator="{ on, attrs }">
            <div v-on="on" v-bind="attrs">
              <v-icon data-test="float-screen-icon" @click="floatScreen">
                {{ floated ? 'mdi-airplane-off' : 'mdi-airplane' }}
              </v-icon>
            </div>
          </template>
          <span> {{ floated ? 'Unfloat Screen' : 'Float Screen' }} </span>
        </v-tooltip>
        <v-tooltip top v-if="floated">
          <template v-slot:activator="{ on, attrs }">
            <div v-on="on" v-bind="attrs">
              <v-icon data-test="up-screen-icon" @click="upScreen">
                mdi-arrow-up
              </v-icon>
            </div>
          </template>
          <span> Move Screen Up </span>
        </v-tooltip>
        <v-tooltip top v-if="floated && zIndex > 0">
          <template v-slot:activator="{ on, attrs }">
            <div v-on="on" v-bind="attrs">
              <v-icon data-test="down-screen-icon" @click="downScreen">
                mdi-arrow-down
              </v-icon>
            </div>
          </template>
          <span> Move Screen Down </span>
        </v-tooltip>
        <v-spacer />
        <span>{{ target }} {{ screen }}</span>
        <v-spacer />
        <v-tooltip top>
          <template v-slot:activator="{ on, attrs }">
            <div v-on="on" v-bind="attrs">
              <v-icon
                data-test="minimize-screen-icon"
                @click="minMaxTransition"
                v-show="expand"
              >
                mdi-window-minimize
              </v-icon>
              <v-icon
                data-test="maximize-screen-icon"
                @click="minMaxTransition"
                v-show="!expand"
              >
                mdi-window-maximize
              </v-icon>
            </div>
          </template>
          <span v-show="expand"> Minimize Screen </span>
          <span v-show="!expand"> Maximize Screen </span>
        </v-tooltip>
        <v-tooltip top>
          <template v-slot:activator="{ on, attrs }">
            <div v-on="on" v-bind="attrs">
              <v-icon
                data-test="close-screen-icon"
                @click="$emit('close-screen')"
              >
                mdi-close-box
              </v-icon>
            </div>
          </template>
          <span> Close Screen </span>
        </v-tooltip>
      </v-system-bar>
      <v-expand-transition v-if="!editDialog">
        <div class="pa-1" ref="screen" v-show="expand">
          <vertical-widget
            :key="screenKey"
            :widgets="layoutStack[0].widgets"
            v-on="$listeners"
          />
        </div>
      </v-expand-transition>
    </v-card>
    <edit-screen-dialog
      v-if="editDialog"
      v-model="editDialog"
      :target="target"
      :screen="screen"
      :definition="currentDefinition"
      :keywords="keywords"
      :errors="errors"
      @save="saveEdit($event)"
      @cancel="cancelEdit()"
      @delete="deleteScreen()"
    />

    <!-- Error dialog -->
    <v-dialog v-model="errorDialog" max-width="600">
      <v-system-bar>
        <v-spacer />
        <span> Screen: {{ target }} {{ screen }} Errors </span>
        <v-spacer />
      </v-system-bar>
      <v-card class="pa-3">
        <v-row class="my-3">
          <v-textarea readonly rows="13" :value="error" />
        </v-row>
        <v-row>
          <v-btn block @click="clearErrors"> Clear </v-btn>
        </v-row>
      </v-card>
    </v-dialog>
  </div>
</template>

<script>
import Api from '../services/api'
import { ConfigParserService } from '../services/config-parser'
import { OpenC3Api } from '../services/openc3-api'
import Vue from 'vue'
import upperFirst from 'lodash/upperFirst'
import camelCase from 'lodash/camelCase'
import EditScreenDialog from './EditScreenDialog'

// Globally register all XxxWidget.vue components
const requireComponent = require.context(
  // The relative path of the components folder
  '@openc3/tool-common/src/components/widgets',
  // Whether or not to look in subfolders
  false,
  // The regular expression used to match base component filenames
  /[A-Z][a-z]+Widget\.vue$/
)

requireComponent.keys().forEach((filename) => {
  // Get component config
  const componentConfig = requireComponent(filename)
  // Get PascalCase name of component
  const componentName = upperFirst(
    camelCase(
      // Gets the filename regardless of folder depth
      filename
        .split('/')
        .pop()
        .replace(/\.\w+$/, '')
    )
  )
  // Register component globally
  Vue.component(
    componentName,
    // Look for the component options on `.default`, which will
    // exist if the component was exported with `export default`,
    // otherwise fall back to module's root.
    componentConfig.default || componentConfig
  )
})

export default {
  components: {
    EditScreenDialog,
  },
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
  },
  data() {
    return {
      api: null,
      backup: '',
      currentDefinition: this.definition,
      editDialog: false,
      expand: true,
      configParser: null,
      currentLayout: null,
      layoutStack: [],
      namedWidgets: {},
      dynamicWidgets: [],
      width: null,
      height: null,
      staleTime: 30,
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
      if (this.floated) {
        style['position'] = 'absolute'
        style['top'] = this.top + 'px'
        style['left'] = this.left + 'px'
      }
      return style
    },
  },
  // Called when an error from any descendent component is captured
  // We need this because an error can occur from any of the children
  // in the widget stack and are typically thrown on create()
  errorCaptured(err, vm, info) {
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
        message: `${err}`,
        time: new Date().getTime(),
      })
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
  destroyed() {
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
      this.errors = []
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
                  `${keyword} <Width or AUTO> <Height or AUTO> <Polling Period>`
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
                  `${keyword} <Time (s)>`
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
        }
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
        this.errors.push({
          type: 'usage',
          message: `Unknown widget! Are these widgets: ${names.join(',')}?`,
          lineNumber: lines.join(','),
          time: new Date().getTime(),
        })
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
    // Called by button scripts to get named widgets
    getNamedWidget: function (name) {
      return this.namedWidgets[name]
    },
    // TODO: Deprecate underscores used to match OpenC3 API rather than Javascript convention?
    get_named_widget: function (name) {
      return this.namedWidgets[name]
    },
    // Called by named widgets to register with the screen
    setNamedWidget: function (name, widget) {
      this.namedWidgets[name] = widget
    },
    update: function () {
      if (
        this.$store.state.tlmViewerItems.length !== 0 &&
        this.errors.length === 0
      ) {
        this.api
          .get_tlm_values(this.$store.state.tlmViewerItems, this.staleTime)
          .then((data) => {
            this.$store.commit('tlmViewerUpdateValues', data)
          })
          .catch((error) => {
            this.errors.push({
              type: 'usage',
              message: error.message,
              time: new Date().getTime(),
            })
          })
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
      if (this.zIndex > 0) {
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
    cancelEdit: function () {
      this.file = null
      this.editDialog = false
      // Restore the backup since we cancelled
      this.currentDefinition = this.backup
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
    saveEdit: function (definition) {
      this.currentDefinition = definition
      this.parseDefinition()
      this.updateRefreshInterval()
      // Force re-render
      this.screenKey = Math.floor(Math.random() * 1000000)
      // After re-render wait and see if there are errors before saving
      this.$nextTick(function () {
        Api.post('/openc3-api/screen/', {
          data: {
            scope: window.openc3Scope,
            target: this.target,
            screen: this.screen,
            text: this.currentDefinition,
          },
        })
        this.editDialog = false
        this.$emit('edit-screen')
      })
    },
    deleteScreen: function () {
      this.editDialog = false
      Api.delete(`/openc3-api/screen/${this.target}/${this.screen}`).then(
        (response) => {
          this.$emit('delete-screen')
        }
      )
    },
    minMaxTransition: function () {
      this.expand = !this.expand
      this.$emit('min-max-screen')
    },
    processWidget: function (keyword, parameters, line, lineNumber) {
      var widgetName = null
      if (keyword === 'NAMED_WIDGET') {
        this.configParser.verify_num_parameters(
          2,
          null,
          `${keyword} <Widget Name> <Widget Type> <Widget Settings... (optional)>`
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
      if (widgetName !== null) {
        // Push a reference to the screen so the layout can register when it is created
        // We do this because the widget isn't actually created until
        // the layout happens with <component :is='type'>
        settings.push(['NAMED_WIDGET', widgetName, this])
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
          widgets: [],
        }
        this.layoutStack.push(layout)
        this.currentLayout.widgets.push(layout)
        this.currentLayout = layout
      } else {
        // Buttons require a reference to the screen to call get_named_widget
        // Canvas items can open other screens when clicked
        if (keyword.includes('BUTTON') || keyword.includes('CANVAS')) {
          // Give it a unique name to avoid name collisions
          settings.push(['__SCREEN__', this])
        }
        if (Vue.options.components[componentName]) {
          this.currentLayout.widgets.push({
            type: componentName,
            target: this.target,
            parameters: parameters,
            settings: settings,
            line: line,
            lineNumber: lineNumber,
          })
        } else {
          let widget = {
            type: 'DynamicWidget',
            target: this.target,
            parameters: parameters,
            settings: settings,
            name: componentName,
            line: line,
            lineNumber: lineNumber,
          }
          this.currentLayout.widgets.push(widget)
          this.dynamicWidgets.push(widget)
        }
      }
    },
    applyGlobalSettings: function (widgets) {
      this.globalSettings.forEach((setting) => {
        widgets.forEach((widget) => {
          // widget.type is already the full camelcase widget name like LabelWidget
          // so we have to lower case both and tack on 'widget' to compare
          if (
            widget.type.toLowerCase() ===
            setting[0].toLowerCase() + 'widget'
          ) {
            widget.settings.push(setting.slice(1))
          }
          // Recursively apply to all widgets contained in layouts
          if (widget.widgets) {
            this.applyGlobalSettings(widget.widgets)
          }
        })
      })
    },
  },
}
</script>

<style scoped>
.v-card {
  background-color: var(--v-tertiary-darken2);
}
.v-textarea :deep(textarea) {
  padding: 5px;
  background-color: var(--v-tertiary-darken1) !important;
}
</style>
