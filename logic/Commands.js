.pragma library

function quote(value) {
  return '"' + String(value).replace(/[\\"\u0000-\u001f]/g, function(char) {
    return "\\" + String(char.charCodeAt(0)).padStart(3, "0")
  }) + '"'
}

function call(path, method, args) {
  return "function() dofile(" + quote(path) + ")." + method + "("
    + args.map(function(value) {
      return typeof value === "number" ? String(value) : quote(value)
    }).join(",") + ") end"
}
