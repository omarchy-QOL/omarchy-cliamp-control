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

local function target(window)
  return "address:" .. window.address
end

-- Keep-open mode shows CLIamp as a pinned float on the regular workspace,
-- because Hyprland hides a special workspace once a regular window takes
-- focus and cycles windows only within the focused workspace.
local function pinned_shown(window)
  return window ~= nil and window.pinned == true and window.workspace ~= nil
    and window.workspace.name ~= workspace
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

local function place(window, monitor)
  local gaps, width, height = M.gaps(monitor,
    state.edge, state.placement, state.width, state.height)
  local reserved = monitor.reserved
  local x = monitor.x + reserved.left + gaps.left
  local y = monitor.y + reserved.top + gaps.top
  local key = table.concat({window.address, monitor.name, x, y, width, height},
    ":")
  if state.place_key == key then return end
  state.place_key = key
  hl.dispatch(hl.dsp.window.resize({x = width, y = height,
    window = target(window)}))
  hl.dispatch(hl.dsp.window.move({x = x, y = y, window = target(window)}))
end

local function show_pinned(window, monitor)
  local active = monitor.active_workspace
  if not active then return end
  if window.pinned then
    hl.dispatch(hl.dsp.window.pin({action = "disable", window = target(window)}))
  end
  hl.dispatch(hl.dsp.window.move({workspace = active.id > 0
    and tostring(active.id) or "name:" .. active.name,
    follow = false, window = target(window)}))
  hl.dispatch(hl.dsp.window.float({action = "enable", window = target(window)}))
  hl.dispatch(hl.dsp.window.pin({action = "enable", window = target(window)}))
  state.place_key = nil
  place(window, monitor)
  hl.dispatch(hl.dsp.focus({window = target(window)}))
end

-- Leaving the window tiled on the hidden workspace keeps the drop-down mode
-- valid if the setting changes while CLIamp is hidden.
local function hide_pinned(window)
  hl.dispatch(hl.dsp.window.pin({action = "disable", window = target(window)}))
  hl.dispatch(hl.dsp.window.move({workspace = workspace, follow = false,
    window = target(window)}))
  hl.dispatch(hl.dsp.window.float({action = "disable", window = target(window)}))
  state.place_key = nil
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
  local window = managed_window()
  if pinned_shown(window) and window.monitor then place(window, window.monitor) end
  if window then report("geometry", width, height)
  else report("absent") end
end

function M.apply(monitor)
  if not state or state ~= _G.cliamp_control or state.applying then return end
  state.applying = true
  local ok, error = pcall(fit, monitor)
  state.applying = false
  if not ok then report("error", tostring(error)) end
end

local function hide_overlay()
  local ws = hl.get_workspace(workspace)
  if ws and ws.visible then
    hl.dispatch(hl.dsp.workspace.toggle_special("cliamp"))
    hl.exec_scheduled_prop_refresh_immediately()
  end
end

function M.configure(epoch, revision, edge, placement, width, height,
    dim_background, keep_open)
  assert(state and state.epoch == epoch, "CLIamp controller is not installed")
  assert(edge == "Top" or edge == "Right" or edge == "Bottom" or edge == "Left")
  assert(placement == "Start" or placement == "Center" or placement == "End")
  assert(width >= 1 and width <= 9999 and width % 1 == 0)
  assert(height >= 1 and height <= 9999 and height % 1 == 0)
  state.revision, state.edge, state.placement, state.width, state.height =
    revision, edge, placement, width, height
  state.dim_background = dim_background == 1
  state.keep_open = keep_open == 1
  -- A mode change hides CLIamp; the next toggle shows it in the new mode.
  local window = managed_window()
  if state.keep_open then hide_overlay()
  elseif pinned_shown(window) then hide_pinned(window) end
  M.apply()
end

function M.hide()
  if not state then return end
  local window = managed_window()
  if pinned_shown(window) then hide_pinned(window) end
  hide_overlay()
  M.apply()
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
    dim_background, keep_open, config_reloaded)
  -- A config reload leaves Hyprland's copied dim on the visible workspace.
  local dim_shown = state ~= nil and config_reloaded == 1 and state.dim_shown
  if state then M.stop(state.epoch, config_reloaded) end
  state = {epoch = epoch, launcher = launcher, listeners = {},
    dim_overridden = false, dim_shown = dim_shown}
  _G.cliamp_control = state
  state.window_rule = hl.window_rule({name = "cliamp-control",
    match = {initial_class = "^org[.]omarchy[.]cliamp[.]quake$"},
    workspace = workspace .. " silent", no_initial_focus = true,
    border_size = 0})
  state.listeners[1] = hl.on("window.open", function(window)
    if not managed(window) then return end
    state.launching = false
    if state.launch_timer then state.launch_timer:set_enabled(false) end
    M.apply()
    if state.keep_open and state.show_on_open then
      state.show_on_open = false
      local monitor = hl.get_active_monitor()
      if monitor then show_pinned(window, monitor) end
      -- no_initial_focus applies after this event, so focus once it settles.
      state.open_focus_timer = hl.timer(function()
        if pinned_shown(managed_window()) then
          hl.dispatch(hl.dsp.focus({window = target(window)}))
        end
      end, {timeout = 50, type = "oneshot"})
    elseif window.workspace and window.workspace.visible then
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
    dim_background, keep_open)
end

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function launch()
  state.launching = true
  state.launch_timer = hl.timer(function()
    state.launching = false
    state.show_on_open = false
    report("error", "CLIamp window did not appear")
  end, {timeout = 5000, type = "oneshot"})
  hl.exec_cmd("bash " .. shell_quote(state.launcher) .. " "
      .. shell_quote(_G.cliamp_launch_args or ""), {
    workspace = workspace .. " silent", no_initial_focus = true,
  })
end

local function toggle_pinned(monitor)
  hide_overlay()
  local window = managed_window()
  if not window then
    state.show_on_open = true
    if not state.launching then launch() end
    return
  end
  if pinned_shown(window) then hide_pinned(window)
  else show_pinned(window, monitor) end
end

function M.toggle(monitor_name, origin_workspace)
  assert(state, "CLIamp controller is not installed")
  local monitor = hl.get_active_monitor()
  if not monitor then return end
  if monitor_name and (monitor.name ~= monitor_name
      or not monitor.active_workspace
      or monitor.active_workspace.id ~= origin_workspace) then return end
  if state.keep_open then
    toggle_pinned(monitor)
    return M.apply(monitor)
  end
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
    launch()
  end
  M.apply(monitor)
end

return M
