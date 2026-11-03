local M = {}
local class = "org.omarchy.cliamp.quake"
local workspace = "special:cliamp"
local state = _G.cliamp_control

local function managed(window)
  return window and (window.class == class or window.initial_class == class)
end

local function managed_window()
  for _, window in ipairs(hl.get_windows()) do
    if managed(window) then return window end
  end
end

local function set_undim(undim)
  if undim == state.dim_overridden then return end
  if undim then
    state.dim_restore = hl.get_config("decoration.dim_special") or 0
    hl.config({decoration = {dim_special = 0}})
  else
    hl.config({decoration = {dim_special = state.dim_restore}})
    state.dim_restore = nil
  end
  state.dim_overridden = undim
end

-- Hyprland copies dim_special when a special workspace activates, so a visible
-- workspace must reactivate to show a new value. toggle_special only acts on
-- the focused monitor; elsewhere the value shows once that monitor has focus.
local function sync_dim()
  local ws = hl.get_workspace(workspace)
  local visible = ws ~= nil and ws.visible == true
  local undim = visible and not state.dim_background
  set_undim(undim)
  if not visible then
    state.dim_shown = false
  elseif undim ~= state.dim_shown then
    local active = hl.get_active_monitor()
    if active and ws.monitor and active.name == ws.monitor.name then
      state.dim_shown = undim
      hl.dispatch(hl.dsp.workspace.toggle_special("cliamp"))
      hl.dispatch(hl.dsp.workspace.toggle_special("cliamp"))
      hl.exec_scheduled_prop_refresh_immediately()
    end
  end
end

local function report(status, ...)
  local message = table.concat({
    "cliamp", state.epoch, state.revision, status, ...,
  }, ",")
  if state.last_report == message then return end
  state.last_report = message
  hl.dispatch(hl.dsp.event(message))
end

function M.gaps(monitor, edge, placement, width, height)
  local mw, mh = monitor.width, monitor.height
  if monitor.transform % 2 == 1 then mw, mh = mh, mw end
  local reserved = monitor.reserved
  local usable_width = math.max(1,
    math.floor(mw / monitor.scale - reserved.left - reserved.right))
  local usable_height = math.max(1,
    math.floor(mh / monitor.scale - reserved.top - reserved.bottom))
  width, height = math.min(width, usable_width), math.min(height, usable_height)
  local horizontal = usable_width - width
  local vertical = usable_height - height
  local horizontal_edge = edge == "Top" or edge == "Bottom"
  local free = horizontal_edge and horizontal or vertical
  local offset = placement == "End" and free
    or placement == "Center" and math.floor(free / 2) or 0
  local left = horizontal_edge and offset
    or edge == "Right" and horizontal or 0
  local top = horizontal_edge and (edge == "Bottom" and vertical or 0)
    or offset
  return {top = top, right = horizontal - left,
    bottom = vertical - top, left = left}, width, height
end

local function fit(monitor)
  sync_dim()
  if not monitor then
    local ws = hl.get_workspace(workspace)
    monitor = ws and ws.visible and ws.monitor or hl.get_active_monitor()
  end
  if not monitor or not monitor.scale or monitor.scale <= 0 then return end
  local gaps, width, height = M.gaps(monitor,
    state.edge, state.placement, state.width, state.height)
  local animation = "slide " .. state.edge:lower()
  local key = table.concat({gaps.top, gaps.right, gaps.bottom, gaps.left,
    animation}, ":")
  if state.gaps_key ~= key then
    state.gaps_key = key
    state.rule = hl.workspace_rule({workspace = workspace, gaps_in = 0,
      gaps_out = gaps, no_border = true, animation = animation,
      on_created_empty = ""})
    hl.exec_scheduled_prop_refresh_immediately()
  end
  if managed_window() then report("geometry", width, height)
  else report("absent") end
end

function M.apply(monitor)
  if not state or state ~= _G.cliamp_control or state.applying then return end
  state.applying = true
  local ok, error = pcall(fit, monitor)
  state.applying = false
  if not ok then report("error", tostring(error)) end
end

