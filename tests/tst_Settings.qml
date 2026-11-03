import QtQuick
import QtTest
import "../logic/Settings.js" as Settings
import "../logic/Paths.js" as Paths
import "../logic/Commands.js" as Commands

TestCase {
  name: "Settings"

  function test_defaultsAndValidation() {
    compare(Settings.normalize({}), {
      edge: "Top", placement: "Center",
      windowWidth: 1200, windowHeight: 600
    })
    compare(Settings.normalize({
      edge: "Invalid", placement: "Invalid",
      windowWidth: 1.5, windowHeight: Infinity
    }), {
      edge: "Top", placement: "Center",
      windowWidth: 1200, windowHeight: 600
    })
    compare(Settings.dimension("850", 1200), 850)
    compare(Settings.dimension(0, 1200), 1200)
    compare(Settings.dimension(9999, 1200), 9999)
    compare(Settings.dimension(10000, 1200), 1200)
  }

  function test_inlineEntry() {
    const entry = { id: "cliamp", windowWidth: 850 }
    for (const section of ["left", "center", "right"]) {
      const layout = { left: ["clock"] }
      layout[section] = [entry]
      compare(Settings.findEntry({layout: layout}, "cliamp"), entry)
    }
    compare(Settings.findEntry({}, "cliamp"), {})
  }

  function test_luaQuoting() {
    compare(Commands.quote('a"b\\c\n'), '"a\\034b\\092c\\010"')
  }

  function test_fileUrl() {
    compare(Paths.localPath("file:///tmp/a%20b/%23player/"),
      "/tmp/a b/#player/")
  }
}
