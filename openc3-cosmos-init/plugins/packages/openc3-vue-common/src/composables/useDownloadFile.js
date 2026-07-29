/*
# Copyright 2026 OpenC3, Inc.
# All Rights Reserved.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See LICENSE.md for more details.

# This file may also be used under the terms of a commercial license
# if purchased from OpenC3, Inc.
*/

import { Api } from '@openc3/js-common/services'

export function useDownloadFile() {
  // Decode a Base64 string into raw bytes
  function base64ToBytes(base64) {
    const decodedData = window.atob(base64)
    // Create UNIT8ARRAY of size same as row data length
    const uInt8Array = new Uint8Array(decodedData.length)
    // Insert all character code into uInt8Array
    for (let i = 0; i < decodedData.length; ++i) {
      uInt8Array[i] = decodedData.charCodeAt(i)
    }
    return uInt8Array
  }

  // Make a link and then 'click' on it to start the download
  function saveBlob(blob, filename) {
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.setAttribute('download', filename)
    link.click()
    // Let the browser start the download before releasing the blob
    setTimeout(() => URL.revokeObjectURL(url), 0)
  }

  // POST to url and download the response as a file. The response is expected
  // to be JSON with 'contents' and 'filename' attributes.
  //   data:    request body passed to Api.post, a FormData implies multipart
  //   headers: request headers passed to Api.post
  //   type:    MIME type of the downloaded file
  //   base64:  response contents are Base64 encoded and must be decoded
  //   prefix:  text prepended to the contents of the downloaded file
  async function downloadFile(
    url,
    {
      data = undefined,
      headers = undefined,
      type = 'application/octet-stream',
      base64 = false,
      prefix = null,
    } = {},
  ) {
    let postHeaders = headers
    if (!postHeaders && data instanceof FormData) {
      postHeaders = { 'Content-Type': 'multipart/form-data' }
    }
    const response = await Api.post(url, { data, headers: postHeaders })
    const contents = base64
      ? base64ToBytes(response.data.contents)
      : response.data.contents
    const blob = new Blob(prefix ? [prefix, contents] : [contents], { type })
    saveBlob(blob, response.data.filename)
    return response
  }

  return { downloadFile, saveBlob }
}

// Convenience wrapper for the common case of downloading a Base64 encoded zip
export function useDownloadZip() {
  const { downloadFile } = useDownloadFile()

  return (url) => downloadFile(url, { base64: true, type: 'application/zip' })
}
