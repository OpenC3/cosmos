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
    <v-card flat class="tab-card">
      <v-tabs
        v-model="activeTab"
        bg-color="var(--color-background-base-default)"
      >
        <v-tab value="running">Running Scripts</v-tab>
        <v-tab value="completed">Completed Scripts</v-tab>
      </v-tabs>
      <v-window v-model="activeTab">
        <!-- Running Scripts Tab -->
        <v-window-item value="running">
          <v-card-title>
            <v-row dense>
              <v-spacer />
              <v-btn class="mr-3" color="primary" @click="getRunningScripts">
                Refresh
              </v-btn>
              <v-text-field
                v-model="runningSearch"
                class="pt-0 search"
                label="Search"
                prepend-inner-icon="mdi-magnify"
                clearable
                variant="outlined"
                density="compact"
                single-line
                hide-details
                data-test="running-search"
                style="max-width: 300px"
              />
            </v-row>
          </v-card-title>

          <v-data-table-server
            :headers="runningHeaders"
            :items="runningScripts"
            :items-length="runningTotal"
            :loading="runningLoading"
            disable-sort
            density="compact"
            data-test="running-scripts"
            :items-per-page="runningItemsPerPage"
            :page="runningPage"
            :items-per-page-options="[10, 25, 50]"
            class="script-table"
            @update:page="updateRunningPage"
            @update:items-per-page="updateRunningItemsPerPage"
          >
            <template #item.name="{ item }">
              <v-btn
                color="primary"
                density="comfortable"
                @click="showScript(item)"
              >
                {{ item.name }}
              </v-btn>
            </template>
            <template #item.connect="{ item }">
              <v-btn color="primary" @click="connectScript(item)">
                <span>Connect</span>
                <v-icon v-show="connectInNewTab" end> mdi-open-in-new </v-icon>
              </v-btn>
            </template>
            <template #item.user_full_name="{ item }">
              {{ formatUserDisplay(item) }}
            </template>
            <template #item.start_time="{ item }">
              {{ formatStartTime(item) }}
            </template>
            <template #item.duration="{ item }">
              {{ formatDuration(item) }}
            </template>
            <template #item.stop="{ item }">
              <v-btn color="primary" @click="deleteScript(item)">
                <span>Stop</span>
                <v-icon end> mdi-close-circle-outline </v-icon>
              </v-btn>
            </template>
          </v-data-table-server>
        </v-window-item>

        <!-- Completed Scripts Tab -->
        <v-window-item value="completed">
          <v-card-title>
            <v-row dense>
              <v-spacer />
              <v-btn class="mr-3" color="primary" @click="getCompletedScripts">
                Refresh
              </v-btn>
              <v-text-field
                v-model="completedSearch"
                class="pt-0 search"
                label="Search"
                prepend-inner-icon="mdi-magnify"
                clearable
                variant="outlined"
                density="compact"
                single-line
                hide-details
                style="max-width: 300px"
              />
            </v-row>
          </v-card-title>

          <v-data-table-server
            :headers="completedHeaders"
            :items="completedScripts"
            :items-length="completedTotal"
            :loading="completedLoading"
            disable-sort
            density="compact"
            data-test="completed-scripts"
            :items-per-page="completedItemsPerPage"
            :page="completedPage"
            :items-per-page-options="[10, 25, 50]"
            class="script-table"
            @update:page="updateCompletedPage"
            @update:items-per-page="updateCompletedItemsPerPage"
          >
            <template #item.name="{ item }">
              <v-btn
                color="primary"
                density="comfortable"
                @click="showScript(item)"
              >
                {{ item.name }}
              </v-btn>
            </template>
            <template #item.user_full_name="{ item }">
              {{ formatUserDisplay(item) }}
            </template>
            <template #item.start_time="{ item }">
              {{ formatStartTime(item) }}
            </template>
            <template #item.duration="{ item }">
              {{ formatDuration(item) }}
            </template>
            <template #item.log="{ item }">
              <v-btn
                color="primary"
                density="comfortable"
                icon="mdi-eye"
                :disabled="!item.log"
                @click="viewScriptLog(item, 'log')"
              />
              <v-btn
                color="primary"
                density="comfortable"
                icon="mdi-file-download-outline"
                :disabled="downloadScript || !item.log"
                :loading="downloadScript && downloadScript.name === item.name"
                @click="downloadScriptLog(item, 'log')"
              />
            </template>
            <template #item.report="{ item }">
              <div v-if="!item.report">
                <span>N/A</span>
              </div>
              <div v-else>
                <v-btn
                  color="primary"
                  density="comfortable"
                  icon="mdi-eye"
                  @click="viewScriptLog(item, 'report')"
                />
                <v-menu>
                  <template #activator="{ props: activatorProps }">
                    <v-btn
                      color="primary"
                      density="comfortable"
                      icon="mdi-file-download-outline"
                      :disabled="downloadScript"
                      :loading="
                        downloadScript && downloadScript.name === item.name
                      "
                      v-bind="activatorProps"
                    />
                  </template>
                  <v-list>
                    <v-list-item
                      @click="downloadScriptLog(item, 'report', 'text')"
                    >
                      <v-list-item-title>Download as Text</v-list-item-title>
                    </v-list-item>
                    <v-list-item
                      @click="downloadScriptLog(item, 'report', 'ctrf')"
                    >
                      <v-list-item-title>Download as CTRF</v-list-item-title>
                    </v-list-item>
                  </v-list>
                </v-menu>
              </div>
            </template>
          </v-data-table-server>
        </v-window-item>
      </v-window>
    </v-card>

    <output-dialog
      v-if="showDialog"
      v-model="showDialog"
      :content="dialogContent"
      type="Script"
      :name="dialogName"
      :filename="dialogFilename"
      @submit="showDialog = false"
    />
  </div>
