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

local function report(status, ...)
  local message = table.concat({
    "cliamp", state.epoch, state.revision, status, ...,
  }, ",")
  if state.last_report == message then return end
  state.last_report = message
  hl.dispatch(hl.dsp.event(message))
end

function M.gaps(monitor, alignment, width, height)
  local mw, mh = monitor.width, monitor.height
  if monitor.transform % 2 == 1 then mw, mh = mh, mw end
  local reserved = monitor.reserved
  local usable_width = math.max(1,
    math.floor(mw / monitor.scale - reserved.left - reserved.right))
  local usable_height = math.max(1,
    math.floor(mh / monitor.scale - reserved.top - reserved.bottom))
  width, height = math.min(width, usable_width), math.min(height, usable_height)
  local free = usable_width - width
  local left = alignment == "Right" and free
    or alignment == "Center" and math.floor(free / 2) or 0
  return {top = 0, right = free - left,
    bottom = usable_height - height, left = left}, width, height
end

local function fit(monitor)
  if not monitor then
    local ws = hl.get_workspace(workspace)
    monitor = ws and ws.visible and ws.monitor or hl.get_active_monitor()
  end
  if not monitor or not monitor.scale or monitor.scale <= 0 then return end
  local gaps, width, height = M.gaps(monitor,
    state.alignment, state.width, state.height)
  local key = table.concat({gaps.left, gaps.right, gaps.bottom}, ":")
  if state.gaps_key ~= key then
    state.gaps_key = key
    state.rule = hl.workspace_rule({workspace = workspace, gaps_in = 0,
      gaps_out = gaps, no_border = true, on_created_empty = ""})
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

function M.configure(epoch, revision, alignment, width, height)
  assert(state and state.epoch == epoch, "CLIamp controller is not installed")
  assert(alignment == "Left" or alignment == "Center" or alignment == "Right")
  assert(width >= 1 and width <= 99999 and width % 1 == 0)
  assert(height >= 1 and height <= 99999 and height % 1 == 0)
  state.revision, state.alignment, state.width, state.height =
    revision, alignment, width, height
  M.apply()
end

function M.hide()
  if not state then return end
  local ws = hl.get_workspace(workspace)
  if ws and ws.visible then
    hl.dispatch(hl.dsp.workspace.toggle_special("cliamp"))
    hl.exec_scheduled_prop_refresh_immediately()
  end
end

function M.stop(epoch)
  if not state or state.epoch ~= epoch then return end
  for _, listener in ipairs(state.listeners) do listener:remove() end
  if state.launch_timer then state.launch_timer:set_enabled(false) end
  if state.rule then state.rule:set_enabled(false) end
  state.window_rule:set_enabled(false)
  _G.cliamp_control = nil
end

function M.install(epoch, launcher, revision, alignment, width, height)
  if state then M.stop(state.epoch) end
  state = {epoch = epoch, launcher = launcher, listeners = {}}
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
  for _, event in ipairs({"workspace.special_active", "workspace.move_to_monitor"}) do
    state.listeners[#state.listeners + 1] = hl.on(event, function(ws, monitor)
      if ws and ws.name == workspace then M.apply(monitor) end
    end)
  end
  M.configure(epoch, revision, alignment, width, height)
end

function M.toggle(monitor_name, origin_workspace)
  assert(state, "CLIamp controller is not installed")
  local monitor = hl.get_active_monitor()
  if not monitor then return end
  if monitor_name and (monitor.name ~= monitor_name
      or not monitor.active_workspace
      or monitor.active_workspace.id ~= origin_workspace) then return end
  M.apply(monitor)
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
