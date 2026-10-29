/*
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
*/

import { computed, nextTick, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Api } from '@openc3/js-common/services'
import { readString, writeString } from './storage'
import {
  dashboardUrl,
  fetchDashboardText,
  forget,
  remember,
} from '../navigator/navigatorStore'
import { clearCommandCache } from '../panels/commandParams'
import {
  emptyDashboard,
  parseDashboard,
  serializeDashboard,
} from '../dashboardParser'

const LAST_KEY = 'dashboards__last'

// 'TARGET/NAME' from the page URL, or null when it doesn't name one
export function routeKey({ target, dashboard }) {
  return target && dashboard
    ? `${target.toUpperCase()}/${dashboard.toUpperCase()}`
    : null
}

// The saved dashboards and the one showing: listing, opening, saving,
// creating, duplicating and deleting them, and keeping the URL and
// reopen-on-launch on the dashboard that's showing. model and editing are
// the page's; history is useDashboardHistory, told when the model matches
// the saved file. confirmDiscard() resolves false when unsaved edits should
// stay; startEditing() is called on a new dashboard.
export function useDashboardFile({
  model,
  editing,
  history,
  notify,
  ask,
  confirmDiscard,
  startEditing,
  // Optional: resolves when a just loaded dashboard has its first values
  firstValues = () => Promise.resolve(),
}) {
  const route = useRoute()
  const router = useRouter()

  const dashboards = ref([])
  // The name of the dashboard being opened, for the loading screen; null
  // once it's showing
  const opening = ref(null)
  let openRequest = 0
  const current = ref(null) // { target, name }
  // The text last saved (or opened), for Version History
  const savedText = ref('')
  // The file as it was opened, until the dashboard changes
  const fileText = ref(null)
  const errors = ref([])
  const saving = ref(false)

  const currentKey = computed(() =>
    current.value ? `${current.value.target}/${current.value.name}` : null,
  )
  const filePath = computed(() =>
    current.value
      ? `${current.value.target}/dashboards/${current.value.name.toLowerCase()}.txt`
      : '',
  )

  async function loadList() {
    try {
      const response = await Api.get('/openc3-api/dashboards')
      dashboards.value = response.data.map((path) => {
        const [target, , file] = path.split('/')
        return `${target}/${file.replace(/\.txt$/, '').toUpperCase()}`
      })
    } catch (error) {
      console.error('Error loading dashboards:', error)
    }
  }
  // The dashboard to show first: the URL's, else the last one shown here,
  // else the first
  function initialKey() {
    const last = readString(LAST_KEY)
    return (
      routeKey(route.params) ||
      (dashboards.value.includes(last) ? last : dashboards.value[0])
    )
  }
  async function selectDashboard(key) {
    if (!key || key === currentKey.value) return
    if (!(await confirmDiscard())) return
    open(key)
  }
  async function open(key, { syncUrl = true } = {}) {
    // Panels share command definitions; opening a dashboard refetches them
    // so changed definitions show without a page reload
    clearCommandCache()
    const [target, name] = key.split('/')
    const request = ++openRequest
    opening.value = name
    let fetched
    try {
      fetched = await fetchDashboardText(key)
    } catch {
      notify.caution({ title: 'Unknown dashboard', body: key })
      if (request === openRequest) opening.value = null
      return
    }
    // Another dashboard was picked while this one loaded
    if (request !== openRequest) return
    const parsed = parseDashboard(fetched)
    load({ target, name }, parsed.model, parsed.errors, fetched)
    rememberCurrent({ syncUrl })
    // Keep the loading screen up until the new grid has rendered, laid its
    // panels out and has values (or 1.5 s, whichever is first), so neither
    // the old dashboard nor a grid of '--' shows through
    await nextTick()
    await Promise.race([
      firstValues(),
      new Promise((resolve) => setTimeout(resolve, 1500)),
    ])
    await new Promise((resolve) =>
      requestAnimationFrame(() => requestAnimationFrame(resolve)),
    )
    if (request === openRequest) opening.value = null
  }
  function load(dashboard, newModel, newErrors = [], newFileText = null) {
    current.value = dashboard
    model.value = newModel
    errors.value = newErrors
    fileText.value = newFileText
    editing.value = false
    savedText.value = serializeDashboard(newModel)
    history.markSaved()
  }
  // Navigator summary, reopen-on-launch and the URL all follow
  // the dashboard that's showing
  function rememberCurrent({ syncUrl = true } = {}) {
    const { target, name } = current.value
    remember(currentKey.value, model.value)
    writeString(LAST_KEY, currentKey.value)
    if (
      syncUrl &&
      (route.params.target !== target || route.params.dashboard !== name)
    ) {
      router.replace({
        name: 'Dashboards',
        params: { target, dashboard: name },
      })
    }
  }
  function post(target, dashboard, body) {
    return Api.post('/openc3-api/dashboard', {
      data: { scope: window.openc3Scope, target, dashboard, text: body },
    })
  }
  // The file is only written out here, not on every edit
  async function save() {
    if (!current.value) return
    saving.value = true
    const body = serializeDashboard(model.value)
    try {
      await post(current.value.target, current.value.name, body)
      savedText.value = body
      fileText.value = null
      history.markSaved()
      remember(currentKey.value, model.value)
      notify.normal({ title: 'Saved dashboard', body: currentKey.value })
    } catch (error) {
      notify.serious({
        title: 'Error saving dashboard',
        body: error.message,
      })
    } finally {
      saving.value = false
    }
  }
  // Copy a saved dashboard to a new target / name and open the copy
  async function duplicate(key, { target, name }) {
    try {
      await post(target, name, await fetchDashboardText(key))
    } catch (error) {
      notify.serious({
        title: 'Error duplicating dashboard',
        body: error.message,
      })
      return
    }
    await loadList()
    await selectDashboard(`${target}/${name}`)
  }
  async function createDashboard({ target, name, columns }) {
    if (!(await confirmDiscard())) return
    const dashboardTitle = name
      .toLowerCase()
      .split(/[_-]/)
      .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
    load({ target, name }, emptyDashboard(dashboardTitle, columns))
    await save()
    await loadList()
    rememberCurrent()
    startEditing()
  }
  async function deleteDashboard() {
    if (!current.value) return
    const ok = await ask(
      `Delete ${currentKey.value}? Dashboards installed by a plugin go back to the plugin's version.`,
      { okText: 'Delete', cancelText: 'Cancel', okClass: 'error' },
    )
    if (!ok) return
    try {
      await Api.delete(dashboardUrl(currentKey.value))
      notify.normal({
        title: 'Deleted dashboard',
        body: currentKey.value,
      })
    } catch (error) {
      notify.serious({
        title: 'Error deleting dashboard',
        body: error.message,
      })
      return
    }
    const deleted = currentKey.value
    history.markSaved() // nothing left to discard
    await loadList()
    if (dashboards.value.includes(deleted)) {
      await open(deleted) // plugin version restored
    } else {
      forget(deleted)
      current.value = null
      model.value = emptyDashboard('')
      savedText.value = ''
      fileText.value = null
      editing.value = false
      history.markSaved()
      writeString(LAST_KEY, null)
      router.replace({ name: 'Dashboards', params: {} })
    }
  }

  return {
    dashboards,
    current,
    opening,
    currentKey,
    filePath,
    savedText,
    fileText,
    errors,
    saving,
    loadList,
    initialKey,
    selectDashboard,
    open,
    save,
    duplicate,
    createDashboard,
    deleteDashboard,
  }
}
