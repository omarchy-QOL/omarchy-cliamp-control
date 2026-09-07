import QtQuick
import QtTest
import "../logic/Settings.js" as Settings
import "../logic/Paths.js" as Paths

TestCase {
  name: "Settings"

  function test_defaultsAndValidation() {
    compare(Settings.normalize({}), {
      alignment: "Center", windowWidth: 1200, windowHeight: 600,
      iconVisible: true
    })
    compare(Settings.normalize({
      alignment: "Invalid", windowWidth: 1.5, windowHeight: Infinity,
      iconVisible: false
    }), {
      alignment: "Center", windowWidth: 1200, windowHeight: 600,
      iconVisible: false
    })
    compare(Settings.dimension("850", 1200), 850)
    compare(Settings.dimension(0, 1200), 1200)
    compare(Settings.dimension(100001, 1200), 1200)
  }

  function test_inlineEntry() {
    var entry = { id: "cliamp", windowWidth: 850 }
    for (var section of ["left", "center", "right"]) {
      var layout = { left: ["clock"] }
      layout[section] = [entry]
      compare(Settings.findEntry({layout: layout}, "cliamp"), entry)
    }
    compare(Settings.findEntry({}, "cliamp"), {})
  }

  function test_fileUrl() {
    compare(Paths.localPath("file:///tmp/a%20b/%23player/"),
      "/tmp/a b/#player/")
  }
}