</template>

<script setup>
import { ref, watch, onMounted, onBeforeUnmount, inject } from 'vue'
import { debounce } from 'lodash'
import { useRouter } from 'vue-router'
import { Api, OpenC3Api } from '@openc3/js-common/services'
import { OutputDialog } from '@/components'
import { TimeFilters } from '@/util'

const props = defineProps({
  tabId: {
    type: Number,
    default: null,
  },
  curTab: {
    type: Number,
    default: null,
  },
  connectInNewTab: Boolean,
})

const emit = defineEmits(['disconnect', 'close'])

const router = useRouter()
const notify = inject('notify')
const dialog = inject('dialog')
const { formatDateTimeHMS } = TimeFilters.methods

const api = new OpenC3Api()
const timeZone = ref('local')
const activeTab = ref('completed')
const downloadScript = ref(null)
const refreshTimer = ref(null)

// Running and completed scripts share identical pagination/search/fetch
// behavior, differing only by endpoint and error message, so both are backed
// by the same factory.
function useScriptTable(endpoint, errorTitle) {
  const search = ref('')
  const scripts = ref([])
  const total = ref(0)
  const loading = ref(false)
  const page = ref(1)
  const itemsPerPage = ref(10)

  async function fetchScripts() {
    loading.value = true
    const offset = (page.value - 1) * itemsPerPage.value
    const searchParam = encodeURIComponent(search.value || '')
    try {
      const { data } = await Api.get(
        `${endpoint}?scope=DEFAULT&offset=${offset}&limit=${itemsPerPage.value}&search=${searchParam}`,
      )
      scripts.value = data.items || []
      total.value = data.total || scripts.value.length
    } catch (error) {
      notify.caution({ title: errorTitle, body: error.message })
    } finally {
      loading.value = false
    }
  }

  function setPage(newPage) {
    page.value = newPage
    fetchScripts()
  }

  function setItemsPerPage(newItemsPerPage) {
    itemsPerPage.value = newItemsPerPage
    page.value = 1
    fetchScripts()
  }

  // Debounce search so we refetch from the server after the user stops typing.
  // Reset to the first page since the filtered result set changes.
  watch(
    search,
    debounce(() => {
      page.value = 1
      fetchScripts()
    }, 300),
  )

  // Return refs (not reactive) so they can be destructured into named bindings
  // without losing reactivity.
  return {
    search,
    scripts,
    total,
    loading,
    page,
    itemsPerPage,
    fetchScripts,
    setPage,
    setItemsPerPage,
  }
}

