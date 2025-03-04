/*
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
*/

import axios from './axios.js'
import { parse, stringify, isSafeNumber } from 'lossless-json'

// parse huge integer values into a bigint, and use a regular number otherwise
export function customNumberParser(value) {
  return isSafeNumber(value) ? parseFloat(value) : BigInt(value)
}
export default class OpenC3Api {
  id = 1

  constructor() {}

  async exec(
    method,
    params,
    kwparams = {},
    headerOptions = {},
    timeout = 60000,
  ) {
    try {
      let refreshed = await OpenC3Auth.updateToken(
        OpenC3Auth.defaultMinValidity,
      )
      if (refreshed) {
        OpenC3Auth.setTokens()
      }
    } catch (error) {
      OpenC3Auth.login()
    }
    this.id = this.id + 1
    try {
      kwparams['scope'] = window.openc3Scope
      // Everything from the front-end is manual by default
      // The various api methods decide whether to pass the manual
      // flag to the authorize routine
      headerOptions['manual'] = true
      const response = await axios.post(
        '/openc3-api/api',
        {
          jsonrpc: '2.0',
          method: method,
          params: params,
          id: this.id,
          keyword_params: kwparams,
        },
        {
          headers: {
            Authorization: localStorage.openc3Token,
            'Content-Type': 'application/json-rpc',
            ...headerOptions,
          },
          timeout: timeout,
          transformRequest: [
            (data, headers) => {
              // stringify the data with lossless-json
              return stringify(data)
            },
          ],
          transformResponse: [
            (data) => {
              // parse the data with lossless-json ensuring that large numbers are parsed as BigInts
              // but all other numbers are parsed as regular numbers
              return parse(data, undefined, customNumberParser)
            },
          ],
        },
      )
      // let data = response.data
      // if (data.error) {
      //   let err = new Error()
      //   err.name = data.error.data.class
      //   err.message = data.error.data.message
      //   console.log(data.error.data.backtrace.join('\n'))
      //   throw err
      // }
      return response.data.result
    } catch (error) {
      let err = new Error()
      if (error.response) {
        // The request was made and the server responded with a
        // status code that falls out of the range of 2xx
        err.name = error.response.data.error.data.class
        err.message = error.response.data.error.data.message
        err.object = error.response.data.error
      } else if (error.request) {
        // The request was made but no response was received, `error.request`
        // is an instance of XMLHttpRequest in the browser and an instance
        // of http.ClientRequest in Node.js
        err.name = 'Request error'
        // NOTE: Openc3Screen.vue uses this specific message to determine
        // if the CmdTlmApi server is down. Don't change unless also changing there.
        err.message = 'Request error, no response received'
      } else {
        // Something happened in setting up the request and triggered an Error
        err.name = 'Unknown error'
      }
      throw err
    }
  }

  decode_openc3_type(val) {
    if (val !== null && typeof val === 'object') {
      if (val.json_class == 'Float' && val.raw) {
        if (val.raw == 'NaN') {
          return NaN
        } else if (val.raw == 'Infinity') {
          return Infinity
        } else if (val.raw == '-Infinity') {
          return -Infinity
        }
      }
    }
    return null
  }

  encode_openc3_type(val) {
    if (Number.isNaN(val)) {
      return { json_class: 'Float', raw: 'NaN' }
    } else if (val == Number.POSITIVE_INFINITY) {
      return { json_class: 'Float', raw: 'Infinity' }
    } else if (val == Number.NEGATIVE_INFINITY) {
      return { json_class: 'Float', raw: '-Infinity' }
    }
    return null
  }

  ensure_offline_access() {
    this.offline_access_needed().then((needed) => {
      if (needed) {
        if (localStorage.openc3OfflineToken) {
          this.set_offline_access(localStorage.openc3OfflineToken).then(() => {
            delete localStorage.openc3OfflineToken
          })
        } else {
          OpenC3Auth.getOfflineAccess()
        }
      }
    })
  }

  // ***********************************************
  // The following APIs are used by the CmdTlmServer
  // ***********************************************

  offline_access_needed() {
    return this.exec('offline_access_needed', [])
  }

  set_offline_access(offline_access_token) {
    return this.exec('set_offline_access', [offline_access_token])
  }

  get_all_interface_info() {
    return this.exec('get_all_interface_info', [])
  }

  map_target_to_interface(target_name, interface_name) {
    return this.exec('map_target_to_interface', [target_name, interface_name])
  }

  connect_interface(interface_name, ...interface_params) {
    if (interface_params.length > 0) {
      return this.exec('connect_interface', [
        interface_name,
        ...interface_params,
      ])
    } else {
      return this.exec('connect_interface', [interface_name])
    }
  }

