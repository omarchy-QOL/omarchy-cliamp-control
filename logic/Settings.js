.pragma library

function dimension(value, defaultValue) {
  const number = Number(value)
  return Number.isInteger(number) && number >= 1 && number <= 9999
    ? number : defaultValue
}

function normalize(entry) {
  return {
    edge: ["Top", "Right", "Bottom", "Left"].indexOf(entry.edge) >= 0
      ? entry.edge : "Top",
    placement: ["Start", "Center", "End"].indexOf(entry.placement) >= 0
      ? entry.placement : "Center",
    dimBackground: entry.dimBackground !== false,
    windowWidth: dimension(entry.windowWidth, 1200),
    windowHeight: dimension(entry.windowHeight, 600)
  }
}

function findEntry(barConfig, id) {
  const layout = barConfig.layout || {}
  const entries = [].concat(layout.left || [], layout.center || [],
    layout.right || [])
  return entries.find(function(entry) { return entry.id === id }) || {}
}