const {
  search: runningSearch,
  scripts: runningScripts,
  total: runningTotal,
  loading: runningLoading,
  page: runningPage,
  itemsPerPage: runningItemsPerPage,
  fetchScripts: getRunningScripts,
  setPage: updateRunningPage,
  setItemsPerPage: updateRunningItemsPerPage,
} = useScriptTable(
  '/script-api/running-script',
  'Error Loading Running Scripts',
)

const {
  search: completedSearch,
  scripts: completedScripts,
  total: completedTotal,
  loading: completedLoading,
  page: completedPage,
  itemsPerPage: completedItemsPerPage,
  fetchScripts: getCompletedScripts,
  setPage: updateCompletedPage,
  setItemsPerPage: updateCompletedItemsPerPage,
} = useScriptTable(
  '/script-api/completed-scripts',
  'Error Loading Completed Scripts',
)

// Columns shared by both tables; each table adds its own action columns.
// Sorting is disabled table-wide (disable-sort) since the API doesn't support it.
const coreHeaders = [
  { title: 'Id', key: 'name' },
  { title: 'User', key: 'user_full_name' },
  { title: 'Filename', key: 'filename' },
  { title: 'Start Time', key: 'start_time' },
  { title: 'Duration', key: 'duration' },
  { title: 'State', key: 'state' },
]
const runningHeaders = [
  { title: 'Connect', key: 'connect', filterable: false },
  ...coreHeaders,
  { title: 'Stop', key: 'stop', filterable: false },
]
const completedHeaders = [
  ...coreHeaders,
  { title: 'Log', key: 'log', filterable: false },
  { title: 'Report', key: 'report', filterable: false },
]

const showDialog = ref(false)
const dialogName = ref('')
const dialogContent = ref('')
const dialogFilename = ref('')

watch(activeTab, (newTab) => {
  if (newTab === 'running') {
    getRunningScripts()
  } else if (newTab === 'completed') {
    getCompletedScripts()
  }
})

onMounted(async () => {
  try {
    const response = await api.get_setting('time_zone')
    if (response) {
      timeZone.value = response
    }
  } catch (error) {
    // Do nothing
  }

  getRunningScripts()
  getCompletedScripts()

  // Start a timer to refresh the running scripts list every 5 seconds
  refreshTimer.value = setInterval(() => {
    if (activeTab.value === 'running') {
      getRunningScripts()
    }
  }, 5000)
})

onBeforeUnmount(() => {
  // Clear the timer when component is unmounted
  if (refreshTimer.value) {
    clearInterval(refreshTimer.value)
  }
})

// Display-only formatters used by the data table item slots. Keeping these out
// of the fetch keeps the API response unmodified and lets start time react to
// the time zone setting (which loads asynchronously after the first fetch).
function formatUserDisplay(item) {
  return `${item.user_full_name} (${item.username})`
}

function formatStartTime(item) {
  if (!item.start_time) {
    return 'N/A'
  }
  return formatDateTimeHMS(new Date(item.start_time), timeZone.value)
}

function formatDuration(item) {
  if (!item.start_time) {
    return 'N/A'
  }
  const startTime = new Date(item.start_time)
  // Running scripts have no end_time, so measure against the current time
  const endTime = item.end_time ? new Date(item.end_time) : new Date()
  return formatDurationMs(endTime - startTime)
}

function formatDurationMs(durationMs) {
  if (durationMs < 0) {
    return 'N/A'
  } else if (durationMs < 1000) {
    return '< 1s'
  } else if (durationMs < 60000) {
    return `${Math.round(durationMs / 1000)}s`
  } else if (durationMs < 3600000) {
    const minutes = Math.floor(durationMs / 60000)
    const seconds = Math.round((durationMs % 60000) / 1000)
    return `${minutes}m ${seconds}s`
  } else {
    const hours = Math.floor(durationMs / 3600000)
    const minutes = Math.floor((durationMs % 3600000) / 60000)
    const seconds = Math.round((durationMs % 60000) / 1000)
    return `${hours}h ${minutes}m ${seconds}s`
  }
}