  disconnect_interface(interface_name) {
    return this.exec('disconnect_interface', [interface_name])
  }

  interface_cmd(interface_name, command_name, ...command_params) {
    return this.exec('interface_cmd', [
      interface_name,
      command_name,
      ...command_params,
    ])
  }

  get_all_router_info() {
    return this.exec('get_all_router_info', [])
  }

  connect_router(router_name) {
    return this.exec('connect_router', [router_name])
  }

  disconnect_router(router_name) {
    return this.exec('disconnect_router', [router_name])
  }

  get_target_interfaces() {
    return this.exec('get_target_interfaces', [])
  }

  get_tlm_cnts(target_commands) {
    return this.exec('get_tlm_cnts', [target_commands])
  }

  get_item(target, packet, item) {
    return this.exec('get_item', [target, packet, item])
  }

  get_param(target, packet, item) {
    return this.exec('get_param', [target, packet, item])
  }
  // DEPRECATED for get_param
  get_parameter(target, packet, item) {
    return this.exec('get_param', [target, packet, item])
  }

  get_limits_sets() {
    return this.exec('get_limits_sets', [])
  }

  get_limits_set() {
    return this.exec('get_limits_set', [])
  }

  set_limits_set(limits_set) {
    return this.exec('set_limits_set', [limits_set])
  }

  // ***********************************************
  // End CmdTlmServer APIs
  // ***********************************************

  get_target(target_name) {
    return this.exec('get_target', [target_name])
  }

  get_target_names() {
    return this.exec('get_target_names', [])
  }
  // DEPRECATED for get_target_names
  get_target_list() {
    return this.exec('get_target_names', [])
  }

  get_tlm(target_name, packet_name) {
    return this.exec('get_tlm', [target_name, packet_name])
  }
  // DEPRECATED for get_tlm
  get_telemetry(target_name, packet_name) {
    return this.exec('get_tlm', [target_name, packet_name])
  }

  get_all_tlm(target_name) {
    return this.exec('get_all_tlm', [target_name])
  }
  // DEPRECATED for get_all_tlm
  get_all_telemetry(target_name) {
    return this.exec('get_all_tlm', [target_name])
  }

  get_all_tlm_names(target_name, hidden = false) {
    return this.exec('get_all_tlm_names', [target_name], { hidden: hidden })
  }
  // DEPRECATED for get_all_tlm_names
  get_all_telemetry_names(target_name) {
    return this.exec('get_all_tlm_names', [target_name])
  }

  async get_tlm_packet(target_name, packet_name, value_type, stale_time = 30) {
    const data = await this.exec('get_tlm_packet', [target_name, packet_name], {
      type: value_type,
      stale_time: stale_time,
    })
    // Make sure data isn't null or undefined. Note this is the only valid use of == or !=
    if (data != null) {
      let len = data.length
      let converted = null
      for (let i = 0; i < len; i++) {
        converted = this.decode_openc3_type(data[i][1])
        if (converted !== null) {
          data[i][1] = converted
        }
      }
    }
    return data
  }

  get_packet_derived_items(target_name, packet_name) {
    return this.exec('get_packet_derived_items', [target_name, packet_name])
  }

  get_tlm_buffer(target_name, packet_name) {
    return this.exec('get_tlm_buffer', [target_name, packet_name])
  }

  async get_tlm_values(items, stale_time = 30, cache_timeout = null) {
    let kw_args = {
      stale_time: stale_time,
    }
    if (cache_timeout !== null) {
      kw_args['cache_timeout'] = cache_timeout
    }
    const data = await this.exec(
      'get_tlm_values',
      [items],
      kw_args,
      {},
      10000, // 10s timeout ... should never be this long
    )
    let len = data[0].length
    let converted = null
    for (let i = 0; i < len; i++) {
      converted = this.decode_openc3_type(data[0][i])
      if (converted !== null) {
        data[0][i] = converted
      }
    }
    return data
  }

  get_limits(target_name, packet_name, item_name) {
    return this.exec('get_limits', [target_name, packet_name, item_name])
  }

  async tlm(target_name, packet_name, item_name, value_type = 'CONVERTED') {
    let data = null
    // Check for the single string syntax: tlm("TGT PKT ITEM")
    if (packet_name === undefined) {
      data = await this.exec('tlm', [target_name])
      // Check for the single string syntax with type: tlm("TGT PKT ITEM", "RAW")
    } else if (item_name === undefined) {
      if (
        ['RAW', 'CONVERTED', 'FORMATTED', 'WITH_UNITS'].includes(packet_name)
      ) {
        data = await this.exec('tlm', [target_name], { type: packet_name })
      } else {
        let err = new Error()
        err.name = 'TypeError'
        err.message = `Invalid data type ${packet_name}. Valid options are RAW, CONVERTED, FORMATTED, and WITH_UNITS.`
        throw err
      }
    } else {
      data = await this.exec('tlm', [target_name, packet_name, item_name], {
        type: value_type,
      })
    }
    let converted = this.decode_openc3_type(data)
    if (converted !== null) {
      data = converted
    }
    return data
  }

