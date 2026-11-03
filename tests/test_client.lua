local monitor = {name = "landscape", id = 1, width = 1920, height = 1200,
  x = 1080, y = 0, scale = 1, transform = 0,
  reserved = {left = 0, top = 26, right = 0, bottom = 0},
  active_workspace = {id = 2}}
local special = {name = "special:cliamp", visible = false, monitor = monitor}
local player = {class = "org.omarchy.cliamp.quake", mapped = true,
  address = "0xabc", monitor = monitor, floating = false,
  workspace = special}
local ordinary = {class = "org.omarchy.cliamp", mapped = true}
local windows, actions, events, listeners, launches, rules =
  {ordinary, player}, {}, {}, {}, {}, {}
local dim_special = 0.6
local function action(kind, args) return {kind = kind, args = args} end
local function handle() return {set_enabled = function(self, enabled) self.enabled = enabled end} end
hl = {
  get_active_monitor = function() return monitor end,
  get_workspace = function(name) return name == special.name and special or nil end,
  get_windows = function() return windows end,
  get_config = function(key)
    assert(key == "decoration.dim_special")
    return dim_special
  end,
  config = function(values) dim_special = values.decoration.dim_special end,
  exec_scheduled_prop_refresh_immediately = function() end,
  workspace_rule = function(rule)
    rules[#rules + 1] = rule
    local object = handle()
    object.enabled = true
    return object
  end,
  window_rule = function() local object = handle(); object.enabled = true; return object end,
  on = function(event, callback)
    listeners[event] = callback
    return {remove = function() listeners[event] = nil end}
  end,
  timer = function(callback)
    return {callback = callback, set_enabled = function() end}
  end,
  exec_cmd = function(command, launch_rules)
    launches[#launches + 1] = {command, rules = launch_rules}
  end,
  dsp = {
    event = function(data) return action("event", data) end,
    focus = function(args) return action("focus", args) end,
    workspace = {toggle_special = function(name) return action("toggle", name) end},
  },
  dispatch = function(value)
    if value.kind == "event" then events[#events + 1] = value.args; return end
    actions[#actions + 1] = value
    if value.kind == "toggle" then
      special.visible = not special.visible
      special.monitor = monitor
      monitor.active_special_workspace = special.visible and special or nil
    end
  end,
}

local client = dofile(arg[1])
client.install("test", "/tmp/player's launcher.sh", 0,
  "Top", "Start", 850, 425, 1, 0)
local rule = rules[#rules]
assert(rule.workspace == "special:cliamp" and rule.gaps_in == 0 and rule.no_border)
assert(rule.animation == "slide top")
assert(rule.gaps_out.left == 0 and rule.gaps_out.right == 1070)
assert(rule.gaps_out.top == 0 and rule.gaps_out.bottom == 749)
local written = #rules
client.configure("test", 1, "Top", "Start", 850, 425, 1)
assert(#rules == written, "unchanged geometry rewrote the workspace rule")
client.configure("test", 2, "Top", "Center", 850, 425, 1)
rule = rules[#rules]
assert(rule.gaps_out.left == 535 and rule.gaps_out.right == 535)
client.configure("test", 3, "Top", "End", 850, 425, 1)
rule = rules[#rules]
assert(rule.gaps_out.left == 1070 and rule.gaps_out.right == 0)
client.configure("test", 4, "Bottom", "Center", 850, 425, 1)
rule = rules[#rules]
assert(rule.animation == "slide bottom")
assert(rule.gaps_out.left == 535 and rule.gaps_out.right == 535)
assert(rule.gaps_out.top == 749 and rule.gaps_out.bottom == 0)
client.configure("test", 5, "Left", "Start", 850, 425, 1)
rule = rules[#rules]
assert(rule.animation == "slide left")
assert(rule.gaps_out.left == 0 and rule.gaps_out.right == 1070)
assert(rule.gaps_out.top == 0 and rule.gaps_out.bottom == 749)
client.configure("test", 6, "Right", "End", 850, 425, 1)
rule = rules[#rules]
assert(rule.animation == "slide right")
assert(rule.gaps_out.left == 1070 and rule.gaps_out.right == 0)
assert(rule.gaps_out.top == 749 and rule.gaps_out.bottom == 0)

local portrait = {name = "portrait", id = 0, width = 1920, height = 1080,
  x = 0, y = 0, scale = 1, transform = 1,
  reserved = {left = 0, top = 26, right = 0, bottom = 0},
  active_workspace = {id = 2}}
monitor = portrait
special.monitor = portrait
listeners["workspace.move_to_monitor"](special, portrait)
rule = rules[#rules]
assert(rule.gaps_out.left == 230 and rule.gaps_out.top == 1469)
client.configure("test", 7, "Left", "Center", 850, 625, 1)
rule = rules[#rules]
assert(rule.gaps_out.left == 0 and rule.gaps_out.right == 230)
assert(rule.gaps_out.top == 634 and rule.gaps_out.bottom == 635)

local gaps, width, height = client.gaps({width = 2400, height = 1600,
  transform = 0, scale = 2,
  reserved = {left = 10, top = 30, right = 20, bottom = 40}},
  "Right", "End", 9999, 9999)
assert(width == 1170 and height == 730)
assert(gaps.top == 0 and gaps.right == 0 and gaps.bottom == 0 and gaps.left == 0)

monitor = {name = "landscape", id = 1, width = 1920, height = 1200,
  scale = 1, transform = 0, reserved = {left = 0, top = 26, right = 0, bottom = 0},
  active_workspace = {id = 2}}
special.monitor = monitor
local count = #actions
client.toggle("landscape", 1)
assert(#actions == count, "a changed originating workspace must cancel the click")
client.toggle("portrait", 2)
assert(#actions == count, "a changed monitor must cancel the click")
client.toggle("landscape", 2)
assert(special.visible and dim_special == 0.6)
client.configure("test", 8, "Left", "Center", 850, 625, 0)
assert(dim_special == 0, "disabled dimming was not applied")
client.hide()
assert(not special.visible and dim_special == 0.6,
  "the original dim value was not restored")
client.toggle()
assert(special.visible and dim_special == 0)
special.visible = false
monitor.active_special_workspace = {name = "special:other"}
listeners["workspace.special_active"]({name = "special:other"}, monitor)
assert(dim_special == 0.6, "another special workspace did not restore dimming")
monitor.active_special_workspace = nil

windows = {ordinary}
client.toggle()
client.toggle()
client.toggle()
assert(#launches == 1, "rapid cold toggles must launch only once")
assert(launches[1].rules.workspace == "special:cliamp silent")
assert(launches[1].rules.no_initial_focus and launches[1].rules.float == nil)
assert(launches[1][1] == "bash '/tmp/player'\\''s launcher.sh'")
special.visible = false
monitor.active_special_workspace = nil
windows = {player}
count = #actions
listeners["window.open"](player)
for index = count + 1, #actions do
  assert(actions[index].kind ~= "focus", "a late client must not reclaim focus")
end
client.stop("wrong-instance")
assert(_G.cliamp_control)
client.stop("test")
assert(not _G.cliamp_control and next(listeners) == nil)
assert(dim_special == 0.6, "stop did not restore the original dim value")
print("ok - workspace gaps, monitor ownership, and guarded toggles")
