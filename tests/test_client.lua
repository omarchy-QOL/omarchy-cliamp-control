local monitor = {name = "landscape", id = 1, width = 1920, height = 1200,
  x = 1080, y = 0, scale = 1, transform = 0,
  reserved = {left = 0, top = 26, right = 0, bottom = 0},
  active_workspace = {id = 2}}
local special = {name = "special:cliamp", visible = false}
local player = {class = "org.omarchy.cliamp.quake", mapped = true,
  address = "0xabc", monitor = monitor, floating = false,
  at = {x = 0, y = 0}, size = {x = 100, y = 100}, workspace = special}
local ordinary = {class = "org.omarchy.cliamp", mapped = true}
local first_resize = true
local windows, actions, events, listeners, launches = {ordinary, player}, {}, {}, {}, {}
local function action(kind, args) return {kind = kind, args = args} end
hl = {
  get_active_monitor = function() return monitor end,
  get_windows = function() return windows end,
  exec_scheduled_prop_refresh_immediately = function() end,
  workspace_rule = function() return {set_enabled = function() end} end,
  window_rule = function() return {set_enabled = function() end} end,
  on = function(event, callback)
    listeners[event] = callback
    return {remove = function() listeners[event] = nil end}
  end,
  timer = function(callback)
    return {callback = callback, set_enabled = function() end}
  end,
  exec_cmd = function(command, rules) launches[#launches + 1] = {command, rules} end,
  dsp = {
    event = function(data) return action("event", data) end,
    focus = function(args) return action("focus", args) end,
    window = {
      float = function(args) return action("float", args) end,
      resize = function(args) return action("resize", args) end,
      move = function(args) return action("move", args) end,
    },
    workspace = {toggle_special = function(name) return action("toggle", name) end},
  },
  dispatch = function(a)
    if a.kind == "event" then events[#events + 1] = a.args; return end
    actions[#actions + 1] = a
    if a.kind == "toggle" then
      special.visible = not special.visible
      monitor.active_special_workspace = special.visible and special or nil
    elseif a.kind == "float" then
      assert(a.args.window == "address:0xabc")
      player.floating = true
      player.size = {x = 1200, y = 600}
    elseif a.kind == "resize" then
      player.size = {x = a.args.x, y = a.args.y + (first_resize and 1 or 0)}
      first_resize = false
    elseif a.kind == "move" then
      player.at = {x = a.args.x, y = a.args.y}
    end
  end,
}
local client = dofile(arg[1])
client.install("test", "/tmp/player's launcher.sh", 0, "Left", 850, 425)
assert(player.floating and player.at.x == 1080 and player.at.y == 26)
assert(player.size.x == 850 and player.size.y == 425)
assert(ordinary.floating == nil)
player.size.y = 426
client.apply()
assert(player.size.y == 425, "an observed size adjustment must be corrected")
local event_count = #events
client.apply()
assert(#events == event_count, "unchanged observations must not flood the shell")
local count = #actions
client.configure("test", 1, "Left", 850, 425)
assert(#actions == count, "unchanged geometry must not dispatch a resize")
client.configure("test", 2, "Center", 850, 425)
assert(player.at.x == 1615)
client.configure("test", 3, "Right", 850, 425)
assert(player.at.x == 2150)

local portrait = {name = "portrait", id = 0, width = 1920, height = 1080,
  x = 0, y = 0, scale = 1, transform = 1,
  reserved = {left = 0, top = 26, right = 0, bottom = 0}}
player.monitor = portrait
listeners["workspace.move_to_monitor"]()
assert(player.at.x == 230 and player.size.x == 850 and player.size.y == 425)
client.configure("test", 4, "Center", 850, 625)
assert(player.at.x == 115 and player.size.y == 625)
assert(monitor.name == "landscape", "focus must not choose the client monitor")

local x, y, width, height = client.rectangle({width = 2400, height = 1600,
  transform = 0, scale = 2, x = -1200, y = 50,
  reserved = {left = 10, top = 30, right = 20, bottom = 40}}, "Right", 9999, 9999)
assert(x == -1190 and y == 80 and width == 1170 and height == 730)

count = #actions
client.toggle("landscape", 1)
assert(#actions == count, "a changed originating workspace must cancel the click")
client.toggle("portrait", 2)
assert(#actions == count, "a changed monitor must cancel the click")
client.toggle("landscape", 2)
assert(special.visible)
client.toggle("landscape", 2)
assert(not special.visible)

windows = {ordinary}
client.toggle()
client.toggle()
client.toggle()
assert(#launches == 1, "rapid cold toggles must launch only once")
assert(launches[1][2].workspace == "special:cliamp silent")
assert(launches[1][2].no_initial_focus)
assert(launches[1][1] == "bash '/tmp/player'\\''s launcher.sh'")
special.visible = false
windows = {player}
count = #actions
listeners["window.open"](player)
for i = count + 1, #actions do
  assert(actions[i].kind ~= "focus", "a late client must not reclaim focus")
end
client.stop("wrong-instance")
assert(_G.cliamp_control)
client.stop("test")
assert(not _G.cliamp_control and next(listeners) == nil)
print("ok - immediate geometry, monitor ownership, and guarded toggles")
