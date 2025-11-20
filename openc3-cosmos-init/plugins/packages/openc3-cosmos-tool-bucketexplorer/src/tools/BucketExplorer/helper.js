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