function M.configure(epoch, revision, edge, placement, width, height,
    dim_background)
  assert(state and state.epoch == epoch, "CLIamp controller is not installed")
  assert(edge == "Top" or edge == "Right" or edge == "Bottom" or edge == "Left")
  assert(placement == "Start" or placement == "Center" or placement == "End")
  assert(width >= 1 and width <= 9999 and width % 1 == 0)
  assert(height >= 1 and height <= 9999 and height % 1 == 0)
  state.revision, state.edge, state.placement, state.width, state.height =
    revision, edge, placement, width, height
  state.dim_background = dim_background == 1
  M.apply()
end

function M.hide()
  if not state then return end
  local ws = hl.get_workspace(workspace)
  if ws and ws.visible then
    hl.dispatch(hl.dsp.workspace.toggle_special("cliamp"))
    hl.exec_scheduled_prop_refresh_immediately()
    M.apply()
  end
end

function M.stop(epoch, config_reloaded)
  if not state or state.epoch ~= epoch then return end
  if state.dim_overridden and config_reloaded ~= 1 then
    hl.config({decoration = {dim_special = state.dim_restore}})
  end
  for _, listener in ipairs(state.listeners) do listener:remove() end
  if state.launch_timer then state.launch_timer:set_enabled(false) end
  if state.rule then state.rule:set_enabled(false) end
  state.window_rule:set_enabled(false)
  _G.cliamp_control = nil
end

function M.install(epoch, launcher, revision, edge, placement, width, height,
    dim_background, config_reloaded)
  -- A config reload leaves Hyprland's copied dim on the visible workspace.
  local dim_shown = state ~= nil and config_reloaded == 1 and state.dim_shown
  if state then M.stop(state.epoch, config_reloaded) end
  state = {epoch = epoch, launcher = launcher, listeners = {},
    dim_overridden = false, dim_shown = dim_shown}
  _G.cliamp_control = state
  state.window_rule = hl.window_rule({name = "cliamp-control",
    match = {initial_class = "^org[.]omarchy[.]cliamp[.]quake$"},
    workspace = workspace .. " silent", no_initial_focus = true})
  state.listeners[1] = hl.on("window.open", function(window)
    if not managed(window) then return end
    state.launching = false
    if state.launch_timer then state.launch_timer:set_enabled(false) end
    M.apply()
    if window.workspace and window.workspace.visible then
      hl.dispatch(hl.dsp.focus({window = "address:" .. window.address}))
    end
  end)
  state.listeners[2] = hl.on("window.destroy", function(window)
    if managed(window) then M.apply() end
  end)
  state.listeners[3] = hl.on("monitor.layout_changed", M.apply)
  state.listeners[4] = hl.on("workspace.special_active", function(ws, monitor)
    M.apply(ws and ws.name == workspace and monitor or nil)
  end)
  state.listeners[5] = hl.on("workspace.move_to_monitor", function(ws, monitor)
    if ws and ws.name == workspace then M.apply(monitor) end
  end)
  -- Hyprland updates the focused monitor only after this event.
  state.listeners[6] = hl.on("monitor.focused", function()
    state.focus_timer = hl.timer(function() M.apply() end,
      {timeout = 1, type = "oneshot"})
  end)
  M.configure(epoch, revision, edge, placement, width, height,
    dim_background)
end

function M.toggle(monitor_name, origin_workspace)
  assert(state, "CLIamp controller is not installed")
  local monitor = hl.get_active_monitor()
  if not monitor then return end
  if monitor_name and (monitor.name ~= monitor_name
      or not monitor.active_workspace
      or monitor.active_workspace.id ~= origin_workspace) then return end
  M.apply(monitor)
  local open = monitor.active_special_workspace
  if not open or open.name ~= workspace then
    state.dim_shown = not state.dim_background
    set_undim(state.dim_shown)
  end
  hl.dispatch(hl.dsp.workspace.toggle_special("cliamp"))
  hl.exec_scheduled_prop_refresh_immediately()
  local visible = monitor.active_special_workspace
  if visible and visible.name == workspace
      and not state.launching and not managed_window() then
    state.launching = true
    state.launch_timer = hl.timer(function()
      state.launching = false
      report("error", "CLIamp window did not appear")
    end, {timeout = 5000, type = "oneshot"})
    hl.exec_cmd("bash '" .. state.launcher:gsub("'", "'\\''") .. "'", {
      workspace = workspace .. " silent", no_initial_focus = true,
    })
  end
  M.apply(monitor)
end

return M
