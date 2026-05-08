// Volumes prepend a slash to root (e.g. "/foo") so we strip it before upcasing.
export function storageName(mode, root) {
  const upper =
    mode === 'volume' ? root.toUpperCase().slice(1) : root.toUpperCase()
  return `OPENC3_${upper}_${mode.toUpperCase()}`
}

// "?bucket=OPENC3_FOO_BUCKET" or "?volume=OPENC3_FOO_VOLUME"
export function storageQueryString(mode, root) {
  return `?${mode}=${storageName(mode, root)}`
}

// Run async fn over items with at most `limit` in flight at once.
// Returns Promise.allSettled-style results in input order.
export async function runPool(items, limit, fn) {
  const results = new Array(items.length)
  let next = 0
  const worker = async () => {
    while (next < items.length) {
      const i = next++
      try {
        results[i] = { status: 'fulfilled', value: await fn(items[i], i) }
      } catch (reason) {
        results[i] = { status: 'rejected', reason }
      }
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, worker),
  )
  return results
}

// Helper function to download a base64-encoded file
export function downloadBase64File(base64Contents, filename) {
  // Decode Base64 string
  const decodedData = window.atob(base64Contents)
  // Create UNIT8ARRAY of size same as row data length
  const uInt8Array = new Uint8Array(decodedData.length)
  // Insert all character code into uInt8Array
  for (let i = 0; i < decodedData.length; ++i) {
    uInt8Array[i] = decodedData.charCodeAt(i)
  }
  const blob = new Blob([uInt8Array])
  const href = URL.createObjectURL(blob)

  // Make a link and then 'click' on it to start the download
  const link = document.createElement('a')
  link.href = href
  link.setAttribute('download', filename)
  link.click()
}