function showScript(script) {
  dialogContent.value = JSON.stringify(script, null, 2)
  dialogName.value = 'Script: ' + script.name
  dialogFilename.value = ''
  showDialog.value = true
}

function connectScript(script) {
  // Must disconnect before connecting
  emit('disconnect')
  const destination = {
    name: 'ScriptRunner',
    params: { id: script.name },
  }
  if (props.connectInNewTab) {
    const { href } = router.resolve(destination)
    window.open(href, '_blank')
  } else {
    router.push(destination)
    emit('close')
  }
}

async function deleteScript(script) {
  try {
    await dialog.confirm(
      `Are you sure you want to stop script: ${script.name} ${script.filename}?\n`,
      {
        okText: 'Stop',
        cancelText: 'Cancel',
      },
    )
    await Api.post(`/script-api/running-script/${script.name}/delete`)
    notify.normal({
      body: `Stopped script: ${script.name} ${script.filename}`,
    })
    getRunningScripts()
  } catch (error) {
    if (error !== true) {
      notify.caution({
        body: `Failed to stop script: ${script.name} ${script.filename}`,
      })
    }
  }
}

async function viewScriptLog(script, type) {
  let logUrl = null
  if (type === 'report') {
    dialogName.value = 'Report'
    logUrl = script.report
  } else {
    dialogName.value = 'Log'
    logUrl = script.log
  }
  if (!logUrl) {
    notify.caution({
      title: `No ${dialogName.value.toLowerCase()} available`,
      body: `Script ${script.name} has no ${dialogName.value.toLowerCase()} file yet.`,
    })
    return
  }
  const response = await Api.get(
    `/openc3-api/storage/download_file/${encodeURIComponent(
      logUrl,
    )}?bucket=OPENC3_LOGS_BUCKET`,
  )
  const filenameParts = logUrl.split('/')
  dialogFilename.value = filenameParts[filenameParts.length - 1]
  // Decode Base64 string
  dialogContent.value = window.atob(response.data.contents)
  showDialog.value = true
}

async function downloadScriptLog(script, type, format = 'text') {
  let logUrl = null
  if (type === 'report') {
    dialogName.value = 'Report'
    logUrl = script.report
  } else {
    dialogName.value = 'Log'
    logUrl = script.log
  }
  if (!logUrl) {
    notify.caution({
      title: `No ${dialogName.value.toLowerCase()} available`,
      body: `Script ${script.name} has no ${dialogName.value.toLowerCase()} file yet.`,
    })
    return
  }
  downloadScript.value = script

  try {
    if (format === 'ctrf' && type === 'report') {
      // For CTRF format, pass format parameter to backend for conversion
      const response = await Api.get(
        `/openc3-api/storage/download_file/${encodeURIComponent(
          logUrl,
        )}?bucket=OPENC3_LOGS_BUCKET&format=ctrf`,
      )
      // Backend returns the converted CTRF content
      const blob = new Blob([window.atob(response.data.contents)], {
        type: 'application/json',
      })
      const link = document.createElement('a')
      link.href = URL.createObjectURL(blob)
      link.setAttribute('download', response.data.filename)
      link.click()
      downloadScript.value = null
    } else {
      // Original download functionality for text format
      const response = await Api.get(
        `/openc3-api/storage/download/${encodeURIComponent(
          logUrl,
        )}?bucket=OPENC3_LOGS_BUCKET`,
      )
      const filenameParts = logUrl.split('/')
      const basename = filenameParts[filenameParts.length - 1]
      // Make a link and then 'click' on it to start the download
      const link = document.createElement('a')
      link.href = response.data.url
      link.setAttribute('download', basename)
      link.click()
      downloadScript.value = null
    }
  } catch {
    notify.caution({
      title: `Unable to download log ${logUrl}`,
      body: `You may be able to download this log manually from the 'logs' bucket at ${logUrl}`,
    })
    downloadScript.value = null
  }
}
</script>
<style>
.v-sheet {
  background-color: var(--color-background-base-default);
}
</style>
