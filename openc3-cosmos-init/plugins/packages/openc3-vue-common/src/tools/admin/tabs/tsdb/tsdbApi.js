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

import { Api } from '@openc3/js-common/services'

// QuestDB's PG wire occasionally drops idle connections; retry with backoff
// so transient PQconsumeInput / "server closed the connection" errors from
// the backend don't surface to the user.
export async function execSql(sql, db_shard, retries = 3) {
  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      let url = '/openc3-api/tsdb/exec'
      if (db_shard && db_shard !== '0') {
        url += `?db_shard=${db_shard}`
      }
      return await Api.post(url, {
        data: sql,
        headers: {
          Accept: 'application/json',
          'Content-Type': 'text/plain',
        },
      })
    } catch (error) {
      const msg = error.response?.data?.message || error.message || ''
      const isConnectionError =
        msg.includes('PQconsumeInput') ||
        msg.includes('server closed the connection')
      if (isConnectionError && attempt < retries) {
        await new Promise((r) => setTimeout(r, 1000 * attempt))
        continue
      }
      throw error
    }
  }
}
