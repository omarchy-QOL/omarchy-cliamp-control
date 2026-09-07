.pragma library

function localPath(url) {
  return decodeURIComponent(String(url).slice(7))
}
