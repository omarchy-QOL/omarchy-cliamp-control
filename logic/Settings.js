.pragma library

function dimension(value, defaultValue) {
  var number = Number(value)
  return Number.isInteger(number) && number >= 1 && number <= 100000
    ? number : defaultValue
}

function normalize(entry) {
  return {
    alignment: ["Left", "Center", "Right"].indexOf(entry.alignment) >= 0
      ? entry.alignment : "Center",
    windowWidth: dimension(entry.windowWidth, 1200),
    windowHeight: dimension(entry.windowHeight, 600),
    iconVisible: entry.iconVisible === undefined || entry.iconVisible === null
      || entry.iconVisible === true
  }
}

function findEntry(barConfig, id) {
  var layout = barConfig.layout || {}
  var entries = [].concat(layout.left || [], layout.center || [],
    layout.right || [])
  return entries.find(function(entry) { return entry.id === id }) || {}
}