  async inject_tlm(
    target_name,
    packet_name,
    item_hash = null,
    value_type = 'CONVERTED',
  ) {
    await this.exec('inject_tlm', [target_name, packet_name, item_hash], {
      type: value_type,
    })
  }

  set_tlm(target_name, packet_name, item_name, value_type) {
    return this.exec('set_tlm', [target_name, packet_name, item_name], {
      type: value_type,
    })
  }

  override_tlm(target_name, packet_name, item_name, value_type) {
    return this.exec('override_tlm', [target_name, packet_name, item_name], {
      type: value_type,
    })
  }

  get_overrides() {
    return this.exec('get_overrides')
  }

  normalize_tlm(target_name, packet_name, item_name, value_type) {
    return this.exec('normalize_tlm', [target_name, packet_name, item_name], {
      type: value_type,
    })
  }

  get_all_cmds(target_name) {
    return this.exec('get_all_cmds', [target_name])
  }
  // DEPRECATED for get_all_cmds
  get_all_commands(target_name) {
    return this.exec('get_all_cmds', [target_name])
  }

  get_all_cmd_names(target_name, hidden = false) {
    return this.exec('get_all_cmd_names', [target_name], { hidden: hidden })
  }
  // DEPRECATED for get_all_cmd_names
  get_all_command_names(target_name) {
    return this.exec('get_all_cmd_names', [target_name])
  }

  get_cmd(target_name, command_name) {
    return this.exec('get_cmd', [target_name, command_name])
  }
  // DEPRECATED for get_cmd
  get_command(target_name, command_name) {
    return this.exec('get_cmd', [target_name, command_name])
  }

  get_cmd_cnts(target_commands) {
    return this.exec('get_cmd_cnts', [target_commands])
  }

  get_cmd_value(
    target_name,
    packet_name,
    parameter_name,
    value_type = 'CONVERTED',
  ) {
    return this.exec('get_cmd_value', [
      target_name,
      packet_name,
      parameter_name,
      value_type,
    ])
  }

  get_cmd_buffer(target_name, packet_name) {
    return this.exec('get_cmd_buffer', [target_name, packet_name])
  }

  // Implementation of functionality shared by cmd methods with param_lists.
  _cmd(method, target_name, command_name, param_list, headerOptions) {
    let converted = null
    for (let key in param_list) {
      if (Object.prototype.hasOwnProperty.call(param_list, key)) {
        converted = this.encode_openc3_type(param_list[key])
        if (converted !== null) {
          param_list[key] = converted
        }
      }
    }
    return this.exec(
      method,
      [target_name, command_name, param_list],
      {},
      headerOptions,
    )
  }

  get_cmd_hazardous(target_name, command_name, param_list, headerOptions = {}) {
    if (command_name === undefined) {
      return this.exec('get_cmd_hazardous', target_name, {}, headerOptions)
    } else {
      return this._cmd(
        'get_cmd_hazardous',
        target_name,
        command_name,
        param_list,
        headerOptions,
      )
    }
  }

  cmd(target_name, command_name, param_list, headerOptions = {}) {
    if (command_name === undefined) {
      return this.exec('cmd', target_name, {}, headerOptions)
    } else {
      return this._cmd(
        'cmd',
        target_name,
        command_name,
        param_list,
        headerOptions,
      )
    }
  }

  cmd_no_range_check(
    target_name,
    command_name,
    param_list,
    headerOptions = {},
  ) {
    if (command_name === undefined) {
      return this.exec('cmd_no_range_check', target_name, {}, headerOptions)
    } else {
      return this._cmd(
        'cmd_no_range_check',
        target_name,
        command_name,
        param_list,
        headerOptions,
      )
    }
  }

  cmd_raw(target_name, command_name, param_list, headerOptions = {}) {
    if (command_name === undefined) {
      return this.exec('cmd_raw', target_name, {}, headerOptions)
    } else {
      return this._cmd(
        'cmd_raw',
        target_name,
        command_name,
        param_list,
        headerOptions,
      )
    }
  }

  cmd_raw_no_range_check(
    target_name,
    command_name,
    param_list,
    headerOptions = {},
  ) {
    if (command_name === undefined) {
      return this.exec('cmd_raw_no_range_check', target_name, {}, headerOptions)
    } else {
      return this._cmd(
        'cmd_raw_no_range_check',
        target_name,
        command_name,
        param_list,
        headerOptions,
      )
    }
  }

