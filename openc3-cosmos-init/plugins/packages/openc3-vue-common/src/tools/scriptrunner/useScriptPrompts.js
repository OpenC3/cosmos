/**
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

import { reactive, ref } from 'vue'
import axios from 'axios'
import { Api } from '@openc3/js-common/services'

/**
 * Composable for managing script prompts and dialogs
 * Handles all the interactive prompts that can come from running scripts
 */
export function useScriptPrompts() {
  // Active prompt tracking
  const activePromptId = ref('')

  // Dialog state objects
  const ask = reactive({
    show: false,
    question: '',
    default: null,
    password: false,
    answerRequired: true,
    callback: () => {},
  })

  const file = reactive({
    show: false,
    title: '',
    message: '',
    directory: null,
    filter: '*',
    multiple: false,
    callback: () => {},
  })

  const bucket = reactive({
    show: false,
    title: '',
    message: '',
  })

  const prompt = reactive({
    show: false,
    title: '',
    subtitle: '',
    message: '',
    details: '',
    buttons: null,
    layout: 'horizontal',
    method: '',
    multiple: null,
    callback: () => {},
  })

  const information = reactive({
    show: false,
    title: '',
    text: [],
    width: '600',
  })

  const inputMetadata = reactive({
    show: false,
    events: [],
    callback: () => {},
  })

  const results = reactive({
    show: false,
    text: '',
  })

  const criticalCmd = reactive({
    uuid: null,
    string: null,
    user: null,
    display: false,
  })

  async function showMetadata() {
    const response = await Api.get('/openc3-api/metadata')
    // TODO: This is how Calendar creates new metadata items via makeMetadataEvent
    inputMetadata.value.events = response.data.map((event) => {
      return {
        name: 'Metadata',
        start: new Date(event.start * 1000),
        end: new Date(event.start * 1000),
        color: event.color,
        type: event.type,
        timed: true,
        metadata: event,
      }
    })
    inputMetadata.value.show = true
  }

  /**
   * Callback for generic prompt dialogs
   */
  function promptDialogCallback(value, scriptId) {
    prompt.show = false
    Api.post(`/script-api/running-script/${scriptId}/prompt`, {
      data: {
        method: prompt.method,
        answer: value,
        prompt_id: activePromptId.value,
        multiple: prompt.multiple,
      },
    })
  }

  /**
   * Callback for file dialog selection
   */
  async function fileDialogCallback(files, scriptId) {
    // Set fileNames to 'COSMOS__CANCEL' in case they cancelled
    // otherwise we will populate it with the file names they selected
    let fileNames = 'COSMOS__CANCEL'
    // Record all the API request promises so we can ensure they complete
    let promises = []
    if (files != 'COSMOS__CANCEL') {
      fileNames = []
      files.forEach((selectedFile) => {
        fileNames.push(selectedFile.name)
        promises.push(async () => {
          const response = await Api.get(
            `/openc3-api/storage/upload/${encodeURIComponent(
              `${window.openc3Scope}/tmp/${selectedFile.name}`,
            )}?bucket=OPENC3_CONFIG_BUCKET`,
          )
          // This pushes the file into storage by using the fields in the presignedRequest
          // See storage_controller.rb get_upload_presigned_request()
          promises.push(
            axios({
              ...response.data,
              data: selectedFile,
            }),
          )
        })
      })
    }
    // We have to wait for all the upload API requests to finish before notifying the prompt
    await Promise.all(promises)
    Api.post(`/script-api/running-script/${scriptId}/prompt`, {
      data: {
        method: file.multiple ? 'open_files_dialog' : 'open_file_dialog',
        answer: fileNames,
        prompt_id: activePromptId.value,
      },
    })
    file.show = false // Close the dialog immediately to avoid race condition
  }

  function bucketDialogCallback(response) {
    bucket.show = false
    Api.post(`/script-api/running-script/${this.scriptId}/prompt`, {
      data: {
        method: 'open_bucket_dialog',
        answer: response,
        prompt_id: this.activePromptId,
      },
    })
  }

  /**
   * Main handler for script prompt events
   * Processes different types of prompts from the running script
   */
  function handleScript(data, scriptId, showMetadata) {
    if (data.prompt_complete) {
      activePromptId.value = ''
      prompt.show = false
      ask.show = false
      file.show = false
      bucket.show = false
      return
    }

    activePromptId.value = data.prompt_id
    prompt.method = data.method // Set it here since all prompts use this
    prompt.layout = 'horizontal' // Reset the layout since most are horizontal
    prompt.title = 'Prompt'
    prompt.subtitle = ''
    prompt.details = ''
    prompt.buttons = []
    prompt.multiple = null

    switch (data.method) {
      case 'ask':
      case 'ask_string':
        // Reset values since this dialog can be reused
        ask.default = null
        ask.answerRequired = true
        ask.password = false
        ask.question = data.args[0]
        // If the second parameter is not true or false it indicates a default value
        if (data.args[1] && data.args[1] !== true && data.args[1] !== false) {
          ask.default = data.args[1].toString()
        } else if (data.args[1] === true) {
          // If the second parameter is true it means no value is required to be entered
          ask.answerRequired = false
        }
        // The third parameter indicates a password textfield
        if (data.args[2] === true) {
          ask.password = true
        }
        ask.callback = (value) => {
          ask.show = false // Close the dialog
          if (ask.password) {
            Api.post(`/script-api/running-script/${scriptId}/prompt`, {
              data: {
                method: data.method,
                password: value, // Using password as a key automatically filters it from rails logs
                prompt_id: activePromptId.value,
              },
            })
          } else {
            Api.post(`/script-api/running-script/${scriptId}/prompt`, {
              data: {
                method: data.method,
                answer: value,
                prompt_id: activePromptId.value,
              },
            })
          }
        }
        ask.show = true // Display the dialog
        break

      case 'prompt_for_hazardous':
        prompt.title = 'Hazardous Command'
        prompt.message = `Warning: Command ${data.args[0]} ${data.args[1]} is Hazardous. `
        if (data.args[2]) {
          prompt.message += data.args[2] + ' '
        }
        prompt.message += 'Send?'
        prompt.buttons = [{ text: 'Send', value: 'Send' }]
        prompt.callback = (value) => promptDialogCallback(value, scriptId)
        prompt.show = true
        break

      case 'prompt_for_critical_cmd':
        criticalCmd.uuid = data.args[0]
        criticalCmd.string = data.args[5]
        criticalCmd.user = data.args[1]
        criticalCmd.display = true
        break

      case 'prompt':
        if (data.kwargs?.informative) {
          prompt.subtitle = data.kwargs.informative
        }
        if (data.kwargs?.details) {
          prompt.details = data.kwargs.details
        }
        prompt.message = data.args[0]
        prompt.buttons = [{ text: 'Ok', value: 'Ok' }]
        prompt.callback = (value) => promptDialogCallback(value, scriptId)
        prompt.show = true
        break

      case 'combo_box':
      case 'check_box':
        if (data.kwargs?.informative) {
          prompt.subtitle = data.kwargs.informative
        }
        if (data.kwargs?.details) {
          prompt.details = data.kwargs.details
        }
        // check_box is always multiple choice, combo_box is single choice unless kwargs.multiple is set to true
        if (data.method === 'check_box' || data.kwargs?.multiple) {
          prompt.multiple = true
        }
        prompt.message = data.args[0]
        data.args.slice(1).forEach((v) => {
          prompt.buttons.push({ title: v, value: v })
        })
        prompt.layout = data.method.split('_')[0]
        prompt.callback = (value) => promptDialogCallback(value, scriptId)
        prompt.show = true
        break

      case 'message_box':
      case 'vertical_message_box':
        if (data.kwargs?.informative) {
          prompt.subtitle = data.kwargs.informative
        }
        if (data.kwargs?.details) {
          prompt.details = data.kwargs.details
        }
        prompt.message = data.args[0]
        data.args.slice(1).forEach((v) => {
          prompt.buttons.push({ text: v, value: v })
        })
        if (data.method.includes('vertical')) {
          prompt.layout = 'vertical'
        }
        prompt.callback = (value) => promptDialogCallback(value, scriptId)
        prompt.show = true
        break

      case 'backtrace':
        information.title = 'Call Stack'
        information.text = data.args
        information.show = true
        information.width = '600'
        break

      case 'metadata_input':
        inputMetadata.callback = (value) => {
          inputMetadata.show = false
          Api.post(`/script-api/running-script/${scriptId}/prompt`, {
            data: {
              method: data.method,
              answer: value,
              prompt_id: activePromptId.value,
            },
          })
        }
        showMetadata()
        break

      case 'open_bucket_dialog':
        bucket.title = data.args[0]
        bucket.message = data.args[1]
        bucket.show = true
        break

      // This is called continuously by the backend
      case 'open_file_dialog':
      case 'open_files_dialog':
        file.title = data.args[0]
        file.message = data.args[1]
        if (data.kwargs?.filter) {
          file.filter = data.kwargs.filter
        }
        if (data.method == 'open_files_dialog') {
          file.multiple = true
        }
        file.show = true
        break

      default:
        // console.log(
        // 'Unknown script method:' + data.method + ' with args:' + data.args
        // )
        break
    }
  }

  return {
    // State
    ask,
    bucket,
    criticalCmd,
    file,
    information,
    inputMetadata,
    prompt,
    results,

    // Methods
    bucketDialogCallback,
    fileDialogCallback,
    handleScript,
    promptDialogCallback,
    showMetadata,
  }
}
