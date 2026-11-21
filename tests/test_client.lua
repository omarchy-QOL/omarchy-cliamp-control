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
-- Hyprland renders a copy of dim_special taken when the workspace activates.
local rendered_dim = 0
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
      rendered_dim = special.visible and dim_special or 0
      monitor.active_special_workspace = special.visible and special or nil
    end
  end,
}

local client = dofile(arg[1])
client.install("test", "/tmp/player's launcher.sh", 0,
  "Top", "Start", 850, 425, 1, 0, 0)
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
assert(special.visible and dim_special == 0.6 and rendered_dim == 0.6)
client.configure("test", 8, "Left", "Center", 850, 625, 0)
assert(dim_special == 0, "disabled dimming was not applied")
assert(special.visible and rendered_dim == 0,
  "disabling dimming did not reach the visible workspace")
client.hide()
assert(not special.visible and dim_special == 0.6,
  "the original dim value was not restored")
client.toggle()
assert(special.visible and dim_special == 0)
assert(rendered_dim == 0, "the workspace activated before dimming was disabled")
client.configure("test", 9, "Left", "Center", 850, 625, 1)
assert(special.visible and dim_special == 0.6 and rendered_dim == 0.6,
  "enabling dimming did not reach the visible workspace")
client.configure("test", 10, "Left", "Center", 850, 625, 0)
assert(special.visible and dim_special == 0 and rendered_dim == 0)
count = #actions
client.configure("test", 11, "Top", "Center", 850, 625, 0)
assert(#actions == count, "only a dim change may reactivate the workspace")

local home = monitor
monitor = {name = "elsewhere", id = 2, active_workspace = {id = 3}}
client.configure("test", 12, "Top", "Center", 850, 625, 1)
assert(special.monitor == home, "a dim change must not move the workspace")
assert(dim_special == 0.6 and rendered_dim == 0)
listeners["monitor.focused"](home)
assert(special.monitor == home and rendered_dim == 0,
  "the focus event fires before the focused monitor changes")
monitor = home
_G.cliamp_control.focus_timer.callback()
assert(special.monitor == home and rendered_dim == 0.6,
  "focusing the monitor did not catch up")

client.configure("test", 13, "Top", "Center", 850, 625, 0)
dim_special = 0.35
count = #actions
client.install("test", "/tmp/player's launcher.sh", 14,
  "Top", "Center", 850, 625, 0, 0, 1)
assert(dim_special == 0 and rendered_dim == 0 and #actions == count,
  "a config reload must not replay the workspace")
client.hide()
assert(dim_special == 0.35, "a reloaded user value was not restored")
client.toggle()
assert(special.visible and dim_special == 0 and rendered_dim == 0)
special.visible = false
monitor.active_special_workspace = {name = "special:other"}
listeners["workspace.special_active"]({name = "special:other"}, monitor)
assert(dim_special == 0.35, "another special workspace did not restore dimming")
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
-- Keep-open mode pins CLIamp on the regular workspace instead.
local active
hl.get_active_window = function() return active end
hl.dsp.window = {
  pin = function(args) return action("pin", args) end,
  move = function(args) return action("move", args) end,
  float = function(args) return action("float", args) end,
  resize = function(args) return action("resize", args) end,
}
local base_dispatch = hl.dispatch
hl.dispatch = function(value)
  base_dispatch(value)
  local args = value.args
  if type(args) ~= "table" then return end
  assert(args.window == nil or args.window == "address:0xabc")
  if value.kind == "pin" then player.pinned = args.action == "enable"
  elseif value.kind == "float" then player.floating = args.action == "enable"
  elseif value.kind == "resize" then player.size = {args.x, args.y}
  elseif value.kind == "move" and args.workspace then
    assert(args.follow == false)
    player.workspace = args.workspace == "special:cliamp" and special
      or {name = args.workspace}
  elseif value.kind == "move" then player.at = {args.x, args.y}
  elseif value.kind == "focus" then active = player end
end
monitor.x, monitor.y = 1080, 0

client.configure("test", 20, "Top", "Center", 850, 425, 1, 1)
client.toggle()
assert(not special.visible, "keep-open mode must not open the special workspace")
assert(player.pinned and player.floating and player.workspace.name == "2")
assert(player.size[1] == 850 and player.size[2] == 425)
assert(player.at[1] == 1615 and player.at[2] == 26, "pinned window misplaced")
assert(active == player and dim_special == 0.35)
active = ordinary
client.toggle()
assert(not player.pinned and not player.floating and player.workspace == special,
  "a shown pinned window must hide whether or not it has focus")
assert(active == ordinary, "hiding must not move focus")
client.toggle()
assert(player.pinned)
client.configure("test", 21, "Top", "Center", 850, 425, 1, 0)
assert(not player.pinned and player.workspace == special,
  "leaving keep-open mode must hide the pinned window")

client.configure("test", 22, "Top", "Center", 850, 425, 1, 1)
windows, active = {ordinary}, nil
local launched = #launches
client.toggle()
client.toggle()
assert(#launches == launched + 1 and not special.visible)
windows = {player}
listeners["window.open"](player)
assert(player.pinned and active == player, "a cold launch was not shown")

client.stop("wrong-instance")
assert(_G.cliamp_control)
client.stop("test")
assert(not _G.cliamp_control and next(listeners) == nil)
assert(dim_special == 0.35, "stop did not restore the original dim value")
print("ok - workspace gaps, monitor ownership, and guarded toggles")