  cmd_no_hazardous_check(
    target_name,
    command_name,
    param_list,
    headerOptions = {},
  ) {
    if (command_name === undefined) {
      return this.exec('cmd_no_hazardous_check', target_name, {}, headerOptions)
    } else {
      return this._cmd(
        'cmd_no_hazardous_check',
        target_name,
        command_name,
        param_list,
        headerOptions,
      )
    }
  }

  cmd_no_checks(target_name, command_name, param_list, headerOptions = {}) {
    if (command_name === undefined) {
      return this.exec('cmd_no_checks', target_name, {}, headerOptions)
    } else {
      return this._cmd(
        'cmd_no_checks',
        target_name,
        command_name,
        param_list,
        headerOptions,
      )
    }
  }

  cmd_raw_no_hazardous_check(
    target_name,
    command_name,
    param_list,
    headerOptions = {},
  ) {
    if (command_name === undefined) {
      return this.exec(
        'cmd_raw_no_hazardous_check',
        target_name,
        {},
        headerOptions,
      )
    } else {
      return this._cmd(
        'cmd_raw_no_hazardous_check',
        target_name,
        command_name,
        param_list,
        headerOptions,
      )
    }
  }

  cmd_raw_no_checks(target_name, command_name, param_list, headerOptions = {}) {
    if (command_name === undefined) {
      return this.exec('cmd_raw_no_checks', target_name, {}, headerOptions)
    } else {
      return this._cmd(
        'cmd_raw_no_checks',
        target_name,
        command_name,
        param_list,
        headerOptions,
      )
    }
  }

  build_cmd(target_name, command_name, param_list) {
    if (command_name === undefined) {
      return this.exec('build_cmd', target_name)
    } else {
      return this._cmd('build_cmd', target_name, command_name, param_list)
    }
  }
  // DEPRECATED for build_cmd
  build_command(target_name, command_name, param_list) {
    if (command_name === undefined) {
      return this.exec('build_cmd', target_name)
    } else {
      return this._cmd('build_cmd', target_name, command_name, param_list)
    }
  }

  get_interface_names() {
    return this.exec('get_interface_names', [])
  }

  send_raw(interface_name, data) {
    return this.exec('send_raw', [interface_name, data])
  }

  list_configs(tool) {
    return this.exec('list_configs', [tool])
  }

  load_config(tool, name) {
    return this.exec('load_config', [tool, name])
  }

  save_config(tool, name, data) {
    return this.exec('save_config', [tool, name, data])
  }

  delete_config(tool, name) {
    return this.exec('delete_config', [tool, name])
  }

  enable_limits(target, packet, item) {
    return this.exec('enable_limits', [target, packet, item])
  }

  disable_limits(target, packet, item) {
    return this.exec('disable_limits', [target, packet, item])
  }

  get_out_of_limits() {
    return this.exec('get_out_of_limits', [])
  }

  get_overall_limits_state(ignored) {
    return this.exec('get_overall_limits_state', [ignored])
  }

  list_settings() {
    return this.exec('list_settings', [])
  }

  get_all_settings() {
    return this.exec('get_all_settings', [])
  }

  get_setting(name) {
    return this.exec('get_setting', [name])
  }

  get_settings(array) {
    return this.exec('get_settings', array)
  }

  set_setting(name, data) {
    return this.exec('set_setting', [name, data])
  }

  update_news() {
    return this.exec('update_news', [])
  }

  // DEPRECATED for set_setting
  save_setting(name, data) {
    return this.exec('set_setting', [name, data])
  }

  get_metrics() {
    return this.exec('get_metrics', [])
  }

  // TODO: Currently unused but seemed like a useful function
  async hashString(string) {
    if (window.isSecureContext) {
      // Encode the string as an arrayBuffer which the subtle crypto API uses
      const arrayBuffer = new TextEncoder().encode(string)
      // Use the subtle crypto API to perform a SHA256 Sum of the array buffer
      // The resulting hash is stored in an array buffer
      const hashAsArrayBuffer = await crypto.subtle.digest(
        'SHA-256',
        arrayBuffer,
      )
      // To create a string we will get the hexadecimal value of each byte of the array buffer
      // This gets us an array where each byte of the array buffer becomes one item in the array
      const uint8ViewOfHash = new Uint8Array(hashAsArrayBuffer)
      // We then convert it to a regular array so we can convert each item to hexadecimal strings
      // Where to characters of 0-9 or a-f represent a number between 0 and 16, containing 4 bits of information, so 2 of them is 8 bits (1 byte).
      return Array.from(uint8ViewOfHash)
        .map((b) => b.toString(16).padStart(2, '0'))
        .join('')
    }
    // else ?
  }
}
